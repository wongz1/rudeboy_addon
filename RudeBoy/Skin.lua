--[[
    Skin.lua - the flat look shared by every Rude Boy window, panel and button.

    No Blizzard frame art. Flat WHITE8X8 backdrops with a 1px solid black border (one physical
    screen pixel at any UI scale), dark neutral panels, tight 2 to 4px spacing, light grey text,
    dim grey labels, and one accent colour: the player's class colour if the client gives it,
    otherwise a muted cyan. The game's own fonts throughout.

    Everything is exposed on ns.Skin for UI.lua, Panel.lua and Minimap.lua:
      skin(frame, bg)    turn any frame flat (window token unless bg is given)
      panel(parent)      a flat panel-token frame (title strips, headers, list backgrounds)
      button(parent, text, width, onClick)   a flat 20px button; hover gets the accent border
      select(button, on) the pressed-in look for the current tab
      checkbox(parent, label, onClick)       a 14px flat box that fills with the accent colour
      editbox(parent, width, onEnter)        a flat 18px edit box; focus gets the accent border
      text / dim / header(parent, str)       font strings in the text, dim and header styles
]]

local ADDON, ns = ...

local Skin = {}
ns.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
local COLOR = {
    window = { 0.06, 0.06, 0.06, 0.85 },
    panel = { 0.10, 0.10, 0.10, 0.90 },
    panelHover = { 0.16, 0.16, 0.16, 0.95 },
    panelPushed = { 0.04, 0.04, 0.04, 0.95 },
    border = { 0, 0, 0, 1 },
    text = { 0.90, 0.90, 0.90, 1 },
    dim = { 0.55, 0.55, 0.55, 1 },
    stripe = { 1, 1, 1, 0.03 },     -- every other list row
}
Skin.WHITE = WHITE
Skin.COLOR = COLOR

local function accent()
    if RAID_CLASS_COLORS and UnitClass then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b, 1 end
    end
    return 0.35, 0.75, 0.85, 1
end
Skin.accent = accent

-- One screen pixel in UI units, so the 1px borders stay 1px at any UI scale.
local function pixel()
    if GetPhysicalScreenSize and UIParent and UIParent.GetEffectiveScale then
        local _, h = GetPhysicalScreenSize()
        local scale = UIParent:GetEffectiveScale()
        if h and h > 0 and scale and scale > 0 then return 768 / h / scale end
    end
    return 1
end
Skin.pixel = pixel

local function template()
    -- Newer clients need BackdropTemplate for SetBackdrop; older ones have it built in.
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end
Skin.template = template

local function skin(frame, bg)
    if not frame.SetBackdrop and Mixin and BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) end
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = WHITE, edgeFile = WHITE, tile = false, tileSize = 0, edgeSize = pixel(),
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    local c = bg or COLOR.window
    frame:SetBackdropColor(c[1], c[2], c[3], c[4])
    frame:SetBackdropBorderColor(COLOR.border[1], COLOR.border[2], COLOR.border[3], COLOR.border[4])
end
Skin.skin = skin

local function setBg(frame, c)
    if frame.SetBackdropColor then frame:SetBackdropColor(c[1], c[2], c[3], c[4]) end
end
Skin.setBg = setBg

local function setBorder(frame, r, g, b, a)
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(r, g, b, a) end
end
Skin.setBorder = setBorder

local function plainBorder(frame)
    setBorder(frame, COLOR.border[1], COLOR.border[2], COLOR.border[3], COLOR.border[4])
end
Skin.plainBorder = plainBorder

local function text(parent, str, color, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetText(str)
    local c = color or COLOR.text
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    return fs
end
Skin.text = text

local function header(parent, str)
    return text(parent, str, COLOR.text, "GameFontNormalSmall")
end
Skin.header = header

local function dim(parent, str)
    return text(parent, str, COLOR.dim, "GameFontHighlightSmall")
end
Skin.dim = dim

-- A flat panel inside a window (title strip, header, list background).
local function panel(parent)
    local p = CreateFrame("Frame", nil, parent, template())
    skin(p, COLOR.panel)
    return p
end
Skin.panel = panel

-- The resting look of a button: pressed in (accent border, lighter face) when selected, as the
-- current tab is, otherwise the plain panel face.
local function select(b, on)
    b.selected = on and true or false
    if on then
        setBorder(b, accent())
        setBg(b, COLOR.panelHover)
    else
        plainBorder(b)
        setBg(b, COLOR.panel)
    end
end
Skin.select = select

local function button(parent, str, width, onClick)
    local b = CreateFrame("Button", nil, parent, template())
    b:SetSize(width or 90, 20)
    skin(b, COLOR.panel)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    if b.SetPushedTextOffset then b:SetPushedTextOffset(0, 0) end
    b:SetText(str)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) setBorder(self, accent()) end)
    b:SetScript("OnLeave", function(self) select(self, self.selected) end)
    b:SetScript("OnMouseDown", function(self) setBg(self, COLOR.panelPushed) end)
    b:SetScript("OnMouseUp", function(self) setBg(self, COLOR.panelHover) end)
    return b
end
Skin.button = button

-- A flat check box: a 14px square that fills with the accent colour when checked. The label is
-- a child of the box, so hiding the box hides the label too.
local function checkbox(parent, str, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, template())
    cb:SetSize(14, 14)
    skin(cb, COLOR.panel)
    local fill = cb:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(WHITE)
    fill:SetVertexColor(accent())
    fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    cb:SetCheckedTexture(fill)
    local hover = cb:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture(WHITE)
    hover:SetVertexColor(1, 1, 1, 0.08)
    hover:SetAllPoints(cb)
    cb:SetHighlightTexture(hover)
    cb.label = text(cb, str)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self) onClick(self, self:GetChecked() and true or false) end)
    return cb
end
Skin.checkbox = checkbox

-- A flat edit box. Enter runs onEnter, Escape drops focus; the border takes the accent colour
-- while it has focus.
local function editbox(parent, name, width, onEnter)
    local e = CreateFrame("EditBox", name, parent, template())
    e:SetSize(width, 18)
    skin(e, COLOR.panel)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextColor(COLOR.text[1], COLOR.text[2], COLOR.text[3], COLOR.text[4])
    e:SetTextInsets(4, 4, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) setBorder(self, accent()) end)
    e:SetScript("OnEditFocusLost", function(self) plainBorder(self) end)
    e:SetScript("OnEnterPressed", function(self) onEnter(self) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end
Skin.editbox = editbox

-- A 20px title strip across the top of a window: the title left-aligned, a flat x on the
-- right that runs onClose. Returns the strip; the x is strip.close.
local TITLE_H = 20
Skin.TITLE_H = TITLE_H
Skin.PAD = 8

local function titleStrip(window, str, onClose)
    local strip = panel(window)
    strip:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    strip:SetHeight(TITLE_H)
    strip.title = header(strip, str)
    strip.title:SetPoint("LEFT", strip, "LEFT", 6, 0)
    strip.close = button(strip, "x", TITLE_H - 4, onClose)
    strip.close:SetHeight(TITLE_H - 4)
    strip.close:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
    return strip
end
Skin.titleStrip = titleStrip
