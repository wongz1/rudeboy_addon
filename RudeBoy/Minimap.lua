--[[
    Minimap.lua - a button on the minimap.

    Left-click opens the Rude Boy window. Right-click shows or hides the on-screen panel.
    Hovering shows lines blocked, searches pending and invites declined or warned about.
    Drag it around the minimap's edge; where you leave it is saved.

    /rb minimap            show or hide the button
    /rb minimap reset      back to its default place

    Look: a 20px flat square in the skin from Skin.lua, the icon inset by 2px, the border in the
    accent colour while hovered.
]]

local ADDON, ns = ...

local S = ns.Skin

local ICON = "Interface\\Icons\\Spell_Holy_Silence"
local DEFAULT_ANGLE = 215      -- degrees, counter-clockwise from the right; lower left

local button
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

local function place()
    local angle = math.rad(ns.db.minimap.angle or DEFAULT_ANGLE)
    local radius = ((Minimap.GetWidth and Minimap:GetWidth()) or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
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

-- Called at login, once the settings are in place.
function ns.InitMinimap()
    if ns.db.minimap.shown then ns.SetMinimapShown(true) end
end
