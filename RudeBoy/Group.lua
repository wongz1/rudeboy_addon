--[[
    Group.lua - learns who is in which guild, and warns you (only you) about filtered people.

    Warnings:
      * someone on your lists invites you to a group (optionally declined for you)
      * someone on your lists, or a guild on your list, invites you to a guild (optionally declined)
      * someone on your lists is in your party or raid, when you join or they do

    Guilds are learned from your target, mouseover, nameplates, group members and /who
    results. Group members' guilds can load a moment after they join, so the group is
    checked again a couple of seconds after each change.
]]

local ADDON, ns = ...

local RECHECK_DELAYS = { 2, 6 }   -- seconds after a group change to look again

local warned = {}                 -- [normalized name] = true, cleared when you leave the group
local pending = {}                -- times (GetTime) at which to check the group again

---------------------------------------------------------------------------
-- Warnings
---------------------------------------------------------------------------

function ns.Alert(text)
    ns.Print("|cffff3333" .. text .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
    if PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    end
end

---------------------------------------------------------------------------
-- Learning guilds
---------------------------------------------------------------------------

local function learnUnit(unit)
    if not (UnitExists and UnitExists(unit)) then return end
    if UnitIsPlayer and not UnitIsPlayer(unit) then return end
    local name = ns.UnitFullName(unit)
    local guild = GetGuildInfo and GetGuildInfo(unit)
    if name and guild then ns.RememberGuild(name, guild) end
    return name, guild
end
ns.LearnUnit = learnUnit

local function learnWhoResults()
    local num, total
    if C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetWhoInfo then
        num, total = C_FriendList.GetNumWhoResults()
        for i = 1, num or 0 do
            local info = C_FriendList.GetWhoInfo(i)
            if info then ns.RememberGuild(info.fullName, info.fullGuildName or "") end
        end
    elseif GetNumWhoResults and GetWhoInfo then
        num, total = GetNumWhoResults()
        for i = 1, num or 0 do
            local name, guild = GetWhoInfo(i)
            ns.RememberGuild(name, guild or "")
        end
    end
    if ns.ScanResults then ns.ScanResults(num, total) end
end

-- Short /who answers are printed to chat instead of the Who window, as lines like
-- "|Hplayer:Name|h[Name]|h: Level 60 Human Warrior <Guild> - Zone" (English client),
-- ending with "3 players total".
function ns.LearnWhoLine(msg)
    if type(msg) ~= "string" then return end
    local name, rest = msg:match("^|Hplayer:([^|:]+)[^|]*|h.-|h: Level (.*)$")
    if name then
        ns.RememberGuild(name, rest:match("<(.-)>") or "")
        return
    end
    local total = tonumber(msg:match("^(%d+) players? total"))
    if total and ns.ScanResults then ns.ScanResults(total, total) end
end

---------------------------------------------------------------------------
-- Group check
---------------------------------------------------------------------------

local function groupUnits()
    local units = {}
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    return units
end

-- Checks everyone in your group. `verbose` also reports when nobody matched.
function ns.CheckGroup(verbose)
    local me = ns.NormalizeName(ns.UnitFullName("player"))
    local seen, found, members = {}, 0, 0
    for _, unit in ipairs(groupUnits()) do
        local name, guild = learnUnit(unit)
        local key = ns.NormalizeName(name)
        if name and key ~= me and not seen[key] then
            seen[key] = true
            members = members + 1
            local why = ns.PersonReason(name, guild, UnitGUID and UnitGUID(unit))
            if why then
                found = found + 1
                if verbose or not warned[key] then
                    warned[key] = true
                    ns.Alert(("%s is in your group (%s)."):format(name, why))
                end
            end
        end
    end
    if members == 0 then warned = {} end
    if verbose and found == 0 then
        ns.Print(members == 0 and "you are not in a group." or ("nobody on your lists among %d group members."):format(members))
    end
    return found
end

local function scheduleRechecks()
    local now = GetTime()
    for _, d in ipairs(RECHECK_DELAYS) do pending[#pending + 1] = now + d end
end

local function onInvite(inviter, guid)
    if not inviter then return end
    local why = ns.PersonReason(inviter, nil, guid)
    if not why then return end
    if ns.db.autoDecline and DeclineGroup then
        DeclineGroup()
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
        ns.Alert(("Declined a group invite from %s (%s)."):format(inviter, why))
    else
        ns.Alert(("%s is inviting you to a group (%s)."):format(inviter, why))
    end
end

-- A guild invite is blocked if the inviter is on your lists, or the guild itself is.
local function onGuildInvite(inviter, guildName)
    local why = inviter and ns.PersonReason(inviter)
    if not why and guildName and ns.IsGuildFiltered(guildName) then why = "guild on your list" end
    if not why then return end
    local who = ("%s <%s>"):format(tostring(inviter), tostring(guildName))
    if ns.db.declineGuild and DeclineGuild then
        DeclineGuild()
        if StaticPopup_Hide then StaticPopup_Hide("GUILD_INVITE") end
        ns.Alert(("Declined a guild invite from %s (%s)."):format(who, why))
    else
        ns.Alert(("%s is inviting you to their guild (%s)."):format(who, why))
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
ns.groupFrame = frame

local function register(event)
    -- Not every client has every event, and registering an unknown one is an error.
    pcall(frame.RegisterEvent, frame, event)
end

register("PLAYER_LOGIN")
register("PLAYER_LOGOUT")
register("ADDON_LOADED")
register("PLAYER_ENTERING_WORLD")

-- When the saved settings turned up, for /rb debug: "ADDON_LOADED", "PLAYER_LOGIN", "late (12s)"...
ns.dbSeenAt = nil
local watchUntil        -- GetTime() until which the global is watched for a late hand-over
local loginAt

-- One line at login saying whether saved settings came back from disk, to tell a saving
-- problem from a loading one.
local function announce()
    local db = ns.db
    local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    if ns.loadedFromDisk then
        ns.Print(("v%s: settings loaded (%d words, %d players, %d guilds, %d guild members known; last saved %s). /rb opens the window."):format(
            ns.VERSION, count(db.words), count(db.players), count(db.guilds), count(db.known), db.savedAt or "unknown"))
    else
        ns.Print(("v%s: no saved settings found on disk, starting fresh. /rb opens the window."):format(ns.VERSION))
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == ADDON and RudeBoyDB ~= nil and not ns.dbSeenAt then ns.dbSeenAt = "ADDON_LOADED" end
    elseif event == "PLAYER_LOGIN" then
        ns.loadedFromDisk = RudeBoyDB ~= nil
        if ns.loadedFromDisk and not ns.dbSeenAt then ns.dbSeenAt = "PLAYER_LOGIN" end
        ns.LoadDB()
        announce()
        loginAt = GetTime()
        if not ns.loadedFromDisk then watchUntil = loginAt + 60 end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if ns.AdoptLateDB() then
            ns.dbSeenAt = "PLAYER_ENTERING_WORLD"
            ns.loadedFromDisk = true
            ns.Print("the game handed over the saved settings late (at PLAYER_ENTERING_WORLD); adopted them.")
            announce()
        end
        for _, e in ipairs({
            "GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PARTY_INVITE_REQUEST",
            "GUILD_INVITE_REQUEST",
            "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
            "WHO_LIST_UPDATE", "CHAT_MSG_SYSTEM",
        }) do register(e) end
        ns.CheckGroup(false)
    elseif event == "PLAYER_LOGOUT" then
        if ns.db then ns.db.savedAt = date and date("%Y-%m-%d %H:%M") or "" end
    elseif event == "PARTY_INVITE_REQUEST" then
        -- the inviter's GUID is the 7th value on clients that send it
        local guid = select(7, ...)
        if ns.db.alerts or ns.db.autoDecline then onInvite((...), type(guid) == "string" and guid or nil) end
    elseif event == "GUILD_INVITE_REQUEST" then
        if ns.db.alerts or ns.db.declineGuild then onGuildInvite(...) end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        if ns.db.alerts then
            ns.CheckGroup(false)
            scheduleRechecks()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        learnUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        learnUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        learnUnit((...))
    elseif event == "WHO_LIST_UPDATE" then
        learnWhoResults()
    elseif event == "CHAT_MSG_SYSTEM" then
        ns.LearnWhoLine((...))
    end
end)

frame:SetScript("OnUpdate", function()
    if watchUntil then
        if ns.AdoptLateDB() then
            local secs = math.floor(GetTime() - (loginAt or GetTime()))
            ns.dbSeenAt = ("late (%ds after login)"):format(secs)
            ns.loadedFromDisk = true
            watchUntil = nil
            ns.Print(("the game handed over the saved settings %d seconds after login; adopted them."):format(secs))
            announce()
        elseif GetTime() > watchUntil then
            watchUntil = nil
        end
    end
    if #pending == 0 then return end
    local now = GetTime()
    local due = false
    for i = #pending, 1, -1 do
        if now >= pending[i] then
            table.remove(pending, i)
            due = true
        end
    end
    if due and ns.db and ns.db.alerts then ns.CheckGroup(false) end
end)
