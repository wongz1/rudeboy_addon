--[[
    Commands.lua - /rudeboy (or /rb)

    /rb                          open the window
    /rb status                   status and help in chat
    /rb on | off                 hide chat lines or not
    /rb word add <w1, w2, ...>   filter words or phrases (comma separated, "*" is a wildcard)
    /rb word remove <word>
    /rb word list
    /rb player add [name]        no name = your target
    /rb player remove <name>
    /rb player list
    /rb guild add [guild]        no guild = your target's guild
    /rb guild remove <guild>
    /rb guild list
    /rb exempt add <name>        let a player through despite your player and guild lists
    /rb exempt remove <name>
    /rb exempt list
    /rb scan [guild]             /who your filtered guilds so their online members are learned;
                                 run it again for each next search (big guilds are split up)
    /rb check                    check your current group now
    /rb alerts on | off          group and invite warnings
    /rb decline party on | off   decline party invites from filtered people (also: /rb autodecline)
    /rb decline guild on | off   decline guild invites from filtered people or filtered guilds
    /rb reminder <minutes>       remind to scan when the last scan is older (30 to 720)
    /rb log [clear]              the last 20 hidden lines, with their text (or clear the list)
    /rb preview on | off         show would-be-hidden lines with a grey tag instead, for testing
    /rb test <text>              would this line be hidden?
    /rb debug                    how the game writes names: yours, your target's, recent senders
]]

local ADDON, ns = ...
local P = ns.Print

local HELP = {
    "/rb - open the window,  /rb status - this text",
    "/rb on | off - hide chat lines or not",
    "/rb word add <w1, w2, ...> | remove <word> | list",
    "/rb player add [name] | remove <name> | list   (no name = your target)",
    "/rb guild add [guild] | remove <guild> | list   (no guild = your target's guild)",
    "/rb exempt add <name> | remove <name> | list - let someone through despite the lists",
    "/rb scan [guild] - /who your guilds to learn who is in them (run again for each next search)",
    "/rb check - check your group now",
    "/rb alerts on | off,  /rb decline party on | off,  /rb decline guild on | off",
    "/rb reminder <minutes, 30 to 720>",
    "/rb log [clear] - the last hidden lines,  /rb preview on | off - tag lines instead of hiding",
    "/rb test <text> - would it be hidden?,  /rb debug - how the game writes names",
}

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function sortedValues(t)
    local list = {}
    for k, v in pairs(t) do list[#list + 1] = (v == true) and k or v end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

local function onOff(v) return v and "ON" or "OFF" end

local function printStatus()
    local db = ns.db
    P(("v%s. Hiding chat: %s. Warnings: %s. Decline party invites: %s. Decline guild invites: %s."):format(
        ns.VERSION, onOff(db.enabled), onOff(db.alerts), onOff(db.autoDecline), onOff(db.declineGuild)))
    P(("%d words, %d players, %d guilds filtered. Guilds known for %d players."):format(
        count(db.words), count(db.players), count(db.guilds), count(db.known)))
    P(("hidden %d lines this session, %d lifetime (%d by word, %d player, %d guild) since %s."):format(
        ns.hiddenSession, db.hiddenTotal, db.hiddenByKind.word, db.hiddenByKind.player, db.hiddenByKind.guild,
        db.countingSince))
    for _, line in ipairs(HELP) do P("  " .. line) end
end

local function printList(title, t)
    local list = sortedValues(t)
    if #list == 0 then
        P(title .. ": none.")
    else
        P(("%s (%d): %s"):format(title, #list, table.concat(list, ", ")))
    end
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

local function wordCmd(action, arg)
    if action == "add" or action == "remove" then
        local done = {}
        for piece in (arg .. ","):gmatch("([^,]*),") do
            if ns.Trim(piece) ~= "" then
                local w, err = (action == "add" and ns.AddWord or ns.RemoveWord)(piece)
                if w then done[#done + 1] = w else P(err) end
            end
        end
        if #done > 0 then
            P((action == "add" and "filtering: " or "no longer filtering: ") .. table.concat(done, ", "))
        elseif ns.Trim(arg) == "" then
            P(("usage: /rb word %s <word or phrase>, <another>"):format(action))
        end
    else
        printList("words", ns.db.words)
    end
end

-- Your target's name and guild, or nil and why not.
function ns.TargetInfo()
    if not (UnitExists("target") and UnitIsPlayer("target")) then return nil, nil, "target a player first." end
    local name, guild = ns.LearnUnit("target")
    return name, guild
end

local function playerCmd(action, arg)
    if action == "add" then
        local name, err = arg, nil
        if name == "" then
            local _
            name, _, err = ns.TargetInfo()
            if not name then P("usage: /rb player add <name>, or " .. err) return end
        end
        local added
        added, err = ns.AddPlayer(name)
        P(added and ("filtering player %s."):format(added) or err)
    elseif action == "remove" then
        local removed, err = ns.RemovePlayer(arg)
        P(removed and ("no longer filtering player %s."):format(removed) or err)
    else
        printList("players", ns.db.players)
    end
end

local function guildCmd(action, arg)
    if action == "add" then
        local guild = arg
        if guild == "" then
            local _, g = ns.TargetInfo()
            if not g then P("usage: /rb guild add <guild name>, or target a player who is in the guild.") return end
            guild = g
        end
        local added, err = ns.AddGuild(guild)
        if not added then P(err) return end
        P(("filtering guild <%s>."):format(added))
        -- adding came from your key press, so the first /who may go out right now
        if not added:find("*", 1, true) then ns.Scan(added) end
    elseif action == "remove" then
        local removed, err = ns.RemoveGuild(arg)
        P(removed and ("no longer filtering guild <%s>."):format(removed) or err)
    else
        printList("guilds", ns.db.guilds)
    end
end

local function exemptCmd(action, arg)
    if action == "add" then
        local name, err = arg, nil
        if name == "" then
            local _
            name, _, err = ns.TargetInfo()
            if not name then P("usage: /rb exempt add <name>, or " .. err) return end
        end
        local added
        added, err = ns.Exempt(name)
        P(added and ("%s is exempt: let through even if they or their guild are on your lists."):format(added) or err)
    elseif action == "remove" then
        local removed, err = ns.Unexempt(arg)
        P(removed and ("%s is no longer exempt."):format(removed) or err)
    else
        printList("exempt", ns.db.exempt)
    end
end

local function toggle(key, value, label)
    if value == "on" or value == "off" then ns.db[key] = (value == "on") ns.Changed() end
    P(("%s: %s."):format(label, onOff(ns.db[key])))
end

-- Shows every value a name function returns, quoted, so spaces and hyphens are visible.
local function quoted(...)
    local out = {}
    for i = 1, select("#", ...) do out[#out + 1] = ('"%s"'):format(tostring((select(i, ...)))) end
    return #out > 0 and table.concat(out, ", ") or "(nothing)"
end

local function printDebug()
    local _, _, _, toc = GetBuildInfo()
    P(("saved settings %s (seen at: %s%s); last saved %s; RudeBoyDB is %s"):format(
        ns.loadedFromDisk and "were found" or "were NOT found", tostring(ns.dbSeenAt or "never"),
        ns.restoredFromLink and ", via the linked Saved.lua" or "",
        tostring(ns.db.savedAt or "never"), RudeBoyDB == ns.db and "the addon's table" or "NOT the addon's table"))
    P(("interface %s, realm %s / %s"):format(tostring(toc), quoted(GetRealmName and GetRealmName()),
        quoted(GetNormalizedRealmName and GetNormalizedRealmName())))
    for _, unit in ipairs({ "player", "target" }) do
        if UnitExists(unit) then
            P(("%s: UnitName %s | GetUnitName %s | UnitFullName %s | matches as \"%s\""):format(unit,
                quoted(UnitName(unit)), quoted(GetUnitName and GetUnitName(unit, true)),
                quoted(UnitFullName and UnitFullName(unit)), ns.NormalizeName(ns.UnitFullName(unit))))
        end
    end
    if #ns.recentAuthors == 0 then P("no chat senders seen yet.") end
    for _, a in ipairs(ns.recentAuthors) do
        local names = ns.NamesFor(a.author, a.guid)
        table.remove(names, 1)
        P(("sender %s, by GUID %s, matches as \"%s\""):format(quoted(a.author), quoted(unpack(names)),
            ns.NormalizeName(a.author)))
    end
end

local function printLog(action)
    local log = ns.db.log
    if action == "clear" then
        for i = #log, 1, -1 do log[i] = nil end
        ns.Changed()
        P("hidden lines list cleared.")
        return
    end
    if #log == 0 then P("nothing hidden yet.") return end
    local first = math.max(1, #log - 19)
    P(("last %d of %d hidden lines (oldest first, all of them are on the window's Hidden tab):"):format(#log - first + 1, #log))
    for i = first, #log do
        local e = log[i]
        P(("  %s [%s] %s: %s  |cff999999(%s)|r"):format(e.at, tostring(e.where), tostring(e.author), tostring(e.msg), tostring(e.reason)))
    end
end

---------------------------------------------------------------------------

SLASH_RUDEBOY1 = "/rudeboy"
SLASH_RUDEBOY2 = "/rb"
SlashCmdList["RUDEBOY"] = function(input)
    if not ns.db then P("not loaded yet.") return end
    input = ns.Trim(input)
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local action, arg = rest:match("^(%S*)%s*(.-)$")
    action = action:lower()

    if cmd == "" or cmd == "ui" or cmd == "show" then
        ns.ToggleUI()
    elseif cmd == "status" or cmd == "help" then
        printStatus()
    elseif cmd == "on" or cmd == "off" then
        toggle("enabled", cmd, "hiding chat")
    elseif cmd == "word" or cmd == "words" then
        wordCmd(action, arg)
    elseif cmd == "player" or cmd == "players" then
        playerCmd(action, arg)
    elseif cmd == "guild" or cmd == "guilds" then
        guildCmd(action, arg)
    elseif cmd == "exempt" or cmd == "exempts" then
        exemptCmd(action, arg)
    elseif cmd == "scan" then
        ns.Scan(rest)
    elseif cmd == "check" then
        ns.CheckGroup(true)
    elseif cmd == "alerts" then
        toggle("alerts", action, "group alerts")
    elseif cmd == "autodecline" or (cmd == "decline" and action == "party") then
        toggle("autoDecline", cmd == "decline" and arg or action, "decline party invites from blocked people")
    elseif cmd == "decline" and action == "guild" then
        toggle("declineGuild", arg, "decline guild invites from blocked people and guilds")
    elseif cmd == "decline" then
        P("usage: /rb decline party on | off,  /rb decline guild on | off")
    elseif cmd == "reminder" then
        if action ~= "" then ns.SetReminder(tonumber(action)) end
        P("scan reminder: every " .. ns.FormatInterval(ns.db.reminderMinutes) .. ".")
    elseif cmd == "debug" then
        printDebug()
    elseif cmd == "log" then
        printLog(action)
    elseif cmd == "preview" then
        toggle("preview", action, "preview (show would-be-hidden lines with a tag)")
    elseif cmd == "test" then
        local why = ns.MatchWord(rest)
        P(why and ("would be hidden (word \"%s\")."):format(why) or "would be shown.")
    else
        P("unknown command. Type /rb for help.")
    end
end
