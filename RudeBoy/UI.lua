--[[
    UI.lua - the /rb window: view, add and remove filtered words, players and guilds.

    The Words tab shows every entry as ******** until you press Show, and goes back to
    masked whenever the window is reopened or you change tabs, so opening the window never
    puts the word list on screen by itself.

    The Hidden tab lists the last lines Rude Boy hid, newest first: time, channel, sender and
    why. Their text is masked the same way until Show is pressed; hover a shown line for all
    of it. Preview there leaves would-be-hidden lines in chat with a tag instead, for testing.

    The bottom of the window sets how often to be reminded to scan, and About explains
    why guild lists need regular scans.

    Built the first time it is opened. Escape closes it.
]]

local ADDON, ns = ...

local ROWS = 10
local ROW_HEIGHT = 22
local MASK = "********"

local TABS = {
    { key = "words", label = "Words", noun = "word", add = "AddWord", remove = "RemoveWord", masked = true,
      hint = "Add a word or phrase (separate several with commas, * is a wildcard):" },
    { key = "players", label = "Players", noun = "player", add = "AddPlayer", remove = "RemovePlayer",
      hint = "Add a player by name, or target them and press Add target:" },
    { key = "guilds", label = "Guilds", noun = "guild", add = "AddGuild", remove = "RemoveGuild",
      hint = "Add a guild by name, or target a member and press Add target:" },
    { key = "log", label = "Hidden", noun = "line", masked = true,
      hint = "The last lines Rude Boy hid, newest first. Messages stay masked until you press Show." },
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
    "Press Scan on the Guilds tab (or type /rb scan). Each press sends one /who search. Big guilds "
        .. "are split by class and level, so keep pressing until it says Scan finished. /who only finds "
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

local function plural(n, noun) return ("%d %s%s"):format(n, noun, n == 1 and "" or "s") end

local function entries()
    local list = {}
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
    offset = math.max(0, math.min(offset, #list - ROWS))
    local masked = current.masked and not revealed
    local isLog = current.key == "log"

    for i, tab in ipairs(ui.tabs) do
        if TABS[i] == current then tab:Disable() else tab:Enable() end
    end
    ui.hint:SetText(current.hint)

    for i, row in ipairs(ui.rows) do
        local e = list[offset + i]
        row.entry = e
        if e then
            if isLog then
                row.label:SetText(logLabel(e.log, masked))
                row.label:SetWidth(370)
                row.remove:Hide()
            else
                row.label:SetText(masked and MASK or e.text)
                row.label:SetWidth(290)
                row.remove:Show()
            end
            row:Show()
        else
            row:Hide()
        end
    end

    ui.count:SetText(plural(#list, current.noun) .. (masked and #list > 0 and " (hidden)" or ""))
    if #list > ROWS then
        ui.page:SetText(("%d-%d of %d"):format(offset + 1, math.min(offset + ROWS, #list), #list))
    else
        ui.page:SetText("")
    end
    if offset > 0 then ui.prev:Enable() else ui.prev:Disable() end
    if offset + ROWS < #list then ui.next:Enable() else ui.next:Disable() end
    ui.empty:SetText(isLog and "Nothing hidden yet." or "Nothing here yet.")
    if #list == 0 then ui.empty:Show() else ui.empty:Hide() end
    if isLog then
        ui.input:Hide()
        ui.add:Hide()
        ui.clear:Show()
        ui.preview:Show()
        ui.preview:SetText(ns.db.preview and "Preview: ON" or "Preview: OFF")
        if #list > 0 then ui.clear:Enable() else ui.clear:Disable() end
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
    if current.masked then ui.target:Hide() else ui.target:Show() end
    if current.key == "guilds" then ui.scan:Show() else ui.scan:Hide() end

    ui.checks.enabled:SetChecked(ns.db.enabled)
    ui.checks.alerts:SetChecked(ns.db.alerts)
    ui.checks.autoDecline:SetChecked(ns.db.autoDecline)
    ui.hidden:SetText(("Hidden this session: %d"):format(ns.hiddenSession or 0))

    local minutes = ns.db.reminderMinutes
    ui.reminder:SetText("Remind me to scan every " .. ns.FormatInterval(minutes))
    if minutes > ns.REMINDER_MIN then ui.less:Enable() else ui.less:Disable() end
    if minutes < ns.REMINDER_MAX then ui.more:Enable() else ui.more:Disable() end
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
        setStatus(("Added <%s>. Press Scan to find its online members."):format(guild))
    end
end

local function removeRow(row)
    local e = row.entry
    if not e then return end
    local removed = ns[current.remove](e.key)
    if removed then
        setStatus(current.masked and not revealed and ("Removed 1 %s."):format(current.noun) or ("Removed %s."):format(removed))
    end
end

-- Hovering a shown Hidden tab line gives the whole message.
local function rowEnter(row)
    local e = row.entry and row.entry.log
    if not (e and revealed and GameTooltip) then return end
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
-- Building the window
---------------------------------------------------------------------------

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function fontString(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
end

local function checkbox(parent, label, key, x, y)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", x, y)
    local text = fontString(parent)
    text:SetPoint("LEFT", c, "RIGHT", 2, 0)
    text:SetText(label)
    c:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
    end)
    return c
end

local function build()
    local f = CreateFrame("Frame", "RudeBoyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ui.frame = f
    f:SetSize(430, 530)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "RudeBoyFrame") end

    local title = fontString(f, "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Rude Boy")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    ui.aboutButton = button(f, "About", 64, function()
        if ui.about:IsShown() then ui.about:Hide() else ui.about:Show() end
    end)
    ui.aboutButton:SetPoint("TOPLEFT", 18, -14)

    ui.tabs = {}
    for i, tab in ipairs(TABS) do
        local b = button(f, tab.label, 90, function() selectTab(tab) end)
        b:SetPoint("TOPLEFT", 22 + (i - 1) * 96, -46)
        ui.tabs[i] = b
    end

    ui.hint = fontString(f)
    ui.hint:SetPoint("TOPLEFT", 26, -80)
    ui.hint:SetWidth(380)
    ui.hint:SetJustifyH("LEFT")

    local input = CreateFrame("EditBox", "RudeBoyInput", f, "InputBoxTemplate")
    ui.input = input
    input:SetSize(270, 20)
    input:SetPoint("TOPLEFT", 30, -100)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", addFromInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    ui.add = button(f, "Add", 90, addFromInput)
    ui.add:SetPoint("TOPLEFT", 310, -99)
    ui.target = button(f, "Add target", 110, addTarget)
    ui.target:SetPoint("TOPLEFT", 24, -126)
    ui.scan = button(f, "Scan", 90, function() ns.Scan("") end)
    ui.scan:SetPoint("TOPLEFT", 140, -126)
    ui.reveal = button(f, "Show", 90, function()
        revealed = not revealed
        ns.RefreshUI()
    end)
    ui.reveal:SetPoint("TOPLEFT", 24, -126)
    ui.clear = button(f, "Clear", 90, function()
        local log = ns.db.log
        for i = #log, 1, -1 do log[i] = nil end
        setStatus("Cleared the hidden lines list.")
        ns.RefreshUI()
    end)
    ui.clear:SetPoint("TOPLEFT", 120, -126)
    ui.preview = button(f, "Preview: OFF", 130, function()
        ns.db.preview = not ns.db.preview
        setStatus(ns.db.preview and "Preview on: lines stay in chat, tagged with why they'd be hidden."
            or "Preview off: matching lines are hidden again.")
        ns.RefreshUI()
    end)
    ui.preview:SetPoint("TOPLEFT", 216, -126)

    ui.status = fontString(f)
    ui.status:SetPoint("TOPLEFT", 26, -154)
    ui.status:SetWidth(380)
    ui.status:SetJustifyH("LEFT")

    ui.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(380, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 24, -172 - (i - 1) * ROW_HEIGHT)
        if i % 2 == 1 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if bg.SetColorTexture then bg:SetColorTexture(1, 1, 1, 0.05) else bg:SetTexture(1, 1, 1, 0.05) end
        end
        row.label = fontString(row, "GameFontHighlight")
        row.label:SetPoint("LEFT", 6, 0)
        row.label:SetWidth(290)
        row.label:SetJustifyH("LEFT")
        row.label:SetHeight(ROW_HEIGHT)
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        row:EnableMouse(true)
        row:SetScript("OnEnter", rowEnter)
        row:SetScript("OnLeave", rowLeave)
        row.remove = button(row, "Remove", 76, function() removeRow(row) end)
        row.remove:SetHeight(20)
        row.remove:SetPoint("RIGHT", -2, 0)
        ui.rows[i] = row
    end

    ui.empty = fontString(f, "GameFontDisable")
    ui.empty:SetPoint("TOP", 0, -240)
    ui.empty:SetText("Nothing here yet.")

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) scroll(-delta) end)

    local listBottom = -172 - ROWS * ROW_HEIGHT - 8
    ui.count = fontString(f)
    ui.count:SetPoint("TOPLEFT", 26, listBottom - 4)
    ui.page = fontString(f)
    ui.page:SetPoint("TOP", 20, listBottom - 4)
    ui.prev = button(f, "<", 30, function() scroll(-ROWS) end)
    ui.prev:SetPoint("TOPRIGHT", -62, listBottom)
    ui.next = button(f, ">", 30, function() scroll(ROWS) end)
    ui.next:SetPoint("TOPRIGHT", -28, listBottom)

    local checksY = listBottom - 34
    ui.checks = {
        enabled = checkbox(f, "Hide chat lines", "enabled", 22, checksY),
        alerts = checkbox(f, "Group warnings", "alerts", 152, checksY),
        autoDecline = checkbox(f, "Decline invites", "autoDecline", 282, checksY),
    }
    local reminderY = checksY - 32
    ui.less = button(f, "-", 24, function() ns.SetReminder(ns.db.reminderMinutes - ns.REMINDER_STEP) end)
    ui.less:SetPoint("TOPLEFT", 24, reminderY)
    ui.more = button(f, "+", 24, function() ns.SetReminder(ns.db.reminderMinutes + ns.REMINDER_STEP) end)
    ui.more:SetPoint("TOPLEFT", 50, reminderY)
    ui.reminder = fontString(f)
    ui.reminder:SetPoint("TOPLEFT", 82, reminderY - 5)
    ui.lastScan = fontString(f, "GameFontDisableSmall")
    ui.lastScan:SetPoint("TOPRIGHT", -28, reminderY - 5)

    ui.hidden = fontString(f, "GameFontDisableSmall")
    ui.hidden:SetPoint("BOTTOMLEFT", 26, 20)

    -- About: a panel laid over the lists until closed
    local about = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ui.about = about
    about:SetPoint("TOPLEFT", 14, -40)
    about:SetPoint("BOTTOMRIGHT", -14, 14)
    about:SetFrameLevel((f:GetFrameLevel() or 0) + 10)
    about:EnableMouse(true)
    if about.SetBackdrop then
        about:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
    end
    ui.aboutText = fontString(about, "GameFontHighlight")
    ui.aboutText:SetPoint("TOPLEFT", 16, -16)
    ui.aboutText:SetWidth(368)
    ui.aboutText:SetJustifyH("LEFT")
    ui.aboutText:SetJustifyV("TOP")
    ui.aboutText:SetText(ABOUT)
    ui.aboutBack = button(about, "Back", 90, function() about:Hide() end)
    ui.aboutBack:SetPoint("BOTTOM", 0, 14)
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
