--[[
    Scan.lua - /rb scan: learns who is in your filtered guilds with /who.

    One /who shows at most 50 people, so a search that comes back full is split up by level:
        whole guild  ->  ranges of ten levels  ->  a full range is halved, down to one level
    and the smaller searches are queued. (Class filters return nothing on WoW Forever.) The game only lets an addon send /who from inside a
    key press or mouse click, so the queue can't run on a timer; instead, while searches are
    queued, the next one is sent from whatever key press or click you make anyway, about six
    seconds apart, until the queue is empty. /rb scan (or the Scan button, or adding a guild)
    starts it. With no guild name it covers every keyword and guild on your list.

    Scans are quiet: the game's /who result lines are kept out of chat while one of these
    searches is in flight (they are still read), and the addon prints one line when a scan
    starts and one summary when it ends. /rb scanchat on shows every step instead. A /who you
    type yourself is never hidden.

    Scan reminder: when a scan finishes its time is saved. At login, and every minute while
    you play, a chat reminder is printed if that is older than your reminder setting (30
    minutes to 12 hours), at most once per that interval.
]]

local ADDON, ns = ...
local P = ns.Print

local CAP = 50            -- the most people one /who shows
local TIMEOUT = 8         -- seconds to wait for an answer before sending the search again
local GAP = 6             -- seconds between searches to begin with
local GAP_STEP = 4        -- added each time the server refuses a search for coming too soon
local GAP_MAX = 30
local MAX_REFUSALS = 6    -- a search refused this many times is skipped
local CHUNK = 10          -- levels per search when a guild is first split
local MAX_TRIES = 2       -- a search with no recognisable answer is dropped after this many sends

local queue = {}          -- searches still to send: { guild = , lo = , hi = , tries = }
local inflight            -- { search = , sentAt = } waiting for its answer
local gap = GAP           -- the current gap; grows when the server says "wait"
local lastSent = -GAP     -- GetTime() of the last /who sent
local stats = { pumps = 0, sent = 0, answers = 0, refusals = 0, last = "idle" }   -- for /rb debug
local remaining           -- defined below
local setListening        -- defined below: whether key presses are watched for sending the queue
local quietUntil = 0      -- result lines are hidden until this GetTime(), to cover an answer's last lines
local tally = { found = 0, searches = 0, capped = false, dropped = 0 }   -- for the summary of a quiet scan

local function quiet()
    return not (ns.db and ns.db.scanChat)
end

-- How many searches are still to be answered: the queue, plus the one in flight.
function ns.ScanPending()
    return #queue + (inflight and 1 or 0)
end

-- Where the scan stands, for /rb debug and for the saved file.
function ns.ScanState()
    local now = GetTime()
    return {
        queued = #queue,
        inflight = inflight and ns.WhoQuery(inflight.search) or "none",
        inflightAge = inflight and math.floor(now - inflight.sentAt) or 0,
        next = queue[1] and ns.WhoQuery(queue[1]) or "none",
        sinceLastSent = math.floor(now - lastSent),
        gap = gap,
        pumps = stats.pumps, sent = stats.sent, answers = stats.answers, refusals = stats.refusals,
        last = stats.last,
    }
end

local function note(what)
    stats.last = what
    if ns.db then ns.db.scanState = ns.ScanState() end
end

-- Progress lines, only shown with /rb scanchat on.
local function detail(msg)
    if not quiet() then P(msg) end
end

function ns.WhoQuery(s)
    local q = ('g-"%s"'):format(s.guild)
    if s.lo then q = q .. (" %d-%d"):format(s.lo, s.hi) end
    return q
end

local function describe(s)
    local d = ("<%s>"):format(s.guild)
    if s.lo then d = d .. (s.lo == s.hi and (" level %d"):format(s.lo) or (" levels %d-%d"):format(s.lo, s.hi)) end
    return d
end

local function maxLevel()
    local cap = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    return math.max(cap, (UnitLevel and UnitLevel("player")) or 1)
end

-- Queues smaller searches for a full one, ahead of everything else. Returns how many: a whole
-- guild becomes ranges of CHUNK levels, a range is halved, a single level can't be split.
local function split(s)
    local parts = {}
    if not s.lo then
        local top = maxLevel()
        for lo = 1, top, CHUNK do
            parts[#parts + 1] = { guild = s.guild, lo = lo, hi = math.min(lo + CHUNK - 1, top) }
        end
    elseif s.lo < s.hi then
        local mid = math.floor((s.lo + s.hi) / 2)
        parts[1] = { guild = s.guild, lo = s.lo, hi = mid }
        parts[2] = { guild = s.guild, lo = mid + 1, hi = s.hi }
    end
    for i = #parts, 1, -1 do table.insert(queue, 1, parts[i]) end
    return #parts
end

-- While one of the addon's searches is in flight, its answer is taken directly and the game's
-- Who window is kept from opening: the answer is asked for as an event rather than chat
-- lines, and the frames that would show it stop listening for it. Everything is handed back
-- as soon as the answer (or a refusal, or a timeout) arrives. If you have the Who window open
-- yourself, nothing is changed.
local silenced   -- frames whose WHO_LIST_UPDATE was switched off, to be switched back on

local function whoWindowOpen()
    return (WhoFrame and WhoFrame.IsVisible and WhoFrame:IsVisible()) and true or false
end

-- Second line of defence, for clients where the window opens some other way: while a search
-- is in flight and for a moment after its answer, a Who list that wasn't open when the search
-- was sent is closed as soon as it shows.
local openAtSend = false   -- the player had the Who list open themselves
local closeUntil = 0
local closer = CreateFrame("Frame")
closer:Hide()

local function topPanel(frame)
    while frame.GetParent and frame:GetParent() and frame:GetParent() ~= UIParent do frame = frame:GetParent() end
    return frame
end

local function rememberPopup(frame, how)
    if not ns.db then return end
    local list = ns.db.scanPopups or {}
    ns.db.scanPopups = list
    local name = (frame and frame.GetName and frame:GetName()) or tostring(frame)
    list[name .. " (" .. how .. ")"] = (list[name .. " (" .. how .. ")"] or 0) + 1
end

local function closeWhoWindow()
    if openAtSend or not whoWindowOpen() then return end
    local top = topPanel(WhoFrame)
    rememberPopup(top, "closed")
    if HideUIPanel then pcall(HideUIPanel, top) end
    if top.IsShown and top:IsShown() then pcall(top.Hide, top) end
end

closer:SetScript("OnUpdate", function(self)
    pcall(closeWhoWindow)
    if not inflight and GetTime() > closeUntil then self:Hide() end
end)

-- Any panel the game opens during a search is noted by name, so an unexpected one can be found.
if hooksecurefunc and ShowUIPanel then
    hooksecurefunc("ShowUIPanel", function(frame)
        if inflight or GetTime() < closeUntil then
            pcall(rememberPopup, frame, "opened")
            pcall(closeWhoWindow)
        end
    end)
end

local function silenceWhoWindow()
    openAtSend = whoWindowOpen()
    closer:Show()
    if silenced or openAtSend then return end
    silenced = {}
    for _, frame in ipairs({ FriendsFrame, WhoFrame }) do
        if frame and frame.IsEventRegistered and frame:IsEventRegistered("WHO_LIST_UPDATE") then
            frame:UnregisterEvent("WHO_LIST_UPDATE")
            silenced[#silenced + 1] = frame
        end
    end
    if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
end

local function restoreWhoWindow()
    closeUntil = GetTime() + 1.5
    pcall(closeWhoWindow)
    if not silenced then return end
    for _, frame in ipairs(silenced) do pcall(frame.RegisterEvent, frame, "WHO_LIST_UPDATE") end
    silenced = nil
    if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, false) end
end
ns.RestoreWhoWindow = restoreWhoWindow

local function send(s)
    local q = ns.WhoQuery(s)
    pcall(silenceWhoWindow)
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
    stats.sent = stats.sent + 1
    note("sent " .. q)
    if ns.RefreshPanel then ns.RefreshPanel() end
    return true
end

-- The search in flight got no answer in time: send it again, or give up on it after
-- MAX_TRIES so that one bad search can't hold up the queue for ever.
function ns.ScanUnanswered()
    if not inflight then return end
    local s = inflight.search
    inflight = nil
    pcall(restoreWhoWindow)
    s.tries = (s.tries or 1) + 1
    note("no answer to " .. ns.WhoQuery(s))
    if s.tries > MAX_TRIES then
        tally.dropped = tally.dropped + 1
        detail(("%s: no answer, skipped. %s"):format(describe(s), remaining()))
        if #queue == 0 then ns.ScanResults(nil, nil, true) end
    else
        table.insert(queue, 1, s)
    end
    if ns.RefreshPanel then ns.RefreshPanel() end
end

-- The server answered "wait a moment before using /who again": that search was dropped.
-- Each refusal widens the gap, since this server's limit isn't known; a search refused
-- MAX_REFUSALS times is skipped so the queue can't stall on it.
function ns.ScanThrottled()
    if not inflight then return end
    local s = inflight.search
    inflight = nil
    pcall(restoreWhoWindow)
    lastSent = GetTime()   -- the refusal restarts the server's timer
    quietUntil = lastSent + 1
    gap = math.min(gap + GAP_STEP, GAP_MAX)
    stats.refusals = stats.refusals + 1
    s.refused = (s.refused or 0) + 1
    note(("refused %s, gap now %ds"):format(ns.WhoQuery(s), gap))
    if s.refused >= MAX_REFUSALS then
        tally.dropped = tally.dropped + 1
        detail(("%s: refused %d times, skipped. %s"):format(describe(s), s.refused, remaining()))
        if #queue == 0 then ns.ScanResults(nil, nil, true) return end
    else
        table.insert(queue, 1, s)
        detail(("the server refused a search for coming too soon; waiting %d seconds between searches now. %d to go."):format(gap, #queue))
    end
    setListening(true)
    if ns.RefreshPanel then ns.RefreshPanel() end
end

remaining = function()
    return #queue == 0 and "Scan finished." or ("%d more to go, sent as you play."):format(#queue)
end

---------------------------------------------------------------------------
-- Sending the queue from your own key presses and clicks
---------------------------------------------------------------------------

local hardware   -- frame that sees key presses while searches are queued (keys pass through)

setListening = function(on)
    if hardware and hardware.propagates then pcall(hardware.EnableKeyboard, hardware, on) end
end

-- Called from a key press or click: sends the next queued search if the server's gap allows.
-- Never prints, since it runs on ordinary input.
local function pump()
    stats.pumps = stats.pumps + 1
    if not ns.db then return end
    if #queue == 0 and not inflight then setListening(false) return end
    if inflight then
        if GetTime() - inflight.sentAt < TIMEOUT then return end
        ns.ScanUnanswered()
    end
    if GetTime() - lastSent < gap then return end
    local s = table.remove(queue, 1)
    if not s then setListening(false) return end
    send(s)
end
ns.PumpScan = pump

local function createHardwareFrame()
    hardware = CreateFrame("Frame", "RudeBoyHardwareFrame", UIParent)
    hardware:EnableKeyboard(false)
    -- Only take keyboard input if the keys are certain to pass through to the game.
    local ok = pcall(hardware.SetPropagateKeyboardInput, hardware, true)
    hardware.propagates = ok and (not hardware.GetPropagateKeyboardInput or hardware:GetPropagateKeyboardInput()) and true or false
    hardware:SetScript("OnKeyDown", pump)
    if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", pump) end
end

-- Called with the size of each /who answer. `total` is how many matched, which can be more
-- than the `num` shown.
function ns.ScanResults(num, total, finishOnly)
    if not inflight and not finishOnly then return end
    local s = inflight and inflight.search or { guild = "" }
    inflight = nil
    pcall(restoreWhoWindow)
    local count = finishOnly and 0 or math.max(num or 0, total or 0)
    quietUntil = GetTime() + 1
    if not finishOnly then
        tally.searches = tally.searches + 1
        stats.answers = stats.answers + 1
        note(("answer to %s: %d"):format(ns.WhoQuery(s), count))
    end
    local parts = count >= CAP and split(s) or 0   -- its members are counted by the smaller searches
    if parts > 0 then
        detail(("%s: %d online, more than one /who shows. Split by level into %d searches. %s"):format(
            describe(s), count, parts, remaining()))
    elseif count >= CAP then
        tally.found = tally.found + CAP
        tally.capped = true
        detail(("%s: still %d online, some may be missed. %s"):format(describe(s), count, remaining()))
    elseif not finishOnly then
        tally.found = tally.found + count
        detail(("%s: %d found. %s"):format(describe(s), count, remaining()))
    end
    if #queue == 0 then
        ns.db.lastScan = time()
        ns.Changed()
        setListening(false)
        if quiet() then
            P(("Scan finished: %d online member%s of blocked guilds found in %d search%s.%s%s"):format(
                tally.found, tally.found == 1 and "" or "s", tally.searches, tally.searches == 1 and "" or "es",
                tally.capped and " One search was still full, so a few may be missed." or "",
                tally.dropped > 0 and (" %d got no answer."):format(tally.dropped) or ""))
        end
        tally = { found = 0, searches = 0, capped = false, dropped = 0 }
    else
        setListening(true)   -- split searches were queued
    end
    if ns.RefreshPanel then ns.RefreshPanel() end
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
    if not hardware then createHardwareFrame() end
    local busy
    if inflight and GetTime() - inflight.sentAt < TIMEOUT then
        busy = "still waiting for the last /who answer"
    elseif GetTime() - lastSent < gap then
        busy = "the server allows one /who every few seconds"
    elseif inflight then
        ns.ScanUnanswered()
    end

    if guild ~= "" then
        if guild:find("*", 1, true) then
            P("a wildcard entry can't be looked up; give a full guild name.")
            return
        end
        -- Carry on with this guild's split searches if they are next; otherwise put it at the
        -- front, ahead of whatever else is queued.
        if not (queue[1] and ns.NormalizeGuild(queue[1].guild) == ns.NormalizeGuild(guild)) then
            table.insert(queue, 1, { guild = guild })
        end
    elseif #queue == 0 then
        for _, g in ipairs(sortedGuilds()) do queue[#queue + 1] = { guild = g } end
        if #queue == 0 then
            P("no guilds or keywords on your list to look up (wildcard entries can't be).")
            return
        end
    end

    setListening(true)
    if busy then
        P(("%s; %d queued, sent as you play."):format(busy, #queue))
        if ns.RefreshPanel then ns.RefreshPanel() end
        return
    end
    local s = table.remove(queue, 1)
    if send(s) then
        if quiet() then
            P(("looking up %s%s. Results stay out of chat; a summary follows."):format(describe(s),
                #queue > 0 and (" and %d more"):format(#queue) or ""))
        else
            P(("looking up %s...%s"):format(describe(s), #queue > 0 and (" %d more will follow as you play."):format(#queue) or ""))
        end
    end
    if #queue == 0 then setListening(false) end
end

-- Turns one of the game's text templates ("%d |4player:players; total") into a Lua pattern.
-- The grammar code |4singular:plural; reaches addons either raw or already resolved, so
-- anything is accepted in its place.
local function patternFrom(template)
    if type(template) ~= "string" or template == "" then return nil end
    local p = template:gsub("%%%d+%$", "%%")                       -- "%1$s" -> "%s"
    p = p:gsub("|4[^;]-;", "\1")                                   -- mark the grammar code
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")               -- escape pattern characters
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")             -- "%s" and "%d" placeholders
    p = p:gsub("\1", ".-")
    return "^" .. p .. "$"
end

local patterns   -- built on first use, when the game's templates are certain to be loaded
local function whoPatterns()
    if not patterns then
        patterns = {
            total = patternFrom(WHO_NUM_RESULTS),
            guild = patternFrom(WHO_LIST_GUILD_FORMAT),
            plain = patternFrom(WHO_LIST_FORMAT),
        }
    end
    return patterns
end

-- What a system message is, if it belongs to /who:
--   "total", n            the closing line of an answer
--   "player", name, guild one result (guild "" when they have none)
--   "throttle"            the server refused the search
function ns.ParseWho(msg)
    if type(msg) ~= "string" then return nil end
    local pt = whoPatterns()

    local n = (pt.total and msg:match(pt.total)) or msg:match("^(%d+) players? total") or msg:match("^(%d+) |4[^;]-; total")
    if n then return "total", tonumber(n) end

    if pt.guild then
        local link, _, _, _, _, guild = msg:match(pt.guild)
        if link and guild then return "player", (link:gsub(":.*$", "")), guild end
    end
    if pt.plain then
        local link = msg:match(pt.plain)
        if link then return "player", (link:gsub(":.*$", "")), "" end
    end
    local name, rest = msg:match("^|Hplayer:([^|:]+)[^|]*|h.-|h: Level (.*)$")
    if name then return "player", name, rest:match("<(.-)>") or "" end

    local lower = msg:lower()
    if lower:find("/who", 1, true) and lower:find("wait", 1, true) then return "throttle" end
    return nil
end

-- Keeps the game's /who result lines out of chat while one of the addon's searches is in
-- flight. The addon's event handler still reads them; this only affects what is displayed.
function ns.WhoChatFilter(frame, event, msg)
    if not quiet() or type(msg) ~= "string" then return false end
    if not (inflight or GetTime() < quietUntil) then return false end
    return ns.ParseWho(msg) ~= nil
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ns.WhoChatFilter)

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
