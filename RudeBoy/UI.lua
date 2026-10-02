--[[
    UI.lua - the /rb window: view, add and remove filtered words, players and guilds.

    The Words tab shows every entry as ******** until you press Show, and goes back to
    masked whenever the window is reopened or you change tabs, so opening the window never
    puts the word list on screen by itself.

    The Hidden tab lists the last lines Rude Boy hid, newest first: time, channel, sender and
    why. Their text is masked the same way until Show is pressed; hover a shown line for all
    of it. Preview there leaves would-be-hidden lines in chat with a tag instead, for testing.

    The Blocked tab lists every person being blocked and the reason: on your player list, or
    a member of a listed guild (the part that is otherwise invisible). Exempt on a row lets that
    person through anyway; their exemption shows at the top of the tab with Unexempt.

    Panel (in the title strip, beside About) shows or hides the small on-screen panel, see Panel.lua.

    The bottom of the window sets how often to be reminded to scan, and About explains
    why guild lists need regular scans.

    Built the first time it is opened. Escape closes it.

    Look: the flat skin from Skin.lua. A 20px title strip with the name, the lifetime count,
    About, Panel and x; flat tabs (the current one pressed in with the accent border); a flat
    edit box; the list on a panel with every other row a shade lighter and a small x per row;
    flat check boxes; dim labels and hints, light text for names and values.
]]

local ADDON, ns = ...

local S = ns.Skin

local ROWS = 10           -- rows on most tabs; a tab may set its own `rows`
local MAX_ROWS = 12
local ROW_HEIGHT = 18
local MASK = "********"

-- layout
local WIDTH = 430
local PAD = S.PAD               -- 8: the margin inside the window
local TITLE_H = S.TITLE_H       -- 20: the title strip
local GAP = 4                   -- between rows of controls
local BTN_H = 18                -- buttons and the edit box inside the window
local TEXT_H = 12               -- one line of small text
local CHECK_H = 18              -- one row of check boxes
local INNER = WIDTH - 2 * PAD   -- the usable width
local ROW_WIDTH = INNER - 4     -- a list row, inside the list panel's 2px inset

local TABS = {
    { key = "words", label = "Words", noun = "word", add = "AddWord", remove = "RemoveWord", masked = true,
      hint = "Add words or phrases, comma separated (* is a wildcard):" },
    { key = "players", label = "Players", noun = "player", add = "AddPlayer", remove = "RemovePlayer",
      hint = "Add a player by name, or target them and press Add target:" },
    { key = "guilds", label = "Guilds", noun = "guild", add = "AddGuild", remove = "RemoveGuild",
      hint = "Add a guild by name, or target a member and press Add target:" },
    { key = "blocked", label = "Blocked", noun = "blocked player", rows = 12,   -- no input rows, so the list starts higher
      hint = "Everyone blocked, and why. Exempt lets a person through anyway." },
    { key = "log", label = "Hidden", noun = "line", masked = true,
      hint = "Recently hidden lines, newest first. Masked until you press Show." },
}

local ABOUT = table.concat({
    "|cffffd100What Rude Boy does|r",
    "Hides chat lines that contain your words, or that come from players and guilds on your lists, "
        .. "and warns you when one of them invites you or is in your group. Only you see any of this.",
    "",
    "|cffffd100Guild filtering is not a blanket block|r",
    "Chat doesn't say which guild someone is in. Rude Boy learns who is in a guild only when it "
        .. "sees them: your target, mouseover, nameplates, your group, and /who scans. Adding a guild "
        .. "does not find all of its members. Members who were offline at your last scan, or joined the "
        .. "guild since, get through until they are seen.",
    "",
    "|cffffd100Scan regularly|r",
    "Adding a guild or keyword looks it up at once; Scan on the Guilds tab (or /rb scan) looks up "
        .. "everything on your list. Big guilds take several /who searches (by level range), which go out from your own "
        .. "key presses and clicks as you play, until it says Scan finished. /who only finds "
        .. "players who are online, so scanning at different times of day catches more members. The scan "
        .. "reminder below tells you when your lists are getting old.",
    "",
    "Members are remembered for 30 days after they were last seen.",
}, "\n")

local ui = {}           -- the widgets, also reached by the tests as ns.ui
ns.ui = ui
local current = TABS[1]
local offset = 0        -- index of the first entry shown
local revealed = false  -- Words tab only

-- 12345 -> "12,345"
local function commas(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
ns.Commas = commas

local function plural(n, noun) return ("%d %s%s"):format(n, noun, n == 1 and "" or "s") end

-- Everyone blocked and why. Exempt people first, then the rest alphabetically.
local function blockedEntries()
    local list, seen = {}, {}
    local function add(key, text, source, action, order)
        seen[key] = true
        list[#list + 1] = { key = key, text = text, source = source, action = action, order = order }
    end
    for key, shown in pairs(ns.db.exempt) do
        local guild = ns.GuildOf(shown)
        local why = ns.db.players[key] and "on your player list"
            or (guild and ns.IsGuildFiltered(guild) and ("guild <%s>"):format(guild))
            or "not on any list"
        add(key, shown, "exempt, " .. why, "Unexempt", 0)
    end
    for key, shown in pairs(ns.db.players) do
        if not seen[key] then add(key, shown, "on your player list", "Remove", 1) end
    end
    for key, info in pairs(ns.db.known) do
        if not seen[key] and type(info) == "table" and info.g ~= "" and ns.IsGuildFiltered(info.g) then
            add(key, info.n or key, ("guild <%s>"):format(info.g), "Exempt", 1)
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.text:lower() < b.text:lower()
    end)
    return list
end

local function entries()
    local list = {}
    if current.key == "blocked" then return blockedEntries() end
    if current.key == "guilds" then
        for key, shown in pairs(ns.db.keywords) do
            list[#list + 1] = { key = "kw:" .. key, text = ('any guild containing "%s"'):format(shown), keyword = shown }
        end
    end
    if current.key == "log" then
        local log = ns.db.log
        for i = #log, 1, -1 do list[#list + 1] = { log = log[i] } end
        return list
    end
    for key, shown in pairs(ns.db[current.key]) do
        list[#list + 1] = { key = key, text = (shown == true) and key or shown }
    end
    table.sort(list, function(a, b) return a.text:lower() < b.text:lower() end)
    return list
end

-- A Hidden tab row: masked shows only who, where and what kind of rule; shown adds the text.
local function logLabel(e, masked)
    if masked then
        return ("%s  [%s]  %s  (%s)"):format(e.at or "", tostring(e.where), tostring(e.author), tostring(e.kind))
    end
    return ("%s  %s: %s"):format(e.at or "", tostring(e.author), tostring(e.msg))
end

local function setStatus(text, isError)
    ui.status:SetText(text or "")
    if isError then ui.status:SetTextColor(1, 0.3, 0.3) else ui.status:SetTextColor(0.6, 1, 0.6) end
end

function ns.RefreshUI()
    if not (ui.frame and ui.frame:IsShown()) then return end
    local list = entries()
    local rows = current.rows or ROWS
    offset = math.max(0, math.min(offset, #list - rows))
    local masked = current.masked and not revealed
    local isLog = current.key == "log"

    -- the current tab is pressed in: disabled, with the accent border and the lighter face
    for i, tab in ipairs(ui.tabs) do
        if TABS[i] == current then tab:Disable() S.select(tab, true) else tab:Enable() S.select(tab, false) end
    end
    ui.hint:SetText(current.hint)

    -- the list's bottom is fixed; a tab with more rows starts it higher, with the status
    -- line just above it (the rows are anchored inside the list, so they move with it)
    local top = ui.listBottom + rows * ROW_HEIGHT + 4
    ui.list:ClearAllPoints()
    ui.list:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", PAD, top)
    ui.list:SetPoint("BOTTOMRIGHT", ui.frame, "TOPRIGHT", -PAD, ui.listBottom)
    ui.status:ClearAllPoints()
    ui.status:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", PAD, top + GAP + TEXT_H)
    for i, row in ipairs(ui.rows) do
        local e = (i <= rows) and list[offset + i] or nil
        row.entry = e
        if e then
            if isLog then
                row.label:SetText(logLabel(e.log, masked))
                row.label:SetWidth(ROW_WIDTH - 8)
                row.remove:Hide()
            elseif e.action then
                -- Exempt / Unexempt / Remove: a worded button
                row.label:SetText(("%s  -  %s"):format(e.text, e.source))
                row.label:SetWidth(ROW_WIDTH - 60 - 12)
                row.remove:SetText(e.action)
                row.remove:SetWidth(60)
                row.remove:Show()
            else
                row.label:SetText(masked and MASK or e.text)
                row.label:SetWidth(ROW_WIDTH - 16 - 12)
                row.remove:SetText("x")
                row.remove:SetWidth(16)
                row.remove:Show()
            end
            row:Show()
        else
            row:Hide()
        end
    end

    ui.count:SetText(plural(#list, current.noun) .. (masked and #list > 0 and " (hidden)" or ""))
    if #list > rows then
        ui.page:SetText(("%d-%d of %d"):format(offset + 1, math.min(offset + rows, #list), #list))
    else
        ui.page:SetText("")
    end
    if offset > 0 then ui.prev:Enable() else ui.prev:Disable() end
    if offset + rows < #list then ui.next:Enable() else ui.next:Disable() end
    ui.empty:SetText(isLog and "Nothing hidden yet." or current.key == "blocked" and "Nobody is blocked yet." or "Nothing here yet.")
    if #list == 0 then ui.empty:Show() else ui.empty:Hide() end
    if isLog then
        ui.input:Hide()
        ui.add:Hide()
        ui.clear:Show()
        ui.preview:Show()
        ui.preview:SetText(ns.db.preview and "Preview: ON" or "Preview: OFF")
        if #list > 0 then ui.clear:Enable() else ui.clear:Disable() end
    elseif current.key == "blocked" then
        ui.input:Hide()
        ui.add:Hide()
        ui.clear:Hide()
        ui.preview:Hide()
        ui.target:Hide()
    else
        ui.input:Show()
        ui.add:Show()
        ui.clear:Hide()
        ui.preview:Hide()
    end

    if current.masked and #list > 0 then
        ui.reveal:SetText(revealed and "Hide" or "Show")
        ui.reveal:Show()
    else
        ui.reveal:Hide()
    end
    if current.masked or current.key == "blocked" then ui.target:Hide() else ui.target:Show() end
    if current.key == "guilds" then
        ui.scan:Show() ui.keyword:Show() ui.olympus:Show()
    else
        ui.scan:Hide() ui.keyword:Hide() ui.olympus:Hide()
    end
    ui.olympus:SetChecked(ns.db.keywords[ns.NormalizeGuild(ns.OLYMPUS)] ~= nil)

    ui.checks.enabled:SetChecked(ns.db.enabled)
    ui.checks.alerts:SetChecked(ns.db.alerts)
    ui.checks.autoDecline:SetChecked(ns.db.autoDecline)
    ui.checks.declineGuild:SetChecked(ns.db.declineGuild)
    ui.checks.bubbles:SetChecked(ns.db.bubbles)
    local by = ns.db.hiddenByKind
    ui.lifetime:SetText(("%s line%s filtered"):format(commas(ns.db.hiddenTotal), ns.db.hiddenTotal == 1 and "" or "s"))
    ui.hidden:SetText(("Lines hidden: |cffffd100%s lifetime|r since %s, %s this session\n%s by word, %s by player, %s by guild"):format(
        commas(ns.db.hiddenTotal), ns.db.countingSince, commas(ns.hiddenSession), commas(by.word), commas(by.player), commas(by.guild)))

    local minutes = ns.db.reminderMinutes
    ui.reminder:SetText("Remind me to scan every " .. ns.FormatInterval(minutes))
    if minutes > ns.REMINDER_MIN then ui.less:Enable() else ui.less:Disable() end
    if minutes < ns.REMINDER_MAX then ui.more:Enable() else ui.more:Disable() end
    local gap = ns.db.scanGap
    ui.gap:SetText(("Send a queued search every %d second%s"):format(gap, gap == 1 and "" or "s"))
    if gap > ns.SCAN_GAP_MIN then ui.gapLess:Enable() else ui.gapLess:Disable() end
    if gap < ns.SCAN_GAP_MAX then ui.gapMore:Enable() else ui.gapMore:Disable() end
    ui.lastScan:SetText(ns.db.lastScan and ("Last scan: %s ago"):format(ns.FormatAge(time() - ns.db.lastScan))
        or "Last scan: never")
end

local function selectTab(tab)
    current = tab
    offset = 0
    revealed = false
    setStatus("")
    ui.input:SetText("")
    ns.RefreshUI()
end

local function scroll(delta)
    offset = offset + delta
    ns.RefreshUI()
end

local function addFromInput()
    local text = ui.input:GetText() or ""
    local pieces = {}
    if current.key == "words" then
        for piece in (text .. ","):gmatch("([^,]*),") do
            if ns.Trim(piece) ~= "" then pieces[#pieces + 1] = piece end
        end
    elseif ns.Trim(text) ~= "" then
        pieces[1] = text
    end
    if #pieces == 0 then setStatus(("Type a %s first."):format(current.noun), true) return end

    local added, lastErr = {}, nil
    for _, piece in ipairs(pieces) do
        local entry, err = ns[current.add](piece)
        if entry then added[#added + 1] = entry else lastErr = err end
    end
    ui.input:SetText("")
    if #added == 0 then
        -- the error for a bad word quotes it, so it is kept off screen while words are masked
        setStatus(current.masked and "That has no letters to match." or lastErr, true)
    elseif current.masked then
        setStatus(("Added %s."):format(plural(#added, current.noun)))
    else
        setStatus(("Added %s."):format(table.concat(added, ", ")))
        -- adding a guild came from a click or Enter, so its first /who may go out right now
        if current.key == "guilds" and not added[1]:find("*", 1, true) then ns.Scan(added[1]) end
    end
end

local function addTarget()
    local name, guild = ns.TargetInfo()
    if not name then setStatus("Target a player first.", true) return end
    if current.key == "players" then
        ns.AddPlayer(name)
        setStatus(("Added %s."):format(name))
    elseif not guild then
        setStatus(("%s is not in a guild, or it hasn't loaded yet."):format(name), true)
    else
        ns.AddGuild(guild)
        setStatus(("Added <%s>. Looking up its online members with /who..."):format(guild))
        ns.Scan(guild)
    end
end

local function removeRow(row)
    local e = row.entry
    if not e then return end
    if e.keyword then
        ns.RemoveKeyword(e.keyword)
        setStatus(('No longer blocking guilds containing "%s".'):format(e.keyword))
        return
    end
    if e.action == "Exempt" then
        ns.Exempt(e.text)
        setStatus(("%s is exempt: let through even though their guild is on your list."):format(e.text))
        return
    elseif e.action == "Unexempt" then
        ns.Unexempt(e.key)
        setStatus(("%s is no longer exempt."):format(e.text))
        return
    elseif e.action == "Remove" then
        ns.RemovePlayer(e.key)
        setStatus(("Removed %s from your player list."):format(e.text))
        return
    end
    local removed = ns[current.remove](e.key)
    if removed then
        setStatus(current.masked and not revealed and ("Removed 1 %s."):format(current.noun) or ("Removed %s."):format(removed))
    end
end

-- Hovering a Blocked tab row shows the whole name and reason; a shown Hidden tab line gives
-- the whole message.
local function rowEnter(row)
    if not GameTooltip then return end
    local b = row.entry and row.entry.action and row.entry
    if b then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(b.text, 1, 0.82, 0)
        GameTooltip:AddLine(b.source, 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local e = row.entry and row.entry.log
    if not (e and revealed) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(("%s  [%s]  %s"):format(e.at or "", tostring(e.where), tostring(e.author)), 1, 0.82, 0)
    GameTooltip:AddLine(tostring(e.msg), 1, 1, 1, true)
    GameTooltip:AddLine(tostring(e.reason), 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function rowLeave()
    if GameTooltip then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Building the window: laid out top to bottom with a running y, so the height follows
-- from what is in it and nothing is drawn outside the backdrop.
---------------------------------------------------------------------------

local function build()
    local f = CreateFrame("Frame", "RudeBoyFrame", UIParent, S.template())
    ui.frame = f
    f:SetSize(WIDTH, 100)   -- the height is set from the layout at the end
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    S.skin(f, S.COLOR.window)
    if UISpecialFrames then table.insert(UISpecialFrames, "RudeBoyFrame") end

    -- title strip: the name, the lifetime count beside it, About, Panel and x on the right
    local strip = S.titleStrip(f, "Rude Boy", function() f:Hide() end)
    ui.titleBar = strip
    ui.close = strip.close
    ui.lifetime = S.dim(strip, "")
    ui.lifetime:SetPoint("LEFT", strip.title, "RIGHT", 8, 0)
    ui.panelButton = S.button(strip, "Panel", 44, function() ns.SetPanelShown(not ns.db.panel.shown) end)
    ui.panelButton:SetHeight(TITLE_H - 4)
    ui.panelButton:SetPoint("RIGHT", strip.close, "LEFT", -2, 0)
    ui.aboutButton = S.button(strip, "About", 44, function()
        if ui.about:IsShown() then ui.about:Hide() else ui.about:Show() end
    end)
    ui.aboutButton:SetHeight(TITLE_H - 4)
    ui.aboutButton:SetPoint("RIGHT", ui.panelButton, "LEFT", -2, 0)

    local y = -(TITLE_H + PAD)

    -- tabs in a row; the current one is pressed in (see RefreshUI)
    ui.tabs = {}
    local tabWidth = math.floor((INNER - 2 * (#TABS - 1)) / #TABS)
    for i, tab in ipairs(TABS) do
        local b = S.button(f, tab.label, tabWidth, function() selectTab(tab) end)
        b:SetDisabledFontObject("GameFontHighlightSmall")   -- the current tab is disabled, not greyed out
        if i == 1 then
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        else
            b:SetPoint("LEFT", ui.tabs[i - 1], "RIGHT", 2, 0)
        end
        ui.tabs[i] = b
    end
    y = y - 20 - GAP

    ui.hint = S.dim(f, "")
    ui.hint:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.hint:SetWidth(INNER)
    ui.hint:SetJustifyH("LEFT")
    if ui.hint.SetWordWrap then ui.hint:SetWordWrap(false) end   -- one line; the input box sits right under it
    y = y - TEXT_H - GAP

    -- the input box and Add
    ui.add = S.button(f, "Add", 60, addFromInput)
    ui.add:SetHeight(BTN_H)
    ui.add:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    ui.input = S.editbox(f, "RudeBoyInput", INNER - 60 - 2, addFromInput)
    ui.input:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    y = y - BTN_H - GAP

    -- the action row: which buttons show depends on the tab
    local function action(str, width, onClick)
        local b = S.button(f, str, width, onClick)
        b:SetHeight(BTN_H)
        return b
    end
    ui.target = action("Add target", 80, addTarget)
    ui.target:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.scan = action("Scan", 60, function() ns.Scan("") end)
    ui.scan:SetPoint("LEFT", ui.target, "RIGHT", 2, 0)
    ui.keyword = action("Add keyword", 90, function()
        local word, err = ns.AddKeyword(ui.input:GetText() or "")
        if not word then setStatus("Type a word first: every guild containing it is blocked.", true) return end
        ui.input:SetText("")
        setStatus(('Blocking every guild containing "%s". Looking them up with /who...'):format(word))
        ns.Scan(word)
    end)
    ui.keyword:SetPoint("LEFT", ui.scan, "RIGHT", 2, 0)
    ui.olympus = S.checkbox(f, "Olympus", function(_, on)
        if on then
            ns.AddKeyword(ns.OLYMPUS)
            setStatus("Blocking every guild with Olympus in its name. Looking them up with /who...")
            ns.Scan(ns.OLYMPUS)
        else
            ns.RemoveKeyword(ns.OLYMPUS)
            setStatus("Olympus guilds are no longer blocked as a group.")
        end
        ns.RefreshUI()
    end)
    ui.olympus:SetPoint("LEFT", ui.keyword, "RIGHT", 8, 0)
    ui.reveal = action("Show", 60, function()
        revealed = not revealed
        ns.RefreshUI()
    end)
    ui.reveal:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.clear = action("Clear", 60, function()
        local log = ns.db.log
        for i = #log, 1, -1 do log[i] = nil end
        setStatus("Cleared the hidden lines list.")
        ns.RefreshUI()
    end)
    ui.clear:SetPoint("LEFT", ui.reveal, "RIGHT", 2, 0)
    ui.preview = action("Preview: OFF", 90, function()
        ns.db.preview = not ns.db.preview
        setStatus(ns.db.preview and "Preview on: lines stay in chat, tagged with why they'd be hidden."
            or "Preview off: matching lines are hidden again.")
        ns.RefreshUI()
    end)
    ui.preview:SetPoint("LEFT", ui.clear, "RIGHT", 2, 0)
    y = y - BTN_H - GAP

    -- the status line sits just above the list; RefreshUI anchors it per tab
    ui.status = S.dim(f, "")
    ui.status:SetWidth(INNER)
    ui.status:SetJustifyH("LEFT")
    y = y - TEXT_H - GAP

    -- the list: a panel of rows. Its bottom is fixed; a tab with more rows (Blocked, which
    -- has no input rows) starts it higher, see RefreshUI.
    ui.listTop = y
    ui.listBottom = y - ROWS * ROW_HEIGHT - 4
    ui.list = S.panel(f)
    ui.list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, ui.listTop)
    ui.list:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -PAD, ui.listBottom)
    ui.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, ui.list)
        row:SetSize(ROW_WIDTH, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", ui.list, "TOPLEFT", 2, -2 - (i - 1) * ROW_HEIGHT)
        if i % 2 == 0 then   -- every other row a shade lighter
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetTexture(S.WHITE)
            stripe:SetVertexColor(S.COLOR.stripe[1], S.COLOR.stripe[2], S.COLOR.stripe[3], S.COLOR.stripe[4])
            stripe:SetAllPoints(row)
        end
        row.label = S.text(row, "")
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetWidth(ROW_WIDTH - 8)
        row.label:SetJustifyH("LEFT")
        row.label:SetHeight(ROW_HEIGHT)
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        row:EnableMouse(true)
        row:SetScript("OnEnter", rowEnter)
        row:SetScript("OnLeave", rowLeave)
        row.remove = S.button(row, "x", 16, function() removeRow(row) end)
        row.remove:SetHeight(ROW_HEIGHT - 2)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -1, 0)
        ui.rows[i] = row
    end
    ui.empty = S.dim(ui.list, "Nothing here yet.")
    ui.empty:SetPoint("CENTER", ui.list, "CENTER", 0, 0)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) scroll(-delta) end)

    -- under the list: the count, the page and < >
    y = ui.listBottom - GAP
    ui.next = S.button(f, ">", 18, function() scroll(current.rows or ROWS) end)
    ui.next:SetHeight(BTN_H)
    ui.next:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
    ui.prev = S.button(f, "<", 18, function() scroll(-(current.rows or ROWS)) end)
    ui.prev:SetHeight(BTN_H)
    ui.prev:SetPoint("RIGHT", ui.next, "LEFT", -2, 0)
    ui.page = S.dim(f, "")
    ui.page:SetPoint("RIGHT", ui.prev, "LEFT", -8, 0)
    ui.count = S.dim(f, "")
    ui.count:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 3)
    y = y - BTN_H - PAD

    -- settings: five check boxes in two columns, then a note
    local column = math.floor(INNER / 2)
    local function checkbox(label, key, col, line)
        local cb = S.checkbox(f, label, function(_, on) ns.db[key] = on end)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * column, y - line * CHECK_H)
        return cb
    end
    ui.checks = {
        enabled = checkbox("Hide chat lines", "enabled", 0, 0),
        alerts = checkbox("Warn about blocked people", "alerts", 1, 0),
        autoDecline = checkbox("Decline party invites", "autoDecline", 0, 1),
        declineGuild = checkbox("Decline guild invites", "declineGuild", 1, 1),
        bubbles = checkbox("Hide their chat bubbles", "bubbles", 0, 2),
    }
    ui.checks.bubbles:HookScript("OnClick", function(self)
        if not self:GetChecked() and ns.ShowAllBubbles then ns.ShowAllBubbles() end
    end)
    y = y - 2 * CHECK_H - 14 - GAP

    ui.note = S.dim(f, "Warnings cover groups and invites; invites are only declined from blocked people or guilds. "
        .. "Bubbles can't be hidden in dungeons and raids.")
    ui.note:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.note:SetWidth(INNER)
    ui.note:SetJustifyH("LEFT")
    if ui.note.SetWordWrap then ui.note:SetWordWrap(true) end
    y = y - 2 * TEXT_H - GAP

    -- the scan reminder and the last scan
    ui.less = S.button(f, "-", 18, function() ns.SetReminder(ns.db.reminderMinutes - ns.REMINDER_STEP) end)
    ui.less:SetHeight(BTN_H)
    ui.less:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.more = S.button(f, "+", 18, function() ns.SetReminder(ns.db.reminderMinutes + ns.REMINDER_STEP) end)
    ui.more:SetHeight(BTN_H)
    ui.more:SetPoint("LEFT", ui.less, "RIGHT", 2, 0)
    ui.reminder = S.text(f, "")
    ui.reminder:SetPoint("LEFT", ui.more, "RIGHT", 6, 0)
    ui.lastScan = S.dim(f, "")
    ui.lastScan:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y - 3)
    y = y - BTN_H - GAP

    -- the gap between queued searches
    ui.gapLess = S.button(f, "-", 18, function() ns.SetScanGap(ns.db.scanGap - 1) end)
    ui.gapLess:SetHeight(BTN_H)
    ui.gapLess:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.gapMore = S.button(f, "+", 18, function() ns.SetScanGap(ns.db.scanGap + 1) end)
    ui.gapMore:SetHeight(BTN_H)
    ui.gapMore:SetPoint("LEFT", ui.gapLess, "RIGHT", 2, 0)
    ui.gap = S.text(f, "")
    ui.gap:SetPoint("LEFT", ui.gapMore, "RIGHT", 6, 0)
    y = y - BTN_H - PAD

    -- the two-line lifetime summary
    ui.hidden = S.dim(f, "")
    ui.hidden:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    ui.hidden:SetWidth(INNER)
    ui.hidden:SetJustifyH("LEFT")
    y = y - 2 * TEXT_H - PAD

    f:SetHeight(-y)

    -- About: a flat panel laid over everything under the title strip until closed. Opaque,
    -- so the lists don't show through it.
    local about = S.panel(f)
    ui.about = about
    about:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TITLE_H + PAD))
    about:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    S.setBg(about, { S.COLOR.panel[1], S.COLOR.panel[2], S.COLOR.panel[3], 1 })
    about:SetFrameStrata("FULLSCREEN_DIALOG")
    about:SetFrameLevel((f:GetFrameLevel() or 0) + 50)
    about:EnableMouse(true)
    ui.aboutText = S.text(about, ABOUT)
    ui.aboutText:SetPoint("TOPLEFT", about, "TOPLEFT", PAD, -PAD)
    ui.aboutText:SetWidth(INNER - 2 * PAD)
    ui.aboutText:SetJustifyH("LEFT")
    ui.aboutText:SetJustifyV("TOP")
    ui.aboutBack = S.button(about, "Back", 60, function() about:Hide() end)
    ui.aboutBack:SetHeight(BTN_H)
    ui.aboutBack:SetPoint("BOTTOM", about, "BOTTOM", 0, PAD)
    about:Hide()

    f:SetScript("OnShow", function()
        revealed = false
        offset = 0
        setStatus("")
        ns.RefreshUI()
    end)
    f:SetScript("OnHide", function()
        revealed = false
        ui.about:Hide()
        ui.input:ClearFocus()
    end)
    f:Hide()
end

function ns.ToggleUI()
    if not ui.frame then build() end
    if ui.frame:IsShown() then ui.frame:Hide() else ui.frame:Show() end
end
