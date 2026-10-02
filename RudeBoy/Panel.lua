--[[
    Panel.lua - a small panel showing what Rude Boy has done: how many lines it has blocked,
    how many /who searches are still pending, how many invites from blocked people it has
    declined or warned about, and who was blocked most recently and why.
    Informative only.

    Scan starts a scan of everything on your lists; Settings opens the main window; Recent
    opens a fly-out beside the panel with the last ten hidden lines in full, so you can check
    what you missed. The fly-out starts closed every session and shows nothing until asked.

    Drag it anywhere while unlocked. Locked, it can't be moved and clicks pass through it to
    the game; its lock and close buttons still work. Position, lock and shown/hidden are saved.

    /rb panel                 show or hide
    /rb panel lock | unlock
    /rb panel reset           back to the default position, unlocked

    Look: the flat skin from Skin.lua. A title strip with the name, Lock and x; flat Scan,
    Settings and Recent buttons; light text for the counts and names, dim headings. The
    fly-out is the same: a title strip with an x over the wrapped text.
]]

local ADDON, ns = ...

local S = ns.Skin

local NAMES = 8           -- names listed
local RECENT = 10         -- hidden lines shown in the fly-out
local FLY_WIDTH = 380
local WIDTH = 230
local LINE = 14
local PAD = S.PAD         -- 8: the margin inside the panel
local TITLE_H = S.TITLE_H -- 20: the title strip
local BTN_H = 18
local ROWS_TOP = TITLE_H + 6 + BTN_H + 6 + 3 * LINE + 2 + LINE + 2   -- where the first name row starts

local panel
local flyout
ns.panel = nil
ns.flyout = nil

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

-- Why a line was hidden, in a word or two. Never names the filtered word.
local function shortReason(e)
    return e.kind == "guild" and (tostring(e.reason):match("<(.-)>") or "guild")
        or e.kind == "player" and "player list"
        or "word"
end

-- The last hidden lines, newest first, one paragraph each.
function ns.RecentLinesText(limit)
    local log = ns.db and ns.db.log or {}
    local out = {}
    for i = #log, math.max(1, #log - (limit or RECENT) + 1), -1 do
        local e = log[i]
        out[#out + 1] = ("|cff999999%s  [%s]|r  |cffffd100%s|r: %s  |cff999999(%s)|r"):format(
            tostring(e.at or ""), tostring(e.where or ""), tostring(e.author), tostring(e.msg), shortReason(e))
    end
    if #out == 0 then return "Nothing has been hidden yet." end
    return table.concat(out, "\n\n")
end

local function refreshFlyout()
    if not (flyout and flyout:IsShown()) then return end
    flyout.text:SetText(ns.RecentLinesText(RECENT))
    local h = flyout.text.GetStringHeight and flyout.text:GetStringHeight()
    flyout:SetHeight(TITLE_H + 6 + (tonumber(h) or 160) + PAD)

    -- beside the panel, on whichever side has room
    flyout:ClearAllPoints()
    local right = panel.GetRight and panel:GetRight()
    local screen = UIParent.GetRight and UIParent:GetRight()
    if tonumber(right) and tonumber(screen) and right + FLY_WIDTH + 4 > screen then
        flyout:SetPoint("TOPRIGHT", panel, "TOPLEFT", -4, 0)
    else
        flyout:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
    end
end

local function buildFlyout()
    flyout = CreateFrame("Frame", "RudeBoyRecent", panel, S.template())
    ns.flyout = flyout
    flyout:SetSize(FLY_WIDTH, 200)
    flyout:SetFrameStrata("MEDIUM")
    flyout:EnableMouse(true)
    S.skin(flyout, S.COLOR.window)

    local strip = S.titleStrip(flyout, ("Last %d hidden lines"):format(RECENT), function() flyout:Hide() end)
    flyout.titleBar = strip
    flyout.close = strip.close

    flyout.text = S.text(flyout, "")
    flyout.text:SetPoint("TOPLEFT", flyout, "TOPLEFT", PAD, -(TITLE_H + 6))
    flyout.text:SetWidth(FLY_WIDTH - 2 * PAD)
    flyout.text:SetJustifyH("LEFT")
    flyout.text:SetJustifyV("TOP")
    if flyout.text.SetWordWrap then flyout.text:SetWordWrap(true) end
    flyout:SetScript("OnShow", refreshFlyout)
    flyout:Hide()
end

function ns.ToggleRecent()
    if not panel then return end
    if not flyout then buildFlyout() end
    if flyout:IsShown() then flyout:Hide() else flyout:Show() refreshFlyout() end
end

function ns.RefreshPanel()
    refreshFlyout()
    if not (panel and panel:IsShown() and ns.db) then return end
    local commas = ns.Commas or tostring
    panel.total:SetText(("Lines blocked: |cffffd100%s|r  (%s this session)"):format(
        commas(ns.db.hiddenTotal), commas(ns.hiddenSession or 0)))

    local pending = ns.ScanPending and ns.ScanPending() or 0
    panel.pending:SetText(pending > 0
        and ("Searches pending: |cffffd100%d|r  (sent as you play)"):format(pending)
        or "Searches pending: |cff999999none|r")

    local inv = ns.db.invites
    panel.invites:SetText(("Invites: |cffffd100%s|r declined, |cffffd100%s|r warned"):format(
        commas(inv.declined), commas(inv.warned)))

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
    panel:SetHeight(ROWS_TOP + math.max(1, #list) * LINE + PAD)
end

local function build()
    panel = CreateFrame("Frame", "RudeBoyPanel", UIParent, S.template())
    ns.panel = panel
    panel:SetSize(WIDTH, ROWS_TOP + LINE + PAD)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not ns.db.panel.locked then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    S.skin(panel, S.COLOR.window)

    -- title strip: the name, Lock and x
    local strip = S.titleStrip(panel, "Rude Boy", function() ns.SetPanelShown(false) end)
    panel.titleBar = strip
    panel.close = strip.close

    local lock = S.button(strip, "Lock", 44, function() ns.SetPanelLocked(not ns.db.panel.locked) end)
    lock:SetHeight(TITLE_H - 4)
    lock:SetPoint("RIGHT", strip.close, "LEFT", -2, 0)
    panel.lock = lock

    -- second row: actions
    local y = -(TITLE_H + 6)
    local width = math.floor((WIDTH - 2 * PAD - 4) / 3)
    local scan = S.button(panel, "Scan", width, function() ns.Scan("") end)   -- a click, so the first /who may go out
    scan:SetHeight(BTN_H)
    scan:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    panel.scan = scan

    local settings = S.button(panel, "Settings", width, function() ns.ToggleUI() end)
    settings:SetHeight(BTN_H)
    settings:SetPoint("LEFT", scan, "RIGHT", 2, 0)
    panel.settings = settings

    local recent = S.button(panel, "Recent", width, function() ns.ToggleRecent() end)
    recent:SetHeight(BTN_H)
    recent:SetPoint("LEFT", settings, "RIGHT", 2, 0)
    panel.recent = recent
    y = y - BTN_H - 6

    panel.total = S.text(panel, "")
    panel.total:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    y = y - LINE

    panel.pending = S.text(panel, "")
    panel.pending:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    y = y - LINE

    panel.invites = S.text(panel, "")
    panel.invites:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    y = y - LINE - 2

    local heading = S.dim(panel, "Recently blocked:")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    y = y - LINE - 2   -- now at -ROWS_TOP

    panel.rows = {}
    for i = 1, NAMES do
        local row = S.text(panel, "")
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y - (i - 1) * LINE)
        row:SetWidth(WIDTH - 2 * PAD)
        row:SetJustifyH("LEFT")
        if row.SetWordWrap then row:SetWordWrap(false) end
        panel.rows[i] = row
    end
    panel.empty = S.dim(panel, "Nobody yet.")
    panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)

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
        if flyout then flyout:Hide() end
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
