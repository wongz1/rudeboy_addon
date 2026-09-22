--[[
    Runs the RudeBoy addon in a real Lua 5.1 interpreter against a mocked WoW API.
    WoW uses Lua 5.1, so use luajit or lua5.1 (on macOS: brew install luajit).

    usage (from the repo root): luajit tests/run.lua
]]

local ADDON_DIR = "RudeBoy/"

local FILES = {}
for line in io.lines(ADDON_DIR .. "RudeBoy.toc") do
    local file = line:match("^([^#%s].-%.lua)%s*$")
    if file then FILES[#FILES + 1] = (file:gsub("\\", "/")) end
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
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end
    function methods:IsEnabled() return self.enabled end
    function methods:Click() if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self) end end
    local function mockFrame(name)
        local f = setmetatable({ scripts = {}, events = {}, shown = true, enabled = true, checked = false, text = "" },
            { __index = function(_, k) return methods[k] or function() end end })
        if name then _G[name] = f end
        return f
    end
    function methods:CreateFontString() return mockFrame() end
    function methods:CreateTexture() return mockFrame() end
    _G.UISpecialFrames = {}
    _G.UIParent = mockFrame()
    _G.CreateFrame = function(_, name)
        local f = mockFrame(name)
        env.frames[#env.frames + 1] = f
        return f
    end
    _G.ChatFrame_AddMessageEventFilter = function(event, fn) env.filters[event] = fn end
    _G.GetTime = function() return env.now end
    _G.time = function() return env.clock end
    _G.date = function() return "12:00" end
    _G.print = function(s) env.prints[#env.prints + 1] = s end
    _G.UnitGUID = function(unit) return unit == "player" and "Player-1-SELF" or nil end
    _G.UnitExists = function(unit) return env.units[unit] ~= nil end
    _G.UnitIsPlayer = function(unit) return env.units[unit] ~= nil end
    _G.UnitName = function(unit) return env.units[unit] and env.units[unit].name end
    _G.GetGuildInfo = function(unit) return env.units[unit] and env.units[unit].guild end
    _G.RaidWarningFrame, _G.ChatTypeInfo = {}, { RAID_WARNING = {} }
    _G.RaidNotice_AddMessage = function(_, text) env.alerts[#env.alerts + 1] = text end
    _G.PlaySound = function() end
    _G.UnitFactionGroup = function() return opts.faction or "Horde" end
    _G.DeclineGroup = function() env.declined = env.declined + 1 end
    _G.StaticPopup_Hide = function() end
    _G.C_FriendList = {
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
        env.who = {}
        for i = 1, math.min(total, 50) do env.who[i] = { fullName = "Member " .. i .. (env.whoQuery or ""), fullGuildName = guild } end
        env.whoTotal = total
        env.fire("WHO_LIST_UPDATE")
    end
    function env.slash(input) _G.SlashCmdList["RUDEBOY"](input) end
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
    check(#env.ns.log == 1 and env.ns.log[1].author == "Some One", "hidden line logged")

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
    env.slash("scan")
    check(env.whoQuery == 'g-"Big Guild"', "scan with no name starts with the whole guild")
    env.whoAnswer(12, "Big Guild")
    check(env.lastPrint():find("12 found") and env.lastPrint():find("Scan finished"), "a small guild takes one search")
    check(env.ns.GuildOf("Member 1" .. 'g-"Big Guild"') == "Big Guild", "members learned")

    env.slash("scan")
    env.whoAnswer(83, "Big Guild")
    check(env.lastPrint():find("83 online") and env.lastPrint():find("8 searches"), "a full answer is split by class (8 for Horde)")
    local sent = {}
    for _ = 1, 20 do
        if env.lastPrint():find("Scan finished") then break end
        env.slash("scan")
        sent[#sent + 1] = env.whoQuery
        local fullClass = env.whoQuery == 'g-"Big Guild" c-"Warrior"'
        env.whoAnswer(fullClass and 60 or 10, "Big Guild")
        if fullClass then check(env.lastPrint():find("Split by level into 4"), "a full class is split by level") end
    end
    check(env.lastPrint():find("Scan finished"), "the queue runs out")
    check(#sent == 12, "8 class searches plus 4 level searches")
    check(sent[1] == 'g-"Big Guild" c-"Warrior"', "class search syntax")
    local joined = table.concat(sent, "|")
    check(not joined:find("Paladin") and joined:find("Shaman"), "Horde skips Paladin, keeps Shaman")
    check(sent[2] == 'g-"Big Guild" c-"Warrior" 1-29', "level searches come right after the full class")

    local ally = boot({ faction = "Alliance" })
    ally.slash("guild add Big Guild")
    ally.slash("scan")
    ally.whoAnswer(70, "Big Guild")
    local seen = {}
    for _ = 1, 8 do ally.slash("scan") seen[#seen + 1] = ally.whoQuery ally.whoAnswer(1, "Big Guild") end
    seen = table.concat(seen, "|")
    check(seen:find("Paladin") and not seen:find("Shaman"), "Alliance skips Shaman, keeps Paladin")

    -- several guilds, one search each run; waits for answers; resends a lost search
    local multi = boot()
    multi.slash("guild add Alpha")
    multi.slash("guild add Beta")
    multi.slash("guild add Gamma*")
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Alpha"', "first guild")
    multi.slash("scan")
    check(multi.lastPrint():find("still waiting"), "won't send over an unanswered search")
    multi.now = multi.now + 10
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Alpha"', "a search with no answer is sent again")
    multi.whoAnswer(3, "Alpha")
    multi.slash("scan")
    check(multi.whoQuery == 'g-"Beta"', "then the next guild, wildcards skipped")
    multi.fire("CHAT_MSG_SYSTEM", "2 players total")
    check(multi.lastPrint():find("2 found") and multi.lastPrint():find("Scan finished"), "answers printed to chat count too")

    -- naming a guild repeatedly carries on with its queued searches
    local named = boot()
    named.slash("guild add Big Guild")
    named.slash("scan big guild")
    named.whoAnswer(90, "Big Guild")
    named.slash("scan Big Guild")
    check(named.whoQuery:find('c%-"'), "/rb scan <guild> again continues the split")
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
    check(env.prints[1]:find("v0%.1%.0"), "/rb status prints the version")

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
    check(labels() == "Bad Guild", "Add target adds the target's guild")
    ui.scan:Click()
    check(env.whoQuery == 'g-"Bad Guild"', "Scan sends /who")
    ui.rows[1].remove:Click()
    check(env.ns.IsGuildFiltered("Bad Guild") == nil and ui.status:GetText() == "Removed Bad Guild.", "guild removed by its row")

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

realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
