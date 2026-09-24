--[[
    Tooltip.lua - a line in a player's tooltip when Rude Boy blocks them, or has exempted them.

    Hovering also records the player's guild, like targeting does, so the tooltip is right the
    first time. Newer clients route tooltips through TooltipDataProcessor, older ones through
    GameTooltip's OnTooltipSetUnit script; whichever exists is used.
]]

local ADDON, ns = ...

function ns.TooltipLine(name, guild, guid)
    if not (ns.db and name) then return nil end
    if ns.IsExempt(name) then return "Rude Boy: exempt, always let through", 0.4, 1, 0.4 end
    local why = ns.PersonReason(name, guild, guid)
    if why then return ("Blocked by Rude Boy (%s)"):format(why), 1, 0.3, 0.3 end
    return nil
end

local function onUnitTooltip(tooltip)
    if not (tooltip and tooltip.GetUnit and tooltip.AddLine) then return end
    local _, unit = tooltip:GetUnit()
    if not unit or not (UnitIsPlayer and UnitIsPlayer(unit)) then return end
    local name, guild = ns.LearnUnit(unit)
    local text, r, g, b = ns.TooltipLine(name, guild, UnitGUID and UnitGUID(unit))
    if text then
        tooltip:AddLine(text, r, g, b)
        if tooltip.Show then tooltip:Show() end
    end
end

local function hook(tooltip)
    pcall(onUnitTooltip, tooltip)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, hook)
elseif GameTooltip and GameTooltip.HookScript and (not GameTooltip.HasScript or GameTooltip:HasScript("OnTooltipSetUnit")) then
    GameTooltip:HookScript("OnTooltipSetUnit", hook)
end
