--[[
    Minimap.lua - a button on the minimap.

    Left-click opens the Rude Boy window. Right-click shows or hides the on-screen panel.
    Hovering shows lines blocked, searches pending and invites declined or warned about.
    Drag it around the minimap's edge; where you leave it is saved.

    /rb minimap                          show or hide the button
    /rb minimap reset                    back to its default place
    /rb minimap round | square | auto    the shape of the minimap it sits around

    Round puts the button on the circle just outside a round minimap. Square puts it on the
    square just outside a square one, in the same direction from the centre. Auto, the default,
    asks the interface: an addon that squares the minimap says so through the global function
    GetMinimapShape() ("SQUARE" or "ROUND"), and may say how much room it has taken above,
    below, left and right of the map through GetMinimapEdgeInsets(); the button then sits
    clear of that. With neither function there, auto means round. The button looks again once
    a second, so it follows the map when another addon changes it.

    Look: a 20px flat square in the skin from Skin.lua, the icon inset by 2px, the border in the
    accent colour while hovered.
]]

local ADDON, ns = ...

local S = ns.Skin

local ICON = "Interface\\Icons\\Spell_Holy_Silence"
local DEFAULT_ANGLE = 215      -- degrees, counter-clockwise from the right; lower left
local SHAPES = { auto = true, round = true, square = true }
local NEXT_SHAPE = { auto = "round", round = "square", square = "auto" }

local button, watcher
local placed            -- what the last placement was worked out from, to notice a change
ns.minimapButton = nil

-- What the tooltip shows, as { left, right } pairs. Also used by the tests.
function ns.MinimapLines()
    local db = ns.db
    local commas = ns.Commas or tostring
    local pending = ns.ScanPending and ns.ScanPending() or 0
    return {
        { "Lines blocked", ("%s  (%s this session)"):format(commas(db.hiddenTotal), commas(ns.hiddenSession or 0)) },
        { "Searches pending", pending > 0 and tostring(pending) or "none" },
        { "Invites declined", commas(db.invites.declined) },
        { "Invites warned about", commas(db.invites.warned) },
    }
end

local function showTooltip(self)
    if not (GameTooltip and ns.db) then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Rude Boy", 1, 0.82, 0)
    for _, line in ipairs(ns.MinimapLines()) do
        if GameTooltip.AddDoubleLine then
            GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 0.82, 0)
        else
            GameTooltip:AddLine(line[1] .. ": " .. line[2], 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open the window", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: show or hide the panel", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- "round" or "square": the setting, or with auto what the interface says.
function ns.MinimapShape()
    local want = ns.db.minimap.shape
    if want == "round" or want == "square" then return want end
    if type(GetMinimapShape) == "function" then
        local ok, shape = pcall(GetMinimapShape)
        if ok and shape == "SQUARE" then return "square" end
    end
    return "round"
end

-- The room another addon has taken above, below, left and right of a square minimap.
local function insets()
    if type(GetMinimapEdgeInsets) ~= "function" then return 0, 0, 0, 0 end
    local function n(v) return type(v) == "number" and v > 0 and v or 0 end
    local ok, top, bottom, left, right = pcall(GetMinimapEdgeInsets)
    if not ok then return 0, 0, 0, 0 end
    return n(top), n(bottom), n(left), n(right)
end

-- Everything a placement depends on other than the angle.
local function layout()
    local width = Minimap.GetWidth and Minimap:GetWidth()
    if type(width) ~= "number" or width <= 0 then width = 140 end
    local shape = ns.MinimapShape()
    if shape == "square" then return shape, width, insets() end
    return shape, width, 0, 0, 0, 0
end

-- The button's centre, from the minimap's centre: on the circle just outside a round map, on
-- the square just outside a square one.
local function offset(angle, shape, width, top, bottom, left, right)
    local x, y = math.cos(angle), math.sin(angle)
    if shape ~= "square" then
        local radius = width / 2 + 5
        return x * radius, y * radius
    end
    local half = width / 2 + 12
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m * half, y / m * half
    if y >= half - 0.001 then y = y + top elseif y <= -half + 0.001 then y = y - bottom end
    if x >= half - 0.001 then x = x + right elseif x <= -half + 0.001 then x = x - left end
    return x, y
end

local function place()
    local shape, width, top, bottom, left, right = layout()
    local angle = math.rad(tonumber(ns.db.minimap.angle) or DEFAULT_ANGLE)
    local x, y = offset(angle, shape, width, top, bottom, left, right)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    placed = table.concat({ shape, width, top, bottom, left, right }, ":")
end

-- Once a second: has the minimap changed shape or size since the button was put there?
local function look()
    if placed ~= table.concat({ layout() }, ":") then place() end
end

-- While dragging, the button follows the cursor's direction from the minimap's centre.
local function followCursor()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    if not (mx and my and px and py) then return end
    local angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    ns.db.minimap.angle = (angle + 360) % 360
    place()
end

local function build()
    button = CreateFrame("Button", "RudeBoyMinimapButton", Minimap, S.template())
    ns.minimapButton = button
    button:SetSize(20, 20)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    S.skin(button, S.COLOR.panel)   -- a flat square with a 1px border; the accent colour while hovered

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON)
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.SetPanelShown(not ns.db.panel.shown)
        else
            ns.ToggleUI()
        end
    end)
    button:SetScript("OnEnter", function(self)
        S.setBorder(self, S.accent())
        showTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        S.plainBorder(self)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnDragStart", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", followCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- A child of the button, so it only runs while the button is shown.
    watcher = CreateFrame("Frame", "RudeBoyMinimapWatcher", button)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (type(dt) == "number" and dt or 0)
        if elapsed < 1 then return end
        elapsed = 0
        look()
    end)
end

function ns.SetMinimapShown(shown)
    ns.db.minimap.shown = shown and true or false
    if shown then
        if not Minimap then return end
        if not button then build() end
        place()
        button:Show()
    elseif button then
        button:Hide()
    end
end

function ns.ResetMinimap()
    ns.db.minimap.angle = DEFAULT_ANGLE
    ns.SetMinimapShown(true)
end

function ns.NextMinimapShape()
    return NEXT_SHAPE[ns.db.minimap.shape] or "auto"
end

-- "auto", "round" or "square"; anything else is refused.
function ns.SetMinimapShape(shape)
    if not SHAPES[shape] then return false end
    ns.db.minimap.shape = shape
    if button then place() end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

-- "Minimap: auto (round now)", for the window's button.
function ns.MinimapShapeLabel()
    local shape = ns.db.minimap.shape
    if shape == "auto" then return ("Minimap: auto (%s now)"):format(ns.MinimapShape()) end
    return "Minimap: " .. tostring(shape)
end

-- Called at login, once the settings are in place.
function ns.InitMinimap()
    if ns.db.minimap.shown then ns.SetMinimapShown(true) end
end
