--[[
    UI.lua - the /rb window: view, add and remove filtered words, players and guilds.

    The Words tab shows every entry as ******** until you press Show, and goes back to
    masked whenever the window is reopened or you change tabs, so opening the window never
    puts the word list on screen by itself.

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
}

local ui = {}           -- the widgets, also reached by the tests as ns.ui
ns.ui = ui
local current = TABS[1]
local offset = 0        -- index of the first entry shown
local revealed = false  -- Words tab only

local function plural(n, noun) return ("%d %s%s"):format(n, noun, n == 1 and "" or "s") end

local function entries()
    local list = {}
    for key, shown in pairs(ns.db[current.key]) do
        list[#list + 1] = { key = key, text = (shown == true) and key or shown }
    end
    table.sort(list, function(a, b) return a.text:lower() < b.text:lower() end)
    return list
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

    for i, tab in ipairs(ui.tabs) do
        if TABS[i] == current then tab:Disable() else tab:Enable() end
    end
    ui.hint:SetText(current.hint)

    for i, row in ipairs(ui.rows) do
        local e = list[offset + i]
        row.entry = e
        if e then
            row.label:SetText(masked and MASK or e.text)
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
    if #list == 0 then ui.empty:Show() else ui.empty:Hide() end

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
    f:SetSize(430, 500)
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

    ui.tabs = {}
    for i, tab in ipairs(TABS) do
        local b = button(f, tab.label, 110, function() selectTab(tab) end)
        b:SetPoint("TOPLEFT", 22 + (i - 1) * 130, -46)
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
    ui.hidden = fontString(f, "GameFontDisableSmall")
    ui.hidden:SetPoint("BOTTOMLEFT", 26, 20)

    f:SetScript("OnShow", function()
        revealed = false
        offset = 0
        setStatus("")
        ns.RefreshUI()
    end)
    f:SetScript("OnHide", function()
        revealed = false
        ui.input:ClearFocus()
    end)
    f:Hide()
end

function ns.ToggleUI()
    if not ui.frame then build() end
    if ui.frame:IsShown() then ui.frame:Hide() else ui.frame:Show() end
end
