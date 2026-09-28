--[[
    Runs the RudeBoy addon in a real Lua 5.1 interpreter against a mocked WoW API.
    WoW uses Lua 5.1, so use luajit or lua5.1 (on macOS: brew install luajit).

    usage (from the repo root): luajit tests/run.lua
]]

local ADDON_DIR = "RudeBoy/"

local FILES = {}
for line in io.lines(ADDON_DIR .. "RudeBoy.toc") do
    local file = line:match("^([^#%s].-%.lua)%s*$")
    -- Saved.lua is a link to a real save file on the developer's machine; tests never load it
    if file and file ~= "Saved.lua" then FILES[#FILES + 1] = (file:gsub("\\", "/")) end
end

local realPrint = print
local passed, failed = 0, 0
local function check(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        realPrint("FAIL: " .. label)
    end
end

---------------------------------------------------------------------------
-- Mock WoW environment. Every call to boot() gives a fresh addon instance.
-- env.units maps unit tokens to { name = , guild = }.
---------------------------------------------------------------------------

local function boot(opts)
    opts = opts or {}
    local env = { now = 1000, clock = 1700000000, prints = {}, alerts = {}, filters = {}, frames = {},
                  units = { player = { name = "Me Myself" } }, who = {}, declined = 0, lineID = 0 }

    _G.RudeBoyDB = opts.db
    _G.SlashCmdList = {}
    -- Frames record scripts, events, text, shown/checked/enabled state; any other method is a no-op.
    local methods = {}
    function methods:SetScript(k, fn) self.scripts[k] = fn end
    function methods:HookScript(k, fn)
        local prev = self.scripts[k]
        self.scripts[k] = function(...) if prev then prev(...) end fn(...) end
    end
    function methods:RegisterEvent(e) self.events[e] = true end
    function methods:Show()
        if self.shown then return end
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        if not self.shown then return end
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:IsShown() return self.shown end
    function methods:SetText(t) self.text = t end
    function methods:GetText() return self.text end
    function methods:SetChecked(v) self.checked = v and true or false end
    function methods:GetChecked() return self.checked end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetPoint() if self.point then return self.point[1], self.point[2], self.point[3] or self.point[1], self.point[4] or 0, self.point[5] or 0 end end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetHeight(h) self.height = h end
    function methods:EnableMouse(on) self.mouse = on and true or false end
    function methods:SetMovable(on) self.movable = on and true or false end
    function methods:EnableKeyboard(on) self.keyboard = on and true or false end
    function methods:GetPropagateKeyboardInput() return true end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end
    function methods:IsEnabled() return self.enabled end
    function methods:Click() if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self) end end
    local function mockFrame(name)
        local f = setmetatable({ scripts = {}, events = {}, shown = true, enabled = true, checked = false, text = "" },
            -- WoW methods are CapitalCase; other fields (entry, label...) stay nil until set
            { __index = function(_, k) return methods[k] or (type(k) == "string" and k:find("^%u") and function() end) or nil end })
        if name then _G[name] = f end
        return f
    end
    function methods:CreateFontString() return mockFrame() end
    function methods:CreateTexture() return mockFrame() end
    _G.UISpecialFrames = {}
    -- the tooltip: a frame whose GetUnit reports env.tooltipUnit, collecting added lines
    _G.TooltipDataProcessor, _G.Enum = nil, nil
    _G.GameTooltip = mockFrame()
    _G.GameTooltip.lines = {}
    _G.GameTooltip.GetUnit = function() return env.tooltipUnit and env.units[env.tooltipUnit].name, env.tooltipUnit end
    _G.GameTooltip.AddLine = function(self, text, r, g, b) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b } end
    _G.GameTooltip.HasScript = function() return true end
    _G.UIParent = mockFrame()
    _G.WorldFrame = mockFrame()
    _G.CreateFrame = function(_, name)
        local f = mockFrame(name)
        env.frames[#env.frames + 1] = f
        return f
    end
    _G.ChatFrame_AddMessageEventFilter = function(event, fn) env.filters[event] = fn end
    _G.GetTime = function() return env.now end
    _G.time = function() return env.clock end
    _G.date = function(fmt) return fmt == "%Y-%m-%d" and "2026-09-22" or "12:00" end
    _G.print = function(s) env.prints[#env.prints + 1] = s end
    _G.UnitGUID = function(unit) return unit == "player" and "Player-1-SELF" or nil end
    _G.UnitExists = function(unit) return env.units[unit] ~= nil end
    _G.UnitIsPlayer = function(unit) return env.units[unit] ~= nil end
    _G.UnitName = function(unit)
        local u = env.units[unit]
        if u then return u.name, u.second end
    end
    _G.GetGuildInfo = function(unit) return env.units[unit] and env.units[unit].guild end
    _G.RaidWarningFrame, _G.ChatTypeInfo = {}, { RAID_WARNING = {} }
    _G.RaidNotice_AddMessage = function(_, text) env.alerts[#env.alerts + 1] = text end
    _G.PlaySound = function() end
    _G.GetRealmName = function() return "Classic Beta PvP" end
    _G.GetBuildInfo = function() return "1.60.1", "1", "today", 16001 end
    env.guidNames = {}
    _G.GetPlayerInfoByGUID = function(guid)
        local n = env.guidNames[guid]
        if n then return "Warrior", "WARRIOR", "Human", "Human", 2, n, "" end
    end
    -- the game's own templates for /who lines, as on an English client
    _G.WHO_NUM_RESULTS = "%d |4player:players; total"
    _G.WHO_LIST_FORMAT = "|Hplayer:%s|h[%s]|h: Level %d %s %s - %s"
    _G.WHO_LIST_GUILD_FORMAT = "|Hplayer:%s|h[%s]|h: Level %d %s %s <%s> - %s"
    _G.GetMaxPlayerLevel = function() return opts.maxLevel or 60 end
    _G.UnitLevel = function() return opts.level or 60 end
    _G.UnitFactionGroup = function() return opts.faction or "Horde" end
    _G.DeclineGroup = function() env.declined = env.declined + 1 end
    _G.StaticPopup_Hide = function() end
    env.hooks, env.closed = {}, {}
    _G.hooksecurefunc = function(name, fn) env.hooks[name] = fn end
    _G.ShowUIPanel = function() end
    _G.HideUIPanel = function(frame) env.closed[#env.closed + 1] = frame env.whoWindowOpen = false end
    -- the game's Social window, which opens its Who list when it hears WHO_LIST_UPDATE
    _G.FriendsFrame = mockFrame()
    _G.FriendsFrame.events.WHO_LIST_UPDATE = true
    _G.FriendsFrame.IsEventRegistered = function(self, e) return self.events[e] == true end
    _G.FriendsFrame.UnregisterEvent = function(self, e) self.events[e] = nil end
    _G.WhoFrame = mockFrame()
    _G.WhoFrame.IsVisible = function() return env.whoWindowOpen or false end
    _G.WhoFrame.IsEventRegistered = function() return false end
    _G.C_FriendList = {
        SetWhoToUi = function(on) env.whoToUi = on end,
        SendWho = function(q) env.whoQuery = q end,
        GetNumWhoResults = function() return #env.who, env.whoTotal or #env.who end,
        GetWhoInfo = function(i) return env.who[i] end,
    }

    local ns = {}
    for _, file in ipairs(FILES) do
        assert(loadfile(ADDON_DIR .. file))("RudeBoy", ns)
    end
    env.ns = ns
    for _, f in ipairs(env.frames) do
        if f.events.PLAYER_LOGIN then env.events = f end
    end

    function env.fire(event, ...) env.events.scripts.OnEvent(env.events, event, ...) end
    function env.update() env.events.scripts.OnUpdate(env.events, 0.1) end
    env.fire("PLAYER_LOGIN")
    if not opts.quiet then ns.db.scanChat = true end   -- most tests read the scan's step-by-step lines

    -- Returns true if the line would be hidden. Each chat window runs the filter, so it is run twice.
    function env.chat(event, msg, author, guid)
        env.lineID = env.lineID + 1
        local fn = env.filters[event]
        local a = fn({}, event, msg, author, "", "", "", "", 0, 0, "", 0, env.lineID, guid or ("Player-1-" .. author))
        local b = fn({}, event, msg, author, "", "", "", "", 0, 0, "", 0, env.lineID, guid or ("Player-1-" .. author))
        assert(a == b, "every chat window gets the same answer")
        return a
    end
    -- answers the last /who with `total` matches, of which at most 50 are shown
    function env.whoAnswer(total, guild)
        env.now = env.now + 7   -- an answer takes a moment, and the next search must wait anyway
        env.who = {}
        for i = 1, math.min(total, 50) do env.who[i] = { fullName = "Member " .. i .. (env.whoQuery or ""), fullGuildName = guild } end
        env.whoTotal = total
        env.fire("WHO_LIST_UPDATE")
    end
    -- the raw filter call for one chat window, returning everything the filter returns
    function env.filterRaw(event, msg, author, lineID, channel)
        return env.filters[event]({}, event, msg, author, "", "", "", "", 0, 0, channel or "", 0, lineID, "Player-1-" .. author)
    end
    -- typing a command takes a human a few seconds, which also satisfies the /who gap
    function env.slash(input) env.now = env.now + 7 _G.SlashCmdList["RUDEBOY"](input) end
    function env.lastPrint() return env.prints[#env.prints] or "" end
    return env
end

---------------------------------------------------------------------------
-- Word patterns
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("word add dumb, go away, idiot*, *hole, jerk")
    local m = env.ns.MatchWord
    check(m("you are dumb") == "dumb", "whole word")
    check(m("DUMB!!!") == "dumb", "any case, punctuation after")
    check(m("dumbbell workout") == nil, "not inside a longer word")
    check(m("undumb") == nil, "not at the end of a longer word")
    check(m("duuuumb") == "dumb", "stretched letters")
    check(m("d.u.m.b") == "dumb", "letters split by dots")
    check(m("d u m b") == "dumb", "letters split by spaces")
    check(m("j3rk") == "jerk", "number stand-ins")
    check(m("please go away") == "go away", "phrase")
    check(m("goaway") == "go away", "phrase without its space")
    check(m("idiots everywhere") == "idiot*", "trailing wildcard")
    check(m("what a pothole") == "*hole", "leading wildcard")
    check(m("hello there friend") == nil, "ordinary chat passes")
    check(m("|cff9d9d9d|Hitem:1234::::|h[Dumb Sword]|h|r for sale") == "dumb", "text inside item links")
    check(m("LF2M dungeon 12345 gold") == nil, "numbers alone don't trip filters")

    env.slash("word remove dumb")
    check(m("you are dumb") == nil, "removed word stops matching")
    env.slash("word add ***")
    check(env.lastPrint():find("no letters"), "a wildcard-only entry is refused")
    check(env.ns.db.words["***"] == nil, "and not saved")
end

---------------------------------------------------------------------------
-- Chat hiding
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("word add badword")
    check(env.chat("CHAT_MSG_CHANNEL", "this has a badword in it", "Some One") == true, "channel line with a word is hidden")
    check(env.chat("CHAT_MSG_SAY", "nice day", "Some One") == false, "clean line is shown")
    check(env.chat("CHAT_MSG_SAY", "my badword", "Me Myself", "Player-1-SELF") == false, "own lines are never hidden")
    check(env.ns.hiddenSession == 1 and env.ns.db.hiddenTotal == 1, "hidden line counted once even with two chat windows")
    check(#env.ns.db.log == 1 and env.ns.db.log[1].author == "Some One", "hidden line logged")

    env.slash("player add Troll Face")
    check(env.chat("CHAT_MSG_WHISPER", "hi friend", "Troll Face-Stormrage") == true, "filtered player hidden, realm suffix ignored")
    check(env.chat("CHAT_MSG_YELL", "hi", "trollface") == true, "player match ignores case and spaces")

    env.slash("guild add Streamer Army")
    env.units.target = { name = "Minion One", guild = "Streamer Army" }
    env.fire("PLAYER_TARGET_CHANGED")
    check(env.chat("CHAT_MSG_SAY", "hello", "Minion One") == true, "member of a filtered guild is hidden once their guild is known")
    check(env.chat("CHAT_MSG_SAY", "hello", "Unknown Person") == false, "unknown guild is not hidden")

    env.slash("off")
    check(env.chat("CHAT_MSG_SAY", "badword", "Some One") == false, "/rb off shows everything")
    env.slash("on")
    check(env.chat("CHAT_MSG_SAY", "badword", "Some One") == true, "/rb on hides again")

    -- an error inside the filter must not break chat
    local real = env.ns.LineReason
    env.ns.LineReason = function() error("boom") end
    check(env.chat("CHAT_MSG_SAY", "badword", "Some One") == false, "an internal error shows the line")
    env.ns.LineReason = real

    for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER",
                             "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_EMOTE" }) do
        check(env.filters[event] ~= nil, "filters " .. event)
    end
end

---------------------------------------------------------------------------
-- Guilds: wildcards, /who, the cache
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("guild add Toxic*")
    check(env.ns.IsGuildFiltered("Toxic Legion") ~= nil, "guild wildcard matches")
    check(env.ns.IsGuildFiltered("toxic") ~= nil, "guild wildcard matches the bare prefix")
    check(env.ns.IsGuildFiltered("Not Toxic") == nil, "guild wildcard anchored at the start")

    env.slash("guild add Streamer Army")
    env.slash("scan Streamer Army")
    check(env.whoQuery == 'g-"Streamer Army"', "/rb scan sends a guild /who")

    env.who = { { fullName = "Fan One", fullGuildName = "Streamer Army" }, { fullName = "Ex Fan", fullGuildName = "" } }
    env.ns.RememberGuild("Ex Fan", "Streamer Army")
    env.fire("WHO_LIST_UPDATE")
    check(env.ns.GuildOf("Fan One") == "Streamer Army", "/who results are learned")
    check(env.ns.GuildOf("Ex Fan") == nil, "/who clears someone who left the guild")

    env.fire("CHAT_MSG_SYSTEM", "|Hplayer:Chat Fan|h[Chat Fan]|h: Level 60 Human Warrior <Streamer Army> - Orgrimmar")
    check(env.ns.GuildOf("Chat Fan") == "Streamer Army", "/who lines printed to chat are learned")

    env.units.mouseover = { name = "Passer By" }  -- guild not loaded
    env.ns.RememberGuild("Passer By", "Old Guild")
    env.fire("UPDATE_MOUSEOVER_UNIT")
    check(env.ns.GuildOf("Passer By") == "Old Guild", "a nil guild from the game does not erase what is known")

    env.slash("guild remove streamer army")
    check(env.ns.IsGuildFiltered("Streamer Army") == nil, "guild removed, any case")

    -- the cache survives a reload but forgets people not seen for 30 days
    local saved = env.ns.db
    local later = boot({ db = saved })
    check(later.ns.GuildOf("Fan One") == "Streamer Army", "known guilds are saved")
    saved.known[later.ns.NormalizeName("Fan One")].t = later.clock - 31 * 86400
    local muchLater = boot({ db = saved })
    check(muchLater.ns.GuildOf("Fan One") == nil, "old guild entries expire")
end

---------------------------------------------------------------------------
-- /rb scan: big guilds are split into smaller /who searches
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("guild add Big Guild")
    check(env.whoQuery == 'g-"Big Guild"', "adding a guild sends its first /who at once")
    env.whoAnswer(3, "Big Guild")
    env.whoQuery = nil
    env.slash("scan")
    check(env.whoQuery == 'g-"Big Guild"', "scan with no name starts with the whole guild")
    env.whoAnswer(12, "Big Guild")
    check(env.lastPrint():find("12 found") and env.lastPrint():find("Scan finished"), "a small guild takes one search")

    -- queued searches go out from ordinary key presses and clicks, six seconds apart
    env.slash("scan")
    env.whoAnswer(83, "Big Guild")
    check(env.lastPrint():find("Split by level into 6 searches") and env.lastPrint():find("sent as you play"), "a full answer queues searches by level range")
    local hw = _G.RudeBoyHardwareFrame
    check(hw and hw.keyboard == true, "the addon listens for key presses while searches are queued")
    env.whoQuery = nil
    hw.scripts.OnKeyDown(hw, "W")
    check(env.whoQuery == 'g-"Big Guild" 1-10', "a key press sends the next search")
    env.whoAnswer(10, "Big Guild")
    env.whoQuery = nil
    hw.scripts.OnKeyDown(hw, "W")
    check(env.whoQuery == 'g-"Big Guild" 11-20', "the answer plus the gap lets the next one go")
    env.whoQuery = nil
    hw.scripts.OnKeyDown(hw, "W")
    check(env.whoQuery == nil, "not while an answer is pending")
    env.whoAnswer(10, "Big Guild")
    env.now = env.now - 7   -- undo the answer's time jump: right after the answer is still inside the gap
    _G.WorldFrame.scripts.OnMouseDown(_G.WorldFrame, "LeftButton")
    check(env.whoQuery == nil, "not inside the six-second gap")
    env.now = env.now + 7
    _G.WorldFrame.scripts.OnMouseDown(_G.WorldFrame, "LeftButton")
    check(env.whoQuery == 'g-"Big Guild" 21-30', "a mouse click sends one too")
    for _ = 1, 10 do
        env.whoAnswer(10, "Big Guild")
        hw.scripts.OnKeyDown(hw, "W")
    end
    check(env.lastPrint():find("Scan finished") and hw.keyboard == false, "the queue empties by itself and listening stops")
    env.slash("scan")
    env.whoAnswer(12, "Big Guild")
    check(env.ns.GuildOf("Member 1" .. 'g-"Big Guild"') == "Big Guild", "members learned")

    env.slash("scan")
    env.whoAnswer(83, "Big Guild")
    check(env.lastPrint():find("83 online") and env.lastPrint():find("Split by level into 6 searches"), "a full guild is split into ranges of ten levels")
    local sent = {}
    for _ = 1, 30 do
        if env.lastPrint():find("Scan finished") then break end
        env.slash("scan")
        sent[#sent + 1] = env.whoQuery
        local q = env.whoQuery
        -- 51-60 is full, then 56-60, then 58-60, then 60 alone stays full
        local full = q:find(" 51%-60$") or q:find(" 56%-60$") or q:find(" 59%-60$") or q:find(" 60%-60$")
        env.whoAnswer(full and 60 or 10, "Big Guild")
        if q:find(" 51%-60$") then check(env.lastPrint():find("Split by level into 2 searches"), "a full range is halved") end
        if q:find(" 60%-60$") then check(env.lastPrint():find("still 60 online, some may be missed"), "a single full level can't be split further") end
    end
    check(env.lastPrint():find("Scan finished"), "the queue runs out")
    check(table.concat(sent, "|") == table.concat({
        'g-"Big Guild" 1-10', 'g-"Big Guild" 11-20', 'g-"Big Guild" 21-30', 'g-"Big Guild" 31-40', 'g-"Big Guild" 41-50',
        'g-"Big Guild" 51-60', 'g-"Big Guild" 51-55', 'g-"Big Guild" 56-60', 'g-"Big Guild" 56-58', 'g-"Big Guild" 59-60',
        'g-"Big Guild" 59-59', 'g-"Big Guild" 60-60' }, "|"), "ranges in order, halves right after the full range")
    check(not table.concat(sent, "|"):find("c%-"), "no class filters (they return nothing on WoW Forever)")

    -- a higher level cap is covered
    local cap = boot({ maxLevel = 70 })
    cap.slash("guild add Big Guild")
    cap.whoAnswer(70, "Big Guild")
    check(cap.lastPrint():find("Split by level into 7 searches"), "the client's level cap sets the ranges")

    -- the lines the game prints for small answers, raw and as displayed
    local raw = boot()
    raw.slash("guild add Big Guild")
    raw.fire("CHAT_MSG_SYSTEM", "|Hplayer:Hermaeus Xarxes|h[Hermaeus Xarxes]|h: Level 12 Dwarf Warrior <Big Guild> - Dun Morogh")
    raw.fire("CHAT_MSG_SYSTEM", "|Hplayer:Lone Wolf|h[Lone Wolf]|h: Level 3 Gnome Mage - Dun Morogh")
    check(raw.ns.GuildOf("Hermaeus Xarxes") == "Big Guild", "a result line with a guild is read")
    check(raw.ns.db.known[raw.ns.NormalizeName("Lone Wolf")].g == "", "a result line without a guild is read as unguilded")
    raw.fire("CHAT_MSG_SYSTEM", "2 |4player:players; total")
    check(raw.lastPrint():find("2 found") and raw.lastPrint():find("Scan finished"), "the total line is recognised with its grammar code unresolved")
    for _, line in ipairs({ "0 players total", "1 player total", "0 |4player:players; total" }) do
        local kind, n = raw.ns.ParseWho(line)
        check(kind == "total" and n == tonumber(line:match("^%d+")), "total line: " .. line)
    end
    check(raw.ns.ParseWho("Some One has come online.") == nil and raw.ns.ParseWho("12 players in queue") == nil, "other system lines are not /who lines")

    -- the server keeps refusing: the gap widens each time, and the queue still gets through
    local slow = boot()
    slow.slash("guild add Alpha")
    local hw3 = _G.RudeBoyHardwareFrame
    slow.fire("CHAT_MSG_SYSTEM", "You must wait a moment before using /who again.")
    check(slow.ns.ScanState().gap == 10 and slow.ns.ScanPending() == 1, "a refusal widens the gap and keeps the search")
    slow.whoQuery = nil
    slow.now = slow.now + 7
    hw3.scripts.OnKeyDown(hw3, "W")
    check(slow.whoQuery == nil, "the wider gap is respected")
    slow.now = slow.now + 4
    hw3.scripts.OnKeyDown(hw3, "W")
    check(slow.whoQuery == 'g-"Alpha"', "then the search goes out again")
    for _ = 1, 5 do
        slow.fire("CHAT_MSG_SYSTEM", "You must wait a moment before using /who again.")
        slow.now = slow.now + 31
        hw3.scripts.OnKeyDown(hw3, "W")
    end
    check(slow.ns.ScanPending() == 0 and slow.ns.ScanState().refusals == 6, "a search refused six times is skipped, so the queue can't stall")
    slow.slash("debug")
    check(table.concat(slow.prints, "\n"):find("scan: 0 queued, in flight none"), "/rb debug shows the scan's state")
    check(slow.ns.db.scanState and slow.ns.db.scanState.last:find("refused"), "and the state is kept in the saved data")

    -- a search that never gets an answer is sent twice, then dropped
    local lost = boot()
    lost.slash("guild add Alpha")
    lost.whoAnswer(1, "Alpha")
    lost.slash("guild add Beta")
    local hw2 = _G.RudeBoyHardwareFrame
    lost.ns.Scan("Alpha")            -- queued behind the unanswered Beta search
    lost.whoQuery = nil
    lost.now = lost.now + 9
    hw2.scripts.OnKeyDown(hw2, "W")
    check(lost.whoQuery == 'g-"Beta"', "an unanswered search is sent a second time")
    lost.whoQuery = nil
    lost.now = lost.now + 9
    hw2.scripts.OnKeyDown(hw2, "W")
    check(lost.whoQuery == 'g-"Alpha"' and lost.ns.ScanPending() == 1, "after two tries it is dropped and the queue moves on")
    lost.whoAnswer(1, "Alpha")
    check(lost.ns.ScanPending() == 0, "and the scan still finishes")

    -- several guilds, one search each run; waits for answers; resends a lost search
    local multi = boot()
    multi.slash("guild add Alpha")
    multi.whoAnswer(1, "Alpha")     -- adding looks each guild up at once; answer so the next can go
    multi.slash("guild add Beta")
    multi.whoAnswer(1, "Beta")
    multi.slash("guild add Gamma*")
    check(multi.whoQuery == 'g-"Beta"', "a wildcard guild is not looked up when added")
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Alpha"', "first guild")
    multi.slash("scan")
    check(multi.lastPrint():find("still waiting"), "won't send over an unanswered search")
    multi.fire("CHAT_MSG_SYSTEM", "You must wait a moment before using /who again.")
    check(multi.lastPrint():find("refused a search for coming too soon; waiting 10 seconds") and multi.ns.ScanPending() == 2,
        "the server's wait message puts the search back, widens the gap and says so")
    multi.ns.Scan("")   -- straight away, no time passing
    check(multi.lastPrint():find("every few seconds; %d queued"), "and a scan inside the gap just keeps the queue")
    multi.now = multi.now + 7
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Alpha"', "after the wider gap the dropped search goes out again")
    multi.slash("scan")
    check(multi.lastPrint():find("still waiting"), "(back to waiting for its answer)")
    multi.now = multi.now + 10
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Alpha"', "a search with no answer is sent again")
    multi.whoAnswer(3, "Alpha")
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Beta"', "then the next guild, wildcards skipped")
    multi.fire("CHAT_MSG_SYSTEM", "2 players total")
    check(multi.lastPrint():find("2 found") and multi.lastPrint():find("Scan finished"), "answers printed to chat count too")

    -- a guild added mid-scan goes to the front; the rest of the queue is kept
    multi.now = multi.now + 5                 -- the gap is 10 seconds now
    multi.slash("scan")                       -- Alpha again (fresh queue: Alpha, Beta)
    multi.whoAnswer(1, "Alpha")
    multi.slash("guild add Delta")            -- Delta jumps the queue
    check(multi.whoQuery == 'g-"Delta"', "a guild added during a scan is looked up next")
    multi.whoAnswer(1, "Delta")
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Beta"', "and the rest of the queue carries on")

    -- naming a guild repeatedly carries on with its queued searches
    local named = boot()
    named.slash("guild add Big Guild")
    named.slash("scan big guild")
    named.whoAnswer(90, "Big Guild")
    named.slash("scan Big Guild")
    check(named.whoQuery == 'g-"Big Guild" 1-10', "/rb scan <guild> again continues the split")
end

---------------------------------------------------------------------------
-- Group warnings
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("guild add Streamer Army")
    env.slash("player add Bad Actor")

    env.fire("PARTY_INVITE_REQUEST", "Bad Actor")
    check(#env.alerts == 1 and env.alerts[1]:find("Bad Actor is inviting you"), "warned about an invite from a filtered player")
    check(env.declined == 0, "invite not declined by default")

    env.slash("autodecline on")
    env.fire("PARTY_INVITE_REQUEST", "Bad Actor")
    check(env.declined == 1 and env.alerts[2]:find("Declined"), "autodecline declines filtered invites")
    env.fire("PARTY_INVITE_REQUEST", "Nice Person")
    check(env.declined == 1 and #env.alerts == 2, "other invites are left alone")

    -- guild invites: from a blocked person, or from a blocked guild
    _G.DeclineGuild = function() env.guildDeclined = (env.guildDeclined or 0) + 1 end
    env.fire("GUILD_INVITE_REQUEST", "Bad Actor", "Some Guild")
    check(#env.alerts == 3 and env.alerts[3]:find("Bad Actor <Some Guild> is inviting you to their guild %(player on your list%)"), "warned about a guild invite from a blocked person")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(#env.alerts == 4 and env.alerts[4]:find("guild on your list"), "warned about a guild invite from a blocked guild")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Nice Guild")
    check(#env.alerts == 4 and not env.guildDeclined, "other guild invites are left alone, nothing declined yet")
    env.slash("decline guild on")
    check(env.ns.db.declineGuild == true, "/rb decline guild on")
    _G.GuildInviteFrame = { Hide = function(self) self.hidden = true end }
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(env.guildDeclined == 1 and env.alerts[5]:find("Declined a guild invite"), "guild invite from a blocked guild declined")
    check(_G.GuildInviteFrame.hidden, "the guild invite frame is closed too")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Nice Guild")
    check(env.guildDeclined == 1, "guild invites from others still not declined")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", 123, "Streamer Army")
    check(env.guildDeclined == 2, "the guild name is found even when it isn't the second value")
    _G.DeclineGuild = nil
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(env.alerts[#env.alerts]:find("no way to decline"), "says so when the client can't decline")
    _G.C_GuildInfo = { DeclineGuild = function() env.guildDeclined = env.guildDeclined + 1 end }
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(env.guildDeclined == 3, "falls back to C_GuildInfo.DeclineGuild")
    _G.DeclineGuild = function() env.guildDeclined = env.guildDeclined + 1 end
    env.slash("debug")
    check(table.concat(env.prints, "\n"):find('last guild invite event: "Nice Person", "Streamer Army"', 1, true), "/rb debug shows the last guild invite")
    env.slash("decline party off")
    check(env.ns.db.autoDecline == false, "/rb decline party off")
    env.slash("autodecline on")
    check(env.ns.db.autoDecline == true, "/rb autodecline still works")
    for i = #env.alerts, 3, -1 do env.alerts[i] = nil end   -- back to the two party-invite alerts for the checks below

    env.units.party1 = { name = "Nice Person" }
    env.units.party2 = { name = "Guild Minion", guild = "Streamer Army" }
    env.fire("GROUP_ROSTER_UPDATE")
    check(#env.alerts == 3 and env.alerts[3]:find("Guild Minion is in your group %(guild <Streamer Army>%)"), "warned about a filtered guild member in the group")
    env.fire("GROUP_ROSTER_UPDATE")
    check(#env.alerts == 3, "each person is only warned about once per group")

    -- guild info that loads late is caught by the recheck
    env.units.party3 = { name = "Slow Loader" }
    env.fire("GROUP_ROSTER_UPDATE")
    env.units.party3.guild = "Streamer Army"
    env.now = env.now + 3
    env.update()
    check(#env.alerts == 4 and env.alerts[4]:find("Slow Loader"), "rechecked after the guild loads")

    -- raid units, and the player's own raid slot is skipped
    env.units.party1, env.units.party2, env.units.party3 = nil, nil, nil
    env.units.raid1 = { name = "Me Myself", guild = "Streamer Army" }
    env.units.raid2 = { name = "Bad Actor" }
    env.fire("GROUP_ROSTER_UPDATE")
    check(#env.alerts == 5 and env.alerts[5]:find("Bad Actor"), "raid members are checked, not yourself")

    -- leaving the group resets who has been warned about
    env.units.raid1, env.units.raid2 = nil, nil
    env.fire("GROUP_ROSTER_UPDATE")
    env.units.party1 = { name = "Guild Minion", guild = "Streamer Army" }
    env.fire("GROUP_ROSTER_UPDATE")
    check(#env.alerts == 6, "warned again in a new group")

    env.slash("check")
    check(#env.alerts == 7, "/rb check always reports")

    env.slash("alerts off")
    env.units.party2 = { name = "Bad Actor" }
    env.fire("GROUP_ROSTER_UPDATE")
    check(#env.alerts == 7, "/rb alerts off stops group warnings")
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("status")
    check(env.prints[1]:find("v" .. env.ns.VERSION:gsub("%.", "%%."), 1) ~= nil, "/rb status prints the version")

    env.slash("player add")
    check(env.lastPrint():find("usage"), "player add with no target explains itself")
    env.units.target = { name = "Target Troll", guild = "Bad Guild" }
    env.slash("player add")
    check(env.ns.IsPlayerFiltered("Target Troll"), "player add uses the target")
    env.slash("guild add")
    check(env.ns.IsGuildFiltered("Bad Guild"), "guild add uses the target's guild")

    env.slash("player remove target troll")
    check(not env.ns.IsPlayerFiltered("Target Troll"), "player remove, any case")

    env.slash("word add Some Phrase")
    env.slash("word list")
    check(env.lastPrint():find("some phrase"), "word list shows entries")
    env.slash("test well some phrase here")
    check(env.lastPrint():find("would be hidden"), "/rb test reports a match")

    env.slash("log")
    check(env.lastPrint():find("nothing hidden"), "empty log")
    env.chat("CHAT_MSG_SAY", "some phrase", "Loud Mouth")
    env.slash("log")
    check(env.lastPrint():find("Loud Mouth") and env.lastPrint():find("say"), "log shows the hidden line")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("word add secretword, other")
    env.slash("")
    local ui = env.ns.ui
    check(ui.frame and ui.frame:IsShown(), "/rb opens the window")

    local function labels()
        local out = {}
        for _, row in ipairs(ui.rows) do if row:IsShown() then out[#out + 1] = row.label:GetText() end end
        return table.concat(out, ",")
    end
    check(labels() == "********,********", "words are masked when the window opens")
    check(ui.count:GetText() == "2 words (hidden)", "word count shown while masked")
    ui.reveal:Click()
    check(labels() == "other,secretword", "Show reveals the words")
    check(ui.reveal:GetText() == "Hide", "the button then says Hide")
    ui.reveal:Click()
    check(labels() == "********,********", "Hide masks them again")
    ui.reveal:Click()
    ui.frame:Hide()
    env.slash("")
    check(labels() == "********,********", "reopening the window masks the words again")

    ui.input:SetText("newword, another")
    ui.add:Click()
    check(env.ns.db.words.newword and env.ns.db.words.another, "Add adds comma separated words")
    check(ui.status:GetText() == "Added 2 words." and ui.input:GetText() == "", "adding words doesn't show them")
    check(not ui.status:GetText():find("newword"), "the status never names a masked word")
    ui.input:SetText("***")
    ui.add:Click()
    check(not ui.status:GetText():find("%*%*%*") and ui.status:GetText():find("no letters"), "a bad word is refused without echoing it")

    -- rows sorted: another, newword, other, secretword
    ui.rows[1].remove:Click()
    check(env.ns.db.words.another == nil and ui.status:GetText() == "Removed 1 word.", "Remove removes a masked row without naming it")

    ui.tabs[2]:Click()
    check(not ui.tabs[2].enabled and ui.tabs[1].enabled, "the current tab button is pressed in")
    check(ui.target:IsShown() and not ui.reveal:IsShown() and not ui.scan:IsShown(), "players tab buttons")
    ui.input:SetText("Bad Guy")
    ui.add:Click()
    check(labels() == "Bad Guy" and env.ns.IsPlayerFiltered("bad guy"), "players are added and shown unmasked")
    ui.target:Click()
    check(ui.status:GetText() == "Target a player first.", "Add target with no target")
    env.units.target = { name = "Target Troll", guild = "Bad Guild" }
    ui.target:Click()
    check(labels() == "Bad Guy,Target Troll", "Add target adds the target")

    env.slash("player add Zed Zulu")
    check(labels() == "Bad Guy,Target Troll,Zed Zulu", "changes from slash commands show in the open window")

    for i = 1, 15 do env.ns.AddPlayer("Extra " .. string.char(64 + i)) end
    check(ui.page:GetText() == "1-10 of 18" and not ui.prev.enabled and ui.next.enabled, "long lists are paged")
    ui.next:Click()
    check(ui.page:GetText() == "9-18 of 18" and ui.rows[10].label:GetText() == "Zed Zulu", "next page stops at the end")
    ui.frame.scripts.OnMouseWheel(ui.frame, 1)
    check(ui.page:GetText() == "8-17 of 18", "mouse wheel scrolls")

    ui.tabs[3]:Click()
    check(ui.empty:IsShown() and ui.scan:IsShown(), "guilds tab starts empty and has Scan")
    ui.target:Click()
    check(labels() == "Bad Guild" and env.whoQuery == 'g-"Bad Guild"', "Add target adds the target's guild and looks it up at once")
    env.whoAnswer(2, "Bad Guild")
    env.whoQuery = nil
    ui.input:SetText("Typed Guild")
    ui.add:Click()
    check(env.whoQuery == 'g-"Typed Guild"', "a guild typed into the window is looked up at once")
    env.whoAnswer(2, "Typed Guild")
    ui.rows[2].remove:Click()   -- Typed Guild
    env.whoQuery = nil
    ui.scan:Click()
    check(env.whoQuery == 'g-"Bad Guild"', "Scan sends /who")
    ui.rows[1].remove:Click()
    check(env.ns.IsGuildFiltered("Bad Guild") == nil and ui.status:GetText() == "Removed Bad Guild.", "guild removed by its row")

    ui.checks.declineGuild:SetChecked(true)
    ui.checks.declineGuild:Click()
    check(env.ns.db.declineGuild == true, "Decline guild invites checkbox")
    ui.checks.enabled:SetChecked(false)
    ui.checks.enabled:Click()
    check(env.ns.db.enabled == false, "Hide chat checkbox turns hiding off")
    env.slash("on")
    check(ui.checks.enabled:GetChecked(), "and follows /rb on")

    ui.tabs[1]:Click()
    check(labels():find("^%*"), "going back to Words masks again")
    env.slash("")
    check(not ui.frame:IsShown(), "/rb again closes the window")
end

---------------------------------------------------------------------------
-- Scan reminder and About
---------------------------------------------------------------------------
do
    local env = boot()
    local tick = function(sec) env.ns.reminderFrame.scripts.OnUpdate(env.ns.reminderFrame, sec) end
    tick(11)
    check(not env.lastPrint():find("guild lists"), "no reminder with no guilds on the list")

    env.slash("guild add Big Guild")
    env.whoAnswer(3, "Big Guild")   -- adding looked it up; answer so that scan is finished
    env.ns.db.lastScan = nil
    check(env.ns.db.reminderMinutes == 720, "reminder defaults to 12 hours")
    tick(61)
    check(env.lastPrint() :find("haven't been scanned yet"), "reminds when never scanned")
    local n = #env.prints
    tick(61)
    check(#env.prints == n, "not repeated within the interval")

    env.slash("scan")
    env.whoAnswer(5, "Big Guild")
    check(env.ns.db.lastScan == env.clock, "a finished scan is timed")
    env.clock = env.clock + 3600
    tick(61)
    check(#env.prints == n + 2, "no reminder while the scan is newer than 12 hours")

    env.slash("reminder 30")
    check(env.ns.db.reminderMinutes == 30 and env.lastPrint():find("every 30 minutes"), "/rb reminder sets it")
    tick(61)
    check(env.lastPrint():find("Your guild lists are 1 hour old, run /rb scan%."), "reminds with the age")
    n = #env.prints
    env.clock = env.clock + 20 * 60
    tick(61)
    check(#env.prints == n, "at most once per interval")
    env.clock = env.clock + 11 * 60
    tick(61)
    check(env.lastPrint():find("1 hour old"), "and again after it")

    check(env.ns.SetReminder(5) == 30 and env.ns.SetReminder(5000) == 720, "reminder kept between 30 minutes and 12 hours")
    check(env.ns.SetReminder(80) == 90 and env.ns.SetReminder(74) == 60, "reminder rounded to 30 minute steps")
    check(env.ns.FormatInterval(90) == "1.5 hours" and env.ns.FormatInterval(60) == "1 hour", "interval wording")

    -- the window
    env.slash("")
    local ui = env.ns.ui
    env.ns.SetReminder(60)
    check(ui.reminder:GetText() == "Remind me to scan every 1 hour", "window shows the reminder")
    check(ui.lastScan:GetText() == "Last scan: 1 hour ago", "window shows the last scan")
    ui.less:Click()
    check(env.ns.db.reminderMinutes == 30 and not ui.less.enabled, "- goes down to 30 minutes and stops")
    for _ = 1, 30 do ui.more:Click() end
    check(env.ns.db.reminderMinutes == 720 and not ui.more.enabled and ui.less.enabled, "+ goes up to 12 hours and stops")
    check(ui.reminder:GetText() == "Remind me to scan every 12 hours", "12 hours wording")

    check(not ui.about:IsShown(), "About starts closed")
    ui.aboutButton:Click()
    check(ui.about:IsShown() and ui.aboutText:GetText():find("not a blanket block")
        and ui.aboutText:GetText():find("offline"), "About explains guild lists need regular scans")
    ui.aboutBack:Click()
    check(not ui.about:IsShown(), "Back closes About")
    ui.aboutButton:Click()
    ui.frame:Hide()
    env.slash("")
    check(not ui.about:IsShown(), "About is closed when the window reopens")
end

---------------------------------------------------------------------------
-- Two-part WoW Forever names
---------------------------------------------------------------------------
do
    local env = boot()
    local N = env.ns.NormalizeName
    for _, form in ipairs({ "Cat Facts", "Cat-Facts", "CatFacts", "cat facts", "  Cat  Facts ",
                            "Cat Facts-Some Server", "Cat Facts-Classic Beta PvP", "Cat-Facts-ClassicBetaPvP" }) do
        check(N(form) == "catfacts", "name form " .. form)
    end
    check(N("Cat") ~= N("Cat Facts"), "a first name alone is a different player")
    check(N("Bob-ClassicBetaPvP") == "bob", "a one-part name with this server's suffix")

    env.slash("player add Cat Facts")
    check(env.chat("CHAT_MSG_SAY", "hi", "Cat-Facts") == true, "hyphen-joined sender matches a spaced entry")
    check(env.chat("CHAT_MSG_SAY", "hi", "Cat") == false, "first name alone does not match")
    env.guidNames["Player-1-ABC"] = "Cat Facts"
    check(env.chat("CHAT_MSG_SAY", "hi", "Cat", "Player-1-ABC") == true, "the GUID's name catches a sender shown by first name")
    env.slash("player add Deew")
    env.guidNames["Player-1-DEEW"] = "Deew"
    check(env.chat("CHAT_MSG_SAY", "hi", "Deew Acidni", "Player-1-DEEW") == false, "a first-name-only GUID name is not matched against a fuller sender name")

    env.slash("guild add Streamer Army")
    env.ns.RememberGuild("Game Enjoyer", "Streamer Army")
    check(env.chat("CHAT_MSG_SAY", "hi", "Game-Enjoyer") == true, "guild members match whichever way their name is written")

    env.fire("PARTY_INVITE_REQUEST", "Cat", false, false, false, true, false, "Player-1-ABC")
    check(#env.alerts == 1 and env.alerts[1]:find("Cat is inviting you"), "invites are checked by the inviter's GUID too")

    env.slash("debug")
    local out = table.concat(env.prints, "\n")
    check(out:find('UnitName "Me Myself"') and out:find('sender "Cat", by GUID "Cat Facts"'), "/rb debug shows raw names")
end

---------------------------------------------------------------------------
-- Hidden lines list and preview
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("word add badword")
    env.filterRaw("CHAT_MSG_CHANNEL", "buy my badword", "Spam Mer", 500, "Trade")
    local e = env.ns.db.log[1]
    check(e and e.where == "Trade" and e.kind == "word" and e.reason == 'word "badword"', "log records channel and why")
    check(env.filterRaw("CHAT_MSG_SAY", "badword", "No Id", nil) == true, "lines without a line ID are still checked")

    for i = 1, 105 do env.filterRaw("CHAT_MSG_SAY", "badword " .. i, "Loud Mouth", 1000 + i) end
    check(#env.ns.db.log == 100 and env.ns.db.log[100].msg == "badword 105", "log keeps the newest 100")


    -- preview: shown, tagged, not removed; the rest of the arguments pass through
    env.slash("preview on")
    local hide, newMsg, author, _, _, _, _, _, _, channel = env.filterRaw("CHAT_MSG_CHANNEL", "more badword", "Spam Mer", 2000, "Trade")
    check(hide == false and newMsg == '|cff888888[RudeBoy: word "badword"]|r more badword' and author == "Spam Mer"
        and channel == "Trade", "preview shows the line with a tag")
    check(env.filterRaw("CHAT_MSG_CHANNEL", "clean", "Spam Mer", 2001, "Trade") == false, "preview leaves clean lines alone")
    local again = { env.filterRaw("CHAT_MSG_CHANNEL", "more badword", "Spam Mer", 2000, "Trade") }
    check(again[2] == newMsg and env.ns.db.log[100].msg == "more badword" and env.ns.db.log[99].msg ~= "more badword",
        "a second chat window gets the same tag, logged once")
    env.slash("preview off")
    check(env.filterRaw("CHAT_MSG_SAY", "badword", "X Y", 2002) == true, "preview off hides again")

    -- the Hidden tab
    env.slash("log clear")
    check(#env.ns.db.log == 0, "/rb log clear empties the list")
    env.slash("")
    local ui = env.ns.ui
    ui.tabs[5]:Click()
    check(ui.empty:IsShown() and ui.empty:GetText() == "Nothing hidden yet." and not ui.clear.enabled, "Hidden tab starts empty")
    check(not ui.input:IsShown() and not ui.add:IsShown() and ui.preview:IsShown(), "no input box on the Hidden tab")
    env.filterRaw("CHAT_MSG_CHANNEL", "you badword", "Spam Mer", 3000, "Trade")
    env.filterRaw("CHAT_MSG_SAY", "hello", "Bad Actor", 3001)
    env.slash("player add Bad Actor")
    env.filterRaw("CHAT_MSG_SAY", "hello again", "Bad Actor", 3002)
    check(ui.rows[1].label:GetText() == "12:00  [say]  Bad Actor  (player)", "newest first, masked shows who, where and why")
    check(ui.rows[2].label:GetText() == "12:00  [Trade]  Spam Mer  (word)", "a masked word line doesn't name the word")
    check(not ui.rows[1].remove:IsShown(), "no Remove buttons on the Hidden tab")
    check(ui.count:GetText() == "2 lines (hidden)", "count")
    ui.reveal:Click()
    check(ui.rows[2].label:GetText() == "12:00  Spam Mer: you badword", "Show reveals the text")
    ui.preview:Click()
    check(env.ns.db.preview and ui.preview:GetText() == "Preview: ON", "Preview button turns preview on")
    ui.preview:Click()
    ui.clear:Click()
    check(#env.ns.db.log == 0 and ui.empty:IsShown(), "Clear empties the list")
    ui.tabs[1]:Click()
    check(ui.input:IsShown() and ui.add:IsShown() and not ui.clear:IsShown() and not ui.preview:IsShown(), "other tabs get their input back")

    env.slash("debug")
    check(env.ns.db.recentAuthors and #env.ns.db.recentAuthors > 0, "recent senders are saved for reading outside the game")

    -- lifetime counter, split by kind, kept through Clear
    local before = env.ns.db.hiddenTotal
    env.filterRaw("CHAT_MSG_SAY", "badword", "Some Body", 3900)
    env.filterRaw("CHAT_MSG_SAY", "hi", "Bad Actor", 3901)
    check(env.ns.db.hiddenTotal == before + 2, "lifetime count goes up")
    local by = env.ns.db.hiddenByKind
    check(by.word + by.player + by.guild == env.ns.db.hiddenTotal and by.player >= 2, "split by word, player and guild")
    env.slash("")
    check(ui.hidden:GetText():find("lifetime") and ui.hidden:GetText():find("since 2026%-09%-22"), "window shows the lifetime count")
    check(ui.lifetime:GetText() == env.ns.Commas(env.ns.db.hiddenTotal) .. " lines filtered", "lifetime count under the title")
    check(env.ns.Commas(1234567) == "1,234,567" and env.ns.Commas(999) == "999" and env.ns.Commas(1000) == "1,000", "thousands separators")
    env.slash("")
    env.slash("status")
    check(table.concat(env.prints, "\n"):find("lifetime %(" .. by.word .. " by word"), "/rb status shows it")

    -- saved: a new session sees the list (boot last, it takes over the globals)
    env.filterRaw("CHAT_MSG_SAY", "badword", "Last One", 4000)
    local later = boot({ db = env.ns.db })
    check(later.ns.db.log[#later.ns.db.log].author == "Last One", "hidden lines are saved")
    check(later.ns.db.hiddenTotal == env.ns.db.hiddenTotal and later.ns.hiddenSession == 0, "lifetime count is saved, session count starts over")
end

---------------------------------------------------------------------------
-- Window text that must fit one line
---------------------------------------------------------------------------
do
    local env = boot()
    env.slash("")
    local ui = env.ns.ui
    for i, tab in ipairs(ui.tabs) do
        tab:Click()
        local hint = ui.hint:GetText() or ""
        check(#hint <= 66, ("tab %d hint fits one line (%d chars): %s"):format(i, #hint, hint))
    end
end

---------------------------------------------------------------------------
-- Release checks
---------------------------------------------------------------------------
do
    local toc = io.open(ADDON_DIR .. "RudeBoy.toc"):read("*a")
    local tocVersion = toc:match("## Version: *([^\r\n]+)")
    check(tocVersion == boot().ns.VERSION, ("the .toc version (%s) matches ns.VERSION in Core.lua"):format(tostring(tocVersion)))
    local changelog = io.open("CHANGELOG.md") and io.open("CHANGELOG.md"):read("*a") or ""
    check(changelog:find("## " .. tostring(tocVersion):gsub("%.", "%%."), 1) ~= nil, "CHANGELOG.md has a section for this version")
end

---------------------------------------------------------------------------
-- Full unit names, the Blocked tab and exemptions
---------------------------------------------------------------------------
do
    local env = boot()
    env.units.target = { name = "Little", second = "Under", guild = "Streamer Army" }
    env.fire("PLAYER_TARGET_CHANGED")
    check(env.ns.GuildOf("Little Under") == "Streamer Army", "first and last name from UnitName are joined")
    check(env.ns.db.known["littleunder"].n == "Little Under", "the shown name is kept with the guild")
    env.units.target = { name = "Bob Builder", second = "Classic Beta PvP", guild = "Other Guild" }
    env.fire("PLAYER_TARGET_CHANGED")
    check(env.ns.GuildOf("Bob Builder") == "Other Guild" and env.ns.db.known["bobbuilder"], "this server's name as the second value is not a last name")
    env.units.mouseover = { name = "Cat", guild = "Third Guild" }
    _G.UnitGUID = function(unit) return unit == "player" and "Player-1-SELF" or unit == "mouseover" and "Player-1-CAT" or nil end
    env.guidNames["Player-1-CAT"] = "Cat Facts"
    env.fire("UPDATE_MOUSEOVER_UNIT")
    check(env.ns.GuildOf("Cat Facts") == "Third Guild", "a fuller name from the GUID is preferred")

    env.slash("guild add Streamer Army")
    env.slash("player add Bad Actor")
    check(env.chat("CHAT_MSG_SAY", "hi", "Little Under") == true, "guild member hidden")
    env.slash("exempt add Little Under")
    check(env.chat("CHAT_MSG_SAY", "hi", "Little Under") == false, "exempt guild member is let through")
    env.slash("word add badword")
    check(env.chat("CHAT_MSG_SAY", "badword", "Little Under") == true, "words still apply to exempt people")
    env.slash("exempt add Bad Actor")
    check(env.chat("CHAT_MSG_SAY", "hi", "Bad Actor") == false, "exempt beats the player list")
    env.units.party1 = { name = "Little", second = "Under", guild = "Streamer Army" }
    env.fire("GROUP_ROSTER_UPDATE")
    check(#env.alerts == 0, "no group warning about an exempt person")
    env.slash("exempt remove Bad Actor")
    check(env.chat("CHAT_MSG_SAY", "hi", "Bad Actor") == true, "unexempt blocks again")
    env.slash("exempt list")
    check(env.lastPrint():find("Little Under"), "/rb exempt list")

    -- the Blocked tab
    env.slash("")
    local ui = env.ns.ui
    ui.tabs[4]:Click()
    check(not ui.input:IsShown() and not ui.target:IsShown() and not ui.reveal:IsShown(), "Blocked tab has no input or target button")
    local function rows()
        local out = {}
        for _, row in ipairs(ui.rows) do if row:IsShown() then out[#out + 1] = row.label:GetText() .. " [" .. row.remove:GetText() .. "]" end end
        return table.concat(out, "\n")
    end
    check(rows() == "Little Under  -  exempt, guild <Streamer Army> [Unexempt]\nBad Actor  -  on your player list [Remove]",
        "exempt first, then player list; guild members of unlisted guilds are not shown")
    env.ns.RememberGuild("Loud Fan", "Streamer Army")
    check(rows():find("Loud Fan  -  guild <Streamer Army> [Exempt]", 1, true), "guild members of listed guilds are shown with why")
    ui.rows[3].remove:Click()
    check(env.ns.IsExempt("Loud Fan") and rows():find("Loud Fan  -  exempt, guild <Streamer Army> [Unexempt]", 1, true), "Exempt on a row")
    ui.rows[1].remove:Click()
    check(not env.ns.IsExempt("Little Under") and rows():find("Little Under  -  guild <Streamer Army> [Exempt]", 1, true), "Unexempt on a row")
    ui.rows[2].remove:Click()   -- Loud Fan (exempt) is first, Bad Actor second
    check(not env.ns.IsPlayerFiltered("Bad Actor") and not rows():find("Bad Actor", 1, true), "Remove on a player-list row")

    -- login line about saved settings
    local fresh = boot()
    check(fresh.prints[1]:find("no saved settings found"), "login says when nothing was on disk")
    fresh.fire("PLAYER_LOGOUT")
    check(fresh.ns.db.savedAt == "12:00", "logout stamps the save time")
    -- saved settings handed over after login: adopted, with the session's additions kept
    local late = boot()
    late.slash("word add sessionword")
    late.filterRaw("CHAT_MSG_SAY", "sessionword", "Some One", 7000)
    local savedCopy = { words = { oldword = true }, players = { oldplayer = "Old Player" }, guilds = {}, known = {},
        hiddenTotal = 40, hiddenByKind = { word = 40, player = 0, guild = 0 }, log = {}, exempt = {},
        enabled = true, alerts = true, savedAt = "yesterday" }
    _G.RudeBoyDB = savedCopy
    late.fire("PLAYER_ENTERING_WORLD")
    check(late.ns.db == savedCopy and late.ns.loadedFromDisk, "late saved settings are adopted")
    check(late.ns.db.words.oldword and late.ns.db.words.sessionword and late.ns.db.players.oldplayer, "lists from both are kept")
    check(late.ns.db.hiddenTotal == 41 and late.ns.db.hiddenByKind.word == 41 and #late.ns.db.log == 1, "counts and log are merged")
    check(late.ns.MatchWord("oldword") == "oldword", "the adopted words are compiled")
    check(late.lastPrint():find("settings loaded") and late.prints[#late.prints - 1]:find("handed over the saved settings late"), "it says so")
    late.fire("PLAYER_ENTERING_WORLD")
    check(late.ns.db.hiddenTotal == 41, "adopting is a one-off")
    local watched = boot()
    _G.RudeBoyDB = { words = { fromdisk = true } }
    watched.now = watched.now + 12
    watched.update()
    check(watched.ns.db.words.fromdisk and watched.ns.dbSeenAt == "late (12s after login)", "a hand-over within a minute of login is caught by the watcher")

    local again = boot({ db = fresh.ns.db })
    check(again.prints[1]:find("settings restored") and again.prints[1]:find("last saved 12:00"), "login says settings were found and when saved")
    check(again.ns.restoredFromLink and again.prints[1]:find("restored from the linked save file"), "a table present before the addon's files run counts as restored by Saved.lua")
    check(fresh.prints[2]:find("LinkSavedSettings%.cmd"), "a fresh start points at the fix")
end

---------------------------------------------------------------------------
-- Guild keywords and the Olympus shortcut
---------------------------------------------------------------------------
do
    local env = boot()
    check(env.ns.IsGuildFiltered("Mount Olympus Raiders") == nil, "nothing blocked by default")
    env.slash("olympus on")
    check(env.ns.db.keywords.olympus == "Olympus" and env.whoQuery == 'g-"Olympus"', "/rb olympus on adds the keyword and looks the guilds up at once")
    env.whoAnswer(4, "Olympus Rising")
    check(env.ns.IsGuildFiltered("Mount Olympus Raiders") and env.ns.IsGuildFiltered("OLYMPUS") and env.ns.IsGuildFiltered("olympus ii"),
        "any guild with the word is blocked, any case")
    check(env.ns.IsGuildFiltered("Olympian Legends") == nil, "the whole word must appear")
    env.ns.RememberGuild("Some Fan", "Olympus Rising")
    check(env.chat("CHAT_MSG_SAY", "hi", "Some Fan") == true, "members of those guilds are hidden")
    env.slash("exempt add Some Fan")
    check(env.chat("CHAT_MSG_SAY", "hi", "Some Fan") == false, "exemptions still apply")
    env.slash("olympus off")
    check(env.ns.IsGuildFiltered("Mount Olympus Raiders") == nil, "/rb olympus off")

    env.slash("keyword add Crank")
    check(env.ns.db.keywords.crank == "Crank" and env.whoQuery == 'g-"Crank"', "/rb keyword add blocks and looks up")
    env.whoAnswer(2, "Crank Squad")
    check(env.ns.IsGuildFiltered("The Crank Squad") == 'guilds containing "Crank"', "keyword match names the keyword")
    env.slash("keyword list")
    check(env.lastPrint():find("Crank"), "/rb keyword list")
    env.slash("keyword remove crank")
    check(env.ns.IsGuildFiltered("The Crank Squad") == nil, "/rb keyword remove, any case")

    -- an older save with the olympus flag becomes a keyword
    local old = boot({ db = { olympus = true } })
    check(old.ns.db.keywords.olympus == "Olympus" and old.ns.db.olympus == nil, "old olympus setting migrated")

    env = boot()
    env.slash("guild add Other Guild")
    env.whoAnswer(1, "Other Guild")
    env.slash("")
    local ui = env.ns.ui
    ui.tabs[3]:Click()
    check(ui.keyword:IsShown() and ui.olympus:IsShown() and not ui.olympus:GetChecked(), "keyword button and Olympus box on the Guilds tab")
    ui.input:SetText("Crank")
    env.whoQuery = nil
    ui.keyword:Click()
    check(env.ns.db.keywords.crank == "Crank" and env.whoQuery == 'g-"Crank"' and ui.input:GetText() == "", "Add keyword blocks and scans")
    env.whoAnswer(1, "Crank Squad")
    local function labels()
        local out = {}
        for _, row in ipairs(ui.rows) do if row:IsShown() then out[#out + 1] = row.label:GetText() end end
        return table.concat(out, ",")
    end
    check(labels() == 'any guild containing "Crank",Other Guild', "keywords are listed with the guilds")
    ui.rows[1].remove:Click()
    check(env.ns.db.keywords.crank == nil and labels() == "Other Guild", "Remove on a keyword row")
    env.whoQuery = nil
    ui.olympus:SetChecked(true)
    ui.olympus:Click()
    check(env.ns.db.keywords.olympus == "Olympus" and env.whoQuery == 'g-"Olympus"', "ticking Olympus adds the keyword and scans")
    env.whoAnswer(1, "Olympus Rising")
    ui.tabs[1]:Click()
    check(not ui.olympus:IsShown() and not ui.keyword:IsShown(), "only on the Guilds tab")
    env.whoQuery = nil
    env.slash("scan")
    check(env.whoQuery == 'g-"Olympus"', "a full scan looks keywords up first")
    env.whoAnswer(1, "Olympus Rising")
    env.slash("scan")
    check(env.whoQuery == 'g-"Other Guild"', "then the listed guilds")
end

---------------------------------------------------------------------------
-- The Blocked tab uses the space where other tabs have their input box
---------------------------------------------------------------------------
do
    local env = boot()
    for i = 1, 15 do env.ns.AddPlayer("Player " .. string.char(64 + i)) end
    env.slash("")
    local ui = env.ns.ui
    ui.tabs[2]:Click()
    check(ui.page:GetText() == "1-10 of 15" and not ui.rows[11]:IsShown(), "Players tab shows 10 rows")
    ui.tabs[4]:Click()
    check(ui.page:GetText() == "1-12 of 15" and ui.rows[12]:IsShown(), "Blocked tab shows 12 rows")
    ui.next:Click()
    check(ui.page:GetText() == "4-15 of 15", "paging by 12 on the Blocked tab")
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
do
    local env = boot()
    local tt = _G.GameTooltip
    local function hover(unit)
        tt.lines = {}
        env.tooltipUnit = unit
        tt.scripts.OnTooltipSetUnit(tt)
        return tt.lines[1]
    end
    env.slash("guild add Streamer Army")
    env.slash("player add Bad Actor")
    env.units.mouseover = { name = "Nice", second = "Person" }
    check(hover("mouseover") == nil, "no line for an ordinary player")
    env.units.mouseover = { name = "Bad", second = "Actor" }
    local line = hover("mouseover")
    check(line and line.text == "Blocked by Rude Boy (player on your list)" and line.r == 1, "blocked player gets a red line")
    env.units.mouseover = { name = "Guild", second = "Minion", guild = "Streamer Army" }
    line = hover("mouseover")
    check(line and line.text == "Blocked by Rude Boy (guild <Streamer Army>)", "guild member gets the guild as the reason")
    check(env.ns.GuildOf("Guild Minion") == "Streamer Army", "hovering learns the guild")
    env.slash("exempt add Guild Minion")
    line = hover("mouseover")
    check(line and line.text:find("exempt") and line.g == 1, "exempt player gets a green line")
    env.units.mouseover = nil
    check(hover("mouseover") == nil and hover(nil) == nil, "nothing without a unit")
end

---------------------------------------------------------------------------
-- Chat bubbles
---------------------------------------------------------------------------
do
    local env = boot()
    -- two bubbles on screen, each a frame with a child holding a String
    local function bubble(text)
        local holder = mockFrame and nil
        local h = { String = { GetText = function() return text end }, alpha = 1 }
        h.SetAlpha = function(self, a) self.alpha = a end
        return { GetChildren = function() return h end, holder = h }
    end
    local b1, b2 = bubble("what a badword thing"), bubble("hello there")
    _G.C_ChatBubbles = { GetAllChatBubbles = function() return { b1, b2 } end }
    local w = env.ns.bubbleWatcher
    local function tick() w.scripts.OnUpdate(w, 0.1) end

    env.slash("word add badword")
    check(env.ns.db.bubbles == true, "bubble hiding is on by default")
    env.filterRaw("CHAT_MSG_SAY", "what a badword thing", "Loud Mouth", 9001)
    check(w:IsShown(), "a hidden say line starts the bubble watch")
    tick()
    check(b1.holder.alpha == 0 and b2.holder.alpha == 1, "the bubble with the hidden text is made invisible, the other left alone")
    env.now = env.now + 2
    tick()
    check(not w:IsShown(), "the watch stops after a moment")

    -- the bubble frame gets reused for an ordinary line
    b1.holder.String.GetText = function() return "a new line" end
    env.filterRaw("CHAT_MSG_SAY", "a new line", "Some One", 9002)
    tick()
    check(b1.holder.alpha == 1, "a reused bubble is shown again")

    env.now = env.now + 2
    tick()
    env.filterRaw("CHAT_MSG_CHANNEL", "badword in trade", "Loud Mouth", 9003, "Trade")
    check(not w:IsShown(), "channel lines have no bubbles and start no watch")

    env.slash("preview on")
    env.filterRaw("CHAT_MSG_SAY", "badword shown in preview", "Loud Mouth", 9004)
    b1.holder.String.GetText = function() return "badword shown in preview" end
    tick()
    check(b1.holder.alpha == 1, "in preview the bubble stays, like the line")
    env.slash("preview off")

    b1.holder.String.GetText = function() return "another badword" end
    env.filterRaw("CHAT_MSG_YELL", "another badword", "Loud Mouth", 9005)
    tick()
    check(b1.holder.alpha == 0, "yells too")
    env.slash("bubbles off")
    check(b1.holder.alpha == 1 and env.ns.db.bubbles == false, "/rb bubbles off shows hidden bubbles again")
    env.filterRaw("CHAT_MSG_SAY", "another badword", "Loud Mouth", 9006)
    tick()
    check(b1.holder.alpha == 1, "and hides none while off")

    env.slash("")
    local ui = env.ns.ui
    check(ui.checks.bubbles and not ui.checks.bubbles:GetChecked(), "checkbox follows the setting")
    ui.checks.bubbles:SetChecked(true)
    ui.checks.bubbles:Click()
    check(env.ns.db.bubbles == true, "checkbox turns it back on")
end

---------------------------------------------------------------------------
-- Quiet scans (the default)
---------------------------------------------------------------------------
do
    local env = boot({ quiet = true })
    local sys = env.filters.CHAT_MSG_SYSTEM
    local whoLine = "|Hplayer:Some Fan|h[Some Fan]|h: Level 60 Human Warrior <Big Guild> - Orgrimmar"
    check(env.ns.db.scanChat == false, "scans are quiet by default")
    check(sys({}, "CHAT_MSG_SYSTEM", whoLine) == false, "a /who you typed yourself is shown")

    local n = #env.prints
    env.slash("guild add Big Guild")
    check(#env.prints == n + 2 and env.lastPrint():find("looking up <Big Guild>%. Results stay out of chat"), "one line when a scan starts")
    check(sys({}, "CHAT_MSG_SYSTEM", whoLine) == true, "the game's result lines are hidden while a search is in flight")
    check(sys({}, "CHAT_MSG_SYSTEM", "3 players total") == true, "and the total line")
    check(sys({}, "CHAT_MSG_SYSTEM", "0 |4player:players; total") == true, "in the raw form the game sends too")
    check(sys({}, "CHAT_MSG_SYSTEM", "You must wait a moment before using /who again.") == true, "and the server's wait message")
    check(sys({}, "CHAT_MSG_SYSTEM", "Some One has come online.") == false, "other system messages are left alone")
    env.fire("CHAT_MSG_SYSTEM", whoLine)
    check(env.ns.GuildOf("Some Fan") == "Big Guild", "hidden lines are still read")

    n = #env.prints
    env.now = env.now + 7
    env.who = {}
    for i = 1, 50 do env.who[i] = { fullName = "Member " .. i, fullGuildName = "Big Guild" } end
    env.whoTotal = 83
    env.fire("WHO_LIST_UPDATE")
    check(#env.prints == n, "a full answer being split prints nothing")
    check(sys({}, "CHAT_MSG_SYSTEM", "50 players total") == true, "the last lines of an answer are still hidden just after it")
    local hw = _G.RudeBoyHardwareFrame
    for _ = 1, 6 do
        env.now = env.now + 7
        hw.scripts.OnKeyDown(hw, "W")
        env.who = {}
        for i = 1, 5 do env.who[i] = { fullName = "M" .. i .. env.whoQuery, fullGuildName = "Big Guild" } end
        env.whoTotal = 5
        env.fire("WHO_LIST_UPDATE")
    end
    check(#env.prints == n + 1 and env.lastPrint():find("Scan finished: 30 online members of blocked guilds found in 7 searches%."),
        "one summary line when the scan ends")
    env.now = env.now + 5
    check(sys({}, "CHAT_MSG_SYSTEM", whoLine) == false, "afterwards /who lines are shown again")

    env.slash("scanchat on")
    check(env.ns.db.scanChat == true, "/rb scanchat on")
    env.slash("scan")
    check(env.lastPrint():find("looking up <Big Guild>%.%.%."), "with it on, the step lines are back")
    check(sys({}, "CHAT_MSG_SYSTEM", whoLine) == false, "and the game's lines are not hidden")
end

---------------------------------------------------------------------------
-- The on-screen panel
---------------------------------------------------------------------------
do
    local env = boot()
    local panel = env.ns.panel
    check(panel and panel:IsShown(), "the panel is shown at login by default")
    check(panel.empty:IsShown() and panel.total:GetText():find("Lines blocked: |cffffd1000|r  %(0 this session%)"), "starts empty")
    check(panel.point[1] == "RIGHT" and panel.movable == true and panel.mouse == true and panel.lock:GetText() == "Lock", "default position, unlocked")

    env.slash("word add badword")
    env.slash("guild add Streamer Army")
    env.whoAnswer(1, "Streamer Army")
    env.slash("player add Bad Actor")
    env.ns.RememberGuild("Guild Minion", "Streamer Army")
    env.filterRaw("CHAT_MSG_SAY", "a badword", "Loud Mouth", 1)
    env.filterRaw("CHAT_MSG_SAY", "hi", "Guild Minion", 2)
    env.filterRaw("CHAT_MSG_SAY", "hi", "Bad Actor", 3)
    env.filterRaw("CHAT_MSG_SAY", "more badword", "Loud Mouth", 4)
    local function rows()
        local out = {}
        for _, r in ipairs(panel.rows) do if r:IsShown() then out[#out + 1] = (r:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end end
        return table.concat(out, " / ")
    end
    check(rows() == "Loud Mouth  x2  word / Bad Actor  x1  player list / Guild Minion  x1  Streamer Army",
        "names newest first, with counts and why; a word match never names the word")
    check(panel.total:GetText():find("|cffffd1004|r  %(4 this session%)") and not panel.empty:IsShown(), "counts follow")

    -- pending searches
    local function pending() return (panel.pending:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    check(pending() == "Searches pending: none", "no searches pending when idle")
    env.slash("guild add Huge Guild")
    check(pending() == "Searches pending: 1  (sent as you play)", "the search in flight counts")
    env.whoAnswer(90, "Huge Guild")
    check(pending() == "Searches pending: 6  (sent as you play)", "a full answer's split searches are counted")
    local hw = _G.RudeBoyHardwareFrame
    hw.scripts.OnKeyDown(hw, "W")
    check(pending() == "Searches pending: 6  (sent as you play)", "sending one moves it from queued to in flight")
    env.whoAnswer(3, "Huge Guild")
    check(pending() == "Searches pending: 5  (sent as you play)", "an answer takes one off")
    for _ = 1, 5 do
        hw.scripts.OnKeyDown(hw, "W")
        env.whoAnswer(3, "Huge Guild")
    end
    check(pending() == "Searches pending: none", "back to none when the scan is finished")

    -- moving and locking
    panel.point = { "TOPLEFT", _G.UIParent, "TOPLEFT", 40, -200 }
    panel.scripts.OnDragStop(panel)
    check(env.ns.db.panel.point == "TOPLEFT" and env.ns.db.panel.x == 40 and env.ns.db.panel.y == -200, "its position is saved after a drag")
    panel.lock:Click()
    check(env.ns.db.panel.locked and panel.movable == false and panel.mouse == false and panel.lock:GetText() == "Unlock",
        "Lock fixes it in place and lets clicks through")
    env.slash("panel unlock")
    check(not env.ns.db.panel.locked and panel.movable == true, "/rb panel unlock")
    panel.close:Click()
    check(not panel:IsShown() and env.ns.db.panel.shown == false, "its close button hides it")
    env.slash("panel")
    check(panel:IsShown() and panel.point[1] == "TOPLEFT" and panel.point[4] == 40, "/rb panel shows it again where it was")
    env.slash("panel reset")
    check(panel.point[1] == "RIGHT" and env.ns.db.panel.point == nil, "/rb panel reset")

    env.slash("")
    env.ns.ui.panelButton:Click()
    check(not panel:IsShown(), "the window's Panel button toggles it")

    -- hidden stays hidden, and the names survive a restart
    local saved = env.ns.db
    local again = boot({ db = saved })
    check(not again.ns.panel, "a hidden panel is not built at login")
    again.slash("panel show")
    local r1 = again.ns.panel.rows[1]:GetText()
    check(r1 and r1:find("Loud Mouth"), "the names come back from the saved list")
end

---------------------------------------------------------------------------
-- The game's Who window stays shut during the addon's searches
---------------------------------------------------------------------------
do
    local env = boot({ quiet = true })
    local ff = _G.FriendsFrame
    env.slash("guild add Big Guild")
    check(ff.events.WHO_LIST_UPDATE == nil and env.whoToUi == true, "while a search is in flight the Social window doesn't hear the answer")
    env.whoAnswer(83, "Big Guild")
    check(ff.events.WHO_LIST_UPDATE == true and env.whoToUi == false, "and hears /who answers again as soon as it has arrived")
    check(env.ns.ScanPending() == 6 and env.ns.GuildOf("Member 1" .. 'g-"Big Guild"') == "Big Guild", "the answer was still read")

    local hw = _G.RudeBoyHardwareFrame
    hw.scripts.OnKeyDown(hw, "W")
    check(ff.events.WHO_LIST_UPDATE == nil, "silenced again for the next search")
    env.fire("CHAT_MSG_SYSTEM", "You must wait a moment before using /who again.")
    check(ff.events.WHO_LIST_UPDATE == true, "handed back after a refusal")
    env.now = env.now + 11
    hw.scripts.OnKeyDown(hw, "W")
    env.now = env.now + 11
    hw.scripts.OnKeyDown(hw, "W")   -- no answer: times out and, the gap having passed, is sent again
    check(ff.events.WHO_LIST_UPDATE == nil, "silenced for the resend")
    env.whoAnswer(2, "Big Guild")
    check(ff.events.WHO_LIST_UPDATE == true, "handed back after the answer")

    -- a client that opens the Who list anyway: it is closed as soon as it shows
    hw.scripts.OnKeyDown(hw, "W")
    env.whoWindowOpen = true
    env.hooks.ShowUIPanel(_G.FriendsFrame)
    check(#env.closed == 1 and env.whoWindowOpen == false, "a Who list opened by the addon's search is closed at once")
    env.whoAnswer(2, "Big Guild")
    env.whoWindowOpen = true                  -- it shows a moment after the answer, without ShowUIPanel
    for _, f in ipairs(env.frames) do
        if f.scripts.OnUpdate and f ~= env.events and f ~= env.ns.reminderFrame and f ~= env.ns.bubbleWatcher then f.scripts.OnUpdate(f, 0.1) end
    end
    check(#env.closed == 2 and env.whoWindowOpen == false, "also when it shows just after the answer")
    -- a window of any name that shows up during a search is recorded
    local odd = {}
    odd.GetName = function() return "LookingForGroupThing" end
    odd.IsVisible = function() return env.oddShown or false end
    _G.UIParent.GetChildren = function() return odd end
    env.now = env.now + 11
    hw.scripts.OnKeyDown(hw, "W")
    env.oddShown = true
    env.whoAnswer(2, "Big Guild")
    check(env.ns.db.scanPopups["LookingForGroupThing (appeared)"] == 1, "a window that appears during a search is recorded by name")
    env.slash("debug")
    check(table.concat(env.prints, "\n"):find("windows seen during searches: .*LookingForGroupThing"), "and /rb debug lists it")
    _G.UIParent.GetChildren = function() end

    local popups = env.ns.db.scanPopups or {}
    local names = {}
    for k in pairs(popups) do names[#names + 1] = k end
    check(#names > 0, "windows that opened during a search are noted for diagnosis")

    -- with the Who window open by the player's own choice, nothing is touched
    env.whoWindowOpen = true
    hw.scripts.OnKeyDown(hw, "W")
    check(env.whoQuery and ff.events.WHO_LIST_UPDATE == true and env.whoToUi == false, "your own open Who window keeps working")
    check(#env.closed == 2, "and is not closed")
end

---------------------------------------------------------------------------
-- WoW Forever's Who list lives in the Looking For Group window
---------------------------------------------------------------------------
do
        local function frameLike(name)
            local f = { events = {}, scripts = {} }
            f.RegisterEvent = function(self, e) self.events[e] = true end
            _G[name] = f
            return f
        end
        local fe = boot({ quiet = true })
        _G.WhoFrame = nil
        local parent = frameLike("LFGParentFrame")
        parent.GetName = function() return "LFGParentFrame" end
        parent.IsVisible = function() return fe.lfgOpen or false end
        parent.events.WHO_LIST_UPDATE = true
        parent.IsEventRegistered = function(self, e) return self.events[e] == true end
        parent.UnregisterEvent = function(self, e) self.events[e] = nil end
        local list = frameLike("LFGWhoListFrame")
        list.IsVisible = function() return fe.lfgOpen and fe.whoTab or false end
        list.GetParent = function() return parent end
        parent.GetParent = function() return _G.UIParent end
        _G.UIParent.GetChildren = function() return parent end
        _G.HideUIPanel = function(frame) fe.closed[#fe.closed + 1] = frame fe.lfgOpen = false end

        fe.slash("guild add Big Guild")
        check(parent.events.WHO_LIST_UPDATE == nil, "the Looking For Group window doesn't hear the addon's search")
        fe.lfgOpen, fe.whoTab = true, true
        fe.hooks.ShowUIPanel(parent)
        check(fe.closed[1] == parent and not fe.lfgOpen, "if it opens anyway, the Looking For Group window is closed")
        fe.whoAnswer(3, "Big Guild")
        check(parent.events.WHO_LIST_UPDATE == true, "and it hears /who answers again afterwards")

        -- the player has it open on another tab: the addon leaves it alone
        fe.lfgOpen, fe.whoTab = true, false
        fe.slash("scan")
        fe.whoTab = true
        fe.hooks.ShowUIPanel(parent)
        check(#fe.closed == 1 and fe.lfgOpen, "a Looking For Group window you had open yourself is not closed")
        fe.whoAnswer(3, "Big Guild")
        _G.UIParent.GetChildren = function() end
        _G.LFGParentFrame, _G.LFGWhoListFrame = nil, nil
    end

---------------------------------------------------------------------------
-- Search interval, and the panel's Scan and Settings buttons
---------------------------------------------------------------------------
do
    local env = boot()
    check(env.ns.db.scanGap == 6, "searches are six seconds apart by default")
    env.slash("interval 3")
    check(env.ns.db.scanGap == 3 and env.lastPrint():find("every 3 seconds"), "/rb interval sets it")
    check(env.ns.SetScanGap(1) == 2 and env.ns.SetScanGap(99) == 30 and env.ns.SetScanGap(4.6) == 5, "kept between 2 and 30, whole seconds")
    env.ns.SetScanGap(3)

    env.slash("guild add Big Guild")
    env.whoAnswer(90, "Big Guild")
    local hw = _G.RudeBoyHardwareFrame
    env.now = env.now - 7   -- undo the answer's time jump, to measure from the send
    env.whoQuery = nil
    env.now = env.now + 2
    hw.scripts.OnKeyDown(hw, "W")
    check(env.whoQuery == nil, "not sooner than the interval")
    env.now = env.now + 1.5
    hw.scripts.OnKeyDown(hw, "W")
    check(env.whoQuery == 'g-"Big Guild" 1-10', "a search goes out once the interval has passed")

    env.fire("CHAT_MSG_SYSTEM", "You must wait a moment before using /who again.")
    check(env.ns.ScanState().gap == 7 and env.ns.db.scanGap == 3, "a refusal slows this scan down without changing your setting")
    for _ = 1, 8 do
        env.now = env.now + 31
        hw.scripts.OnKeyDown(hw, "W")
        env.whoAnswer(1, "Big Guild")
    end
    check(env.ns.ScanPending() == 0 and env.ns.ScanState().gap == 3, "the next scan starts from your setting again")

    -- the window
    env.slash("")
    local ui = env.ns.ui
    check(ui.gap:GetText() == "Send a queued search every 3 seconds", "the window shows the interval")
    ui.gapLess:Click()
    check(env.ns.db.scanGap == 2 and not ui.gapLess.enabled, "- goes down to 2 seconds and stops")
    ui.gapMore:Click()
    ui.gapMore:Click()
    check(env.ns.db.scanGap == 4 and ui.gap:GetText() == "Send a queued search every 4 seconds", "+ raises it")
    env.slash("")

    -- the panel
    local panel = env.ns.panel
    env.whoQuery = nil
    env.now = env.now + 31
    panel.scan:Click()
    check(env.whoQuery == 'g-"Big Guild"' and env.ns.ScanPending() == 1, "the panel's Scan button starts a scan")
    env.whoAnswer(1, "Big Guild")
    check(not ui.frame:IsShown(), "(settings window closed)")
    panel.settings:Click()
    check(ui.frame:IsShown(), "the panel's Settings button opens the window")
    panel.settings:Click()
    check(not ui.frame:IsShown(), "and closes it again")
    env.slash("panel lock")
    env.whoQuery = nil
    env.now = env.now + 31
    panel.scan:Click()
    check(env.whoQuery == 'g-"Big Guild"', "the buttons still work when the panel is locked")
end

---------------------------------------------------------------------------
-- The panel's Recent fly-out
---------------------------------------------------------------------------
do
    local env = boot()
    local panel = env.ns.panel
    check(env.ns.flyout == nil, "the fly-out is not built, let alone shown, until asked for")
    panel.recent:Click()
    local fly = env.ns.flyout
    check(fly and fly:IsShown() and fly.text:GetText() == "Nothing has been hidden yet.", "Recent opens it, empty at first")

    env.slash("word add badword")
    env.slash("player add Bad Actor")
    for i = 1, 12 do env.filterRaw("CHAT_MSG_CHANNEL", "line " .. i .. " badword", "Loud Mouth", 100 + i, "Trade") end
    env.filterRaw("CHAT_MSG_SAY", "psst", "Bad Actor", 200)
    local text = fly.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local paragraphs = {}
    for para in (text .. "\n\n"):gmatch("(.-)\n\n") do paragraphs[#paragraphs + 1] = para end
    check(#paragraphs == 10, "it shows the last ten lines")
    check(paragraphs[1] == "12:00  [say]  Bad Actor: psst  (player list)", "newest first, in full, with who and why")
    check(paragraphs[2] == "12:00  [Trade]  Loud Mouth: line 12 badword  (word)", "the message is shown unmasked; the reason never names the word list entry")
    check(paragraphs[10]:find("line 4 badword"), "and updates live as lines are hidden")

    fly.close:Click()
    check(not fly:IsShown(), "its x closes it")
    env.slash("panel recent")
    check(fly:IsShown(), "/rb panel recent opens it")
    panel.close:Click()
    check(not fly:IsShown() and not panel:IsShown(), "hiding the panel hides the fly-out too")

    -- placement: beside the panel on the side with room
    env.slash("panel show")
    panel.GetRight = function() return 1500 end
    _G.UIParent.GetRight = function() return 1600 end
    panel.recent:Click()
    check(fly.point[1] == "TOPRIGHT" and fly.point[3] == "TOPLEFT", "near the right edge it opens to the left")
    panel.GetRight = function() return 300 end
    panel.recent:Click()
    panel.recent:Click()
    check(fly.point[1] == "TOPLEFT" and fly.point[3] == "TOPRIGHT", "otherwise to the right")
    _G.UIParent.GetRight = nil

    local again = boot({ db = env.ns.db })
    check(again.ns.flyout == nil, "it starts closed again next session")
end

---------------------------------------------------------------------------
-- Invite statistics
---------------------------------------------------------------------------
do
    local env = boot()
    local panel = env.ns.panel
    local function invites() return (panel.invites:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    check(invites() == "Invites: 0 declined, 0 warned", "starts at nothing")
    env.slash("player add Bad Actor")
    env.slash("guild add Streamer Army")
    env.whoAnswer(1, "Streamer Army")

    env.fire("PARTY_INVITE_REQUEST", "Bad Actor")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(invites() == "Invites: 0 declined, 2 warned", "with declining off, party and guild invites count as warned")
    env.fire("PARTY_INVITE_REQUEST", "Nice Person")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Nice Guild")
    check(invites() == "Invites: 0 declined, 2 warned", "invites from anyone else aren't counted")

    _G.DeclineGuild = function() end
    env.slash("decline party on")
    env.slash("decline guild on")
    env.fire("PARTY_INVITE_REQUEST", "Bad Actor")
    env.fire("GUILD_INVITE_REQUEST", "Bad Actor", "Some Guild")
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(invites() == "Invites: 3 declined, 2 warned", "with declining on they count as declined")

    _G.DeclineGuild = nil
    _G.C_GuildInfo = nil
    env.fire("GUILD_INVITE_REQUEST", "Nice Person", "Streamer Army")
    check(invites() == "Invites: 3 declined, 3 warned", "an invite the client can't decline counts as warned")

    env.slash("status")
    check(table.concat(env.prints, "\n"):find("invites from blocked people: 3 declined, 3 warned about", 1, true), "/rb status shows them")
    local again = boot({ db = env.ns.db })
    check(again.ns.db.invites.declined == 3 and again.ns.db.invites.warned == 3, "the counts are saved")
end

realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
