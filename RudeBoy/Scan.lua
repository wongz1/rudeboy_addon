--[[
    Scan.lua - /rb scan: learns who is in your filtered guilds with /who.

    One /who shows at most 50 people, so a search that comes back full is split up:
        whole guild  ->  one search per class  ->  that class by level range
    and the smaller searches are queued. Each /rb scan sends the next search in the queue
    (the game only lets an addon send /who from a key press or click, so it can't run on
    its own). With no guild name, /rb scan works through every guild on your list.

    Scan reminder: when a scan finishes its time is saved. At login, and every minute while
    you play, a chat reminder is printed if that is older than your reminder setting (30
    minutes to 12 hours), at most once per that interval.
]]

local ADDON, ns = ...
local P = ns.Print

local CAP = 50            -- the most people one /who shows
local TIMEOUT = 8         -- seconds to wait for an answer before sending the search again
local GAP = 6             -- the server allows about one /who this many seconds apart
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }
local LEVELS = { "1-29", "30-49", "50-59", "60-100" }

local queue = {}          -- searches still to send: { guild = , class = , level = }
local inflight            -- { search = , sentAt = } waiting for its answer
local lastSent = -GAP     -- GetTime() of the last /who sent

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
    lastSent = inflight.sentAt
    return true
end

-- The server answered "wait a moment before using /who again": that search was dropped.
function ns.ScanThrottled()
    if not inflight then return end
    table.insert(queue, 1, inflight.search)
    inflight = nil
    lastSent = GetTime()   -- the refusal restarts the server's timer
    P(("the server allows one /who every few seconds. Run /rb scan again in %d seconds (%d to go)."):format(GAP, #queue))
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
    if #queue == 0 then
        ns.db.lastScan = time()
        ns.Changed()
    end
end

-- Guild names to look up. /who g-"Crank" matches every guild containing the word, so each
-- keyword is one search that covers all of its guilds.
local function sortedGuilds()
    local list = {}
    for _, g in pairs(ns.db.guilds) do
        if not g:find("*", 1, true) then list[#list + 1] = g end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    local words = {}
    for _, w in pairs(ns.db.keywords) do words[#words + 1] = w end
    table.sort(words, function(a, b) return a:lower() < b:lower() end)
    for i = #words, 1, -1 do table.insert(list, 1, words[i]) end   -- keywords first
    return list
end

function ns.Scan(guild)
    local wait = GAP - (GetTime() - lastSent)
    if wait > 0 and not inflight then
        P(("the server allows one /who every few seconds; try again in %d second%s."):format(math.ceil(wait), math.ceil(wait) == 1 and "" or "s"))
        return
    end
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

---------------------------------------------------------------------------
-- Scan reminder
---------------------------------------------------------------------------

ns.REMINDER_MIN, ns.REMINDER_MAX, ns.REMINDER_STEP = 30, 720, 30   -- minutes
local FIRST_CHECK = 10    -- seconds after loading, so the reminder isn't lost in login messages
local CHECK_EVERY = 60

-- Rounds to the nearest step and keeps it in range.
function ns.SetReminder(minutes)
    local step = ns.REMINDER_STEP
    local m = math.floor(((tonumber(minutes) or ns.REMINDER_MAX) + step / 2) / step) * step
    ns.db.reminderMinutes = math.max(ns.REMINDER_MIN, math.min(ns.REMINDER_MAX, m))
    ns.Changed()
    return ns.db.reminderMinutes
end

function ns.FormatInterval(minutes)
    if minutes < 60 then return ("%d minutes"):format(minutes) end
    local h = minutes / 60
    if h == math.floor(h) then return ("%d hour%s"):format(h, h == 1 and "" or "s") end
    return ("%.1f hours"):format(h)
end

function ns.FormatAge(seconds)
    local m = math.floor(seconds / 60)
    if m < 60 then return ("%d minute%s"):format(m, m == 1 and "" or "s") end
    local h = math.floor(m / 60)
    return ("%d hour%s"):format(h, h == 1 and "" or "s")
end

local lastReminder    -- time() of the last reminder this session

function ns.CheckReminder()
    if not ns.db or #sortedGuilds() == 0 then return end
    local now = time()
    local interval = ns.db.reminderMinutes * 60
    local age = ns.db.lastScan and now - ns.db.lastScan
    if age and age < interval then return end
    if lastReminder and now - lastReminder < interval then return end
    lastReminder = now
    if age then
        P(("Your guild lists are %s old, run /rb scan."):format(ns.FormatAge(age)))
    else
        P("Your guild lists haven't been scanned yet, run /rb scan.")
    end
end

local ticker = CreateFrame("Frame")
ns.reminderFrame = ticker
local wait = FIRST_CHECK
ticker:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = CHECK_EVERY
    ns.CheckReminder()
end)
