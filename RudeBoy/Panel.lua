--[[
    Panel.lua - a small panel showing what Rude Boy has done: how many lines it has blocked,
    how many /who searches are still pending, and who was blocked most recently and why.
    Informative only.

    Drag it anywhere while unlocked. Locked, it can't be moved and clicks pass through it to
    the game; its lock and close buttons still work. Position, lock and shown/hidden are saved.

    /rb panel                 show or hide
    /rb panel lock | unlock
    /rb panel reset           back to the default position, unlocked
]]

local ADDON, ns = ...

local NAMES = 8           -- names listed
local WIDTH = 230
local LINE = 14

local panel
ns.panel = nil

-- The most recently blocked people, newest first: { name = , count = , why = }.
-- Built from the saved list of hidden lines, so it survives a restart.
function ns.RecentlyBlocked(limit)
    local list, byKey = {}, {}
    local log = ns.db and ns.db.log or {}
    for i = #log, 1, -1 do
        local e = log[i]
        local key = ns.NormalizeName(e.author)
        local entry = byKey[key]
        if not entry then
            local why = e.kind == "guild" and (tostring(e.reason):match("<(.-)>") or "guild")
                or e.kind == "player" and "player list"
                or "word"
            entry = { name = tostring(e.author), count = 0, why = why }
            byKey[key] = entry
            list[#list + 1] = entry
        end
        entry.count = entry.count + 1
    end
    while limit and #list > limit do list[#list] = nil end
    return list
end

local function savePosition()
    local point, _, relativePoint, x, y = panel:GetPoint()
    local p = ns.db.panel
    p.point, p.relativePoint, p.x, p.y = point, relativePoint, x, y
end

local function applyPosition()
    local p = ns.db.panel
    panel:ClearAllPoints()
    if p.point then
        panel:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
    else
        panel:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    end
end

local function applyLock()
    local locked = ns.db.panel.locked
    panel:SetMovable(not locked)
    panel:EnableMouse(not locked)   -- locked: clicks go through to the game
    panel.lock:SetText(locked and "Unlock" or "Lock")
end

function ns.RefreshPanel()
    if not (panel and panel:IsShown() and ns.db) then return end
    local commas = ns.Commas or tostring
    panel.total:SetText(("Lines blocked: |cffffd100%s|r  (%s this session)"):format(
        commas(ns.db.hiddenTotal), commas(ns.hiddenSession or 0)))

    local pending = ns.ScanPending and ns.ScanPending() or 0
    panel.pending:SetText(pending > 0
        and ("Searches pending: |cffffd100%d|r  (sent as you play)"):format(pending)
        or "Searches pending: |cff999999none|r")

    local list = ns.RecentlyBlocked(NAMES)
    for i, row in ipairs(panel.rows) do
        local e = list[i]
        if e then
            row:SetText(("%s  |cffffd100x%d|r  |cff999999%s|r"):format(e.name, e.count, e.why))
            row:Show()
        else
            row:Hide()
        end
    end
    if #list == 0 then panel.empty:Show() else panel.empty:Hide() end
    panel:SetHeight(78 + math.max(1, #list) * LINE + 10)
end

local function build()
    panel = CreateFrame("Frame", "RudeBoyPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ns.panel = panel
    panel:SetSize(WIDTH, 78 + LINE + 10)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not ns.db.panel.locked then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    -- opaque, like the main window
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    if bg.SetColorTexture then bg:SetColorTexture(0.07, 0.07, 0.08, 1) else bg:SetTexture(0.07, 0.07, 0.08, 1) end
    if panel.SetBackdrop then
        panel:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    end

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Rude Boy")

    local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    close:SetSize(20, 18)
    close:SetPoint("TOPRIGHT", -7, -6)
    close:SetText("x")
    close:SetScript("OnClick", function() ns.SetPanelShown(false) end)
    panel.close = close

    local lock = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lock:SetSize(58, 18)
    lock:SetPoint("RIGHT", close, "LEFT", -3, 0)
    lock:SetScript("OnClick", function() ns.SetPanelLocked(not ns.db.panel.locked) end)
    panel.lock = lock

    panel.total = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.total:SetPoint("TOPLEFT", 10, -30)

    panel.pending = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.pending:SetPoint("TOPLEFT", 10, -44)

    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    heading:SetPoint("TOPLEFT", 10, -60)
    heading:SetText("Recently blocked:")

    panel.rows = {}
    for i = 1, NAMES do
        local row = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", 10, -74 - (i - 1) * LINE)
        row:SetWidth(WIDTH - 20)
        row:SetJustifyH("LEFT")
        if row.SetWordWrap then row:SetWordWrap(false) end
        panel.rows[i] = row
    end
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.empty:SetPoint("TOPLEFT", 10, -74)
    panel.empty:SetText("Nobody yet.")

    panel:SetScript("OnShow", ns.RefreshPanel)
    panel:Hide()
end

function ns.SetPanelShown(shown)
    ns.db.panel.shown = shown and true or false
    if shown then
        if not panel then build() end
        applyPosition()
        applyLock()
        panel:Show()
        ns.RefreshPanel()
    elseif panel then
        panel:Hide()
    end
    ns.Changed()
end

function ns.SetPanelLocked(locked)
    ns.db.panel.locked = locked and true or false
    if panel then applyLock() end
end

function ns.ResetPanel()
    local p = ns.db.panel
    p.point, p.relativePoint, p.x, p.y, p.locked = nil, nil, nil, nil, false
    ns.SetPanelShown(true)
end

-- Called at login, once the settings are in place.
function ns.InitPanel()
    if ns.db.panel.shown then ns.SetPanelShown(true) end
end
