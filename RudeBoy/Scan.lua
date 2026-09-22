--[[
    Scan.lua - /rb scan: learns who is in your filtered guilds with /who.

    One /who shows at most 50 people, so a search that comes back full is split up:
        whole guild  ->  one search per class  ->  that class by level range
    and the smaller searches are queued. Each /rb scan sends the next search in the queue
    (the game only lets an addon send /who from a key press or click, so it can't run on
    its own). With no guild name, /rb scan works through every guild on your list.
]]

local ADDON, ns = ...
local P = ns.Print

local CAP = 50            -- the most people one /who shows
local TIMEOUT = 8         -- seconds to wait for an answer before sending the search again
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local LEVELS = { "1-29", "30-49", "50-59", "60-100" }

local queue = {}          -- searches still to send: { guild = , class = , level = }
local inflight            -- { search = , sentAt = } waiting for its answer

function ns.WhoQuery(s)
    local q = ('g-"%s"'):format(s.guild)
    if s.class then q = q .. (' c-"%s"'):format(s.class) end
    if s.level then q = q .. " " .. s.level end
    return q
end

local function describe(s)
    local d = ("<%s>"):format(s.guild)
    if s.class then d = d .. " " .. s.class .. "s" end
    if s.level then d = d .. " level " .. s.level end
    return d
end

-- Paladins are Alliance only and Shamans Horde only, so the other faction's is skipped.
local function classesToSearch()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local list = {}
    for _, c in ipairs(CLASSES) do
        if not ((c == "Paladin" and faction == "Horde") or (c == "Shaman" and faction == "Alliance")) then
            list[#list + 1] = c
        end
    end
    return list
end

-- Queues the next finer searches for a full one, ahead of everything else. Returns how many.
local function split(s)
    local parts = {}
    if not s.class then
        for _, c in ipairs(classesToSearch()) do parts[#parts + 1] = { guild = s.guild, class = c } end
    elseif not s.level then
        for _, l in ipairs(LEVELS) do parts[#parts + 1] = { guild = s.guild, class = s.class, level = l } end
    end
    for i = #parts, 1, -1 do table.insert(queue, 1, parts[i]) end
    return #parts
end

local function send(s)
    local q = ns.WhoQuery(s)
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(q)
    elseif SendWho then
        SendWho(q)
    else
        P("/who is not available on this client.")
        return false
    end
    inflight = { search = s, sentAt = GetTime() }
    return true
end

local function remaining()
    return #queue == 0 and "Scan finished." or ("%d more to go, run /rb scan again."):format(#queue)
end

-- Called with the size of each /who answer. `total` is how many matched, which can be more
-- than the `num` shown.
function ns.ScanResults(num, total)
    if not inflight then return end
    local s = inflight.search
    inflight = nil
    local count = math.max(num or 0, total or 0)
    if count >= CAP and not s.level then
        local n = split(s)
        P(("%s: %d online, more than one /who shows. Split by %s into %d searches. %s"):format(
            describe(s), count, s.class and "level" or "class", n, remaining()))
    elseif count >= CAP then
        P(("%s: still %d online, some may be missed. %s"):format(describe(s), count, remaining()))
    else
        P(("%s: %d found. %s"):format(describe(s), count, remaining()))
    end
end

local function sortedGuilds()
    local list = {}
    for _, g in pairs(ns.db.guilds) do
        if not g:find("*", 1, true) then list[#list + 1] = g end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

function ns.Scan(guild)
    if inflight then
        if GetTime() - inflight.sentAt < TIMEOUT then
            P("still waiting for the last /who answer, try again in a moment.")
            return
        end
        table.insert(queue, 1, inflight.search)   -- no answer came, send it again
        inflight = nil
    end

    if guild ~= "" then
        if guild:find("*", 1, true) then
            P("a wildcard entry can't be looked up; give a full guild name.")
            return
        end
        -- Carry on with this guild's split searches if they are queued, else start it fresh.
        if not (queue[1] and ns.NormalizeGuild(queue[1].guild) == ns.NormalizeGuild(guild)) then
            queue = { { guild = guild } }
        end
    elseif #queue == 0 then
        for _, g in ipairs(sortedGuilds()) do queue[#queue + 1] = { guild = g } end
        if #queue == 0 then
            P("no guilds on your list to look up (wildcard entries can't be).")
            return
        end
    end

    local s = table.remove(queue, 1)
    if send(s) then P(("looking up %s..."):format(describe(s))) end
end
