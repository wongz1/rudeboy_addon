--[[
    Bubbles.lua - hides the speech bubbles of blocked players.

    The game draws bubbles separately from the chat window. After a blocked player's say, yell
    or party line is hidden, the bubbles on screen are checked for that exact text for a
    moment and the matching one is made invisible. Bubbles are reused, so after any later
    say/yell/party line they are checked again and a reused one is shown again.

    Dungeons and raids keep bubbles away from addons, so this works in the open world only.
]]

local ADDON, ns = ...

ns.BUBBLE_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
}

local WATCH = 1.5        -- seconds to keep checking after a line
local REMEMBER = 30      -- seconds a hidden line's text stays matched

local hiddenTexts = {}   -- text -> GetTime() it stops being matched
local hiddenHolders = {} -- bubble frames made invisible
local watchUntil = 0

local function isSecret(v)
    return issecretvalue and issecretvalue(v)
end

-- The frame holding a bubble's text: a child with a String on newer clients, the bubble itself on older ones.
local function holderOf(bubble)
    local child = bubble.GetChildren and bubble:GetChildren()
    if child and child.String then return child end
    if bubble.String then return bubble end
end

local function scan()
    if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    local now = GetTime()
    for text, t in pairs(hiddenTexts) do
        if t < now then hiddenTexts[text] = nil end
    end
    for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles(false)) do
        local holder = holderOf(bubble)
        if holder then
            local text = holder.String:GetText()
            if text and not isSecret(text) and hiddenTexts[text] then
                if not hiddenHolders[holder] then
                    holder:SetAlpha(0)
                    hiddenHolders[holder] = true
                end
            elseif hiddenHolders[holder] then
                holder:SetAlpha(1)   -- reused for someone else's line
                hiddenHolders[holder] = nil
            end
        end
    end
end

local watcher = CreateFrame("Frame")
ns.bubbleWatcher = watcher
watcher:Hide()
local since = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    since = since + (elapsed or 0)
    if since < 0.05 then return end
    since = 0
    pcall(scan)
    if GetTime() > watchUntil then self:Hide() end
end)

-- Called for every say/yell/party line; `hiddenText` is the text when the line was hidden.
function ns.WatchBubbles(hiddenText)
    if not (ns.db and ns.db.bubbles) then return end
    if type(hiddenText) == "string" and not isSecret(hiddenText) then
        hiddenTexts[hiddenText] = GetTime() + REMEMBER
    end
    if hiddenText or next(hiddenHolders) then
        watchUntil = GetTime() + WATCH
        watcher:Show()
    end
end

-- Turning the setting off shows any bubble still hidden.
function ns.ShowAllBubbles()
    for holder in pairs(hiddenHolders) do pcall(holder.SetAlpha, holder, 1) end
    hiddenHolders = {}
    hiddenTexts = {}
    watcher:Hide()
end
