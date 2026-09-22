--[[
    Chat.lua - hides whole chat lines.

    A line is hidden when its sender is on your player list, the sender is known to be in a
    guild on your guild list, or the text contains one of your words. Your own lines are
    never hidden.

    The game runs a chat filter once per chat window showing the line, so the decision is
    kept by line ID: the line is judged, counted and logged once.
]]

local ADDON, ns = ...

local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_AFK", "CHAT_MSG_DND",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local LOG_SIZE = 20
local MEMORY = 300         -- how many line IDs to remember decisions for

ns.log = {}                -- last LOG_SIZE hidden lines, newest last
ns.hiddenSession = 0

local decided, decidedOrder = {}, {}

-- The last few senders exactly as the game wrote them, for /rb debug.
ns.recentAuthors = {}
local function noteAuthor(author, guid)
    local list = ns.recentAuthors
    for _, a in ipairs(list) do
        if a.author == author and a.guid == guid then return end
    end
    list[#list + 1] = { author = author, guid = guid }
    if #list > 5 then table.remove(list, 1) end
end

local function isSelf(author, guid)
    if guid and UnitGUID and guid == UnitGUID("player") then return true end
    return ns.NormalizeName(author) == ns.NormalizeName(UnitName("player"))
end

local function judge(event, msg, author, guid)
    if not (ns.db and ns.db.enabled) then return false end
    if isSelf(author, guid) then return false end
    local reason = ns.LineReason(msg, author, guid)
    if not reason then return false end

    ns.hiddenSession = ns.hiddenSession + 1
    ns.db.hiddenTotal = ns.db.hiddenTotal + 1
    ns.log[#ns.log + 1] = { event = event, author = author, msg = msg, reason = reason, at = date and date("%H:%M") or "" }
    if #ns.log > LOG_SIZE then table.remove(ns.log, 1) end
    return true
end

-- Chat filter: returning true removes the line from that chat window.
-- Arguments after msg and author follow the CHAT_MSG_* payload: arg11 is the line ID, arg12 the GUID.
function ns.ChatFilter(frame, event, msg, author, ...)
    local lineID = select(9, ...)
    local guid = select(10, ...)
    if type(lineID) == "number" and decided[lineID] ~= nil then return decided[lineID] end
    pcall(noteAuthor, author, guid)

    -- An error here would break chat, so fail open: show the line.
    local ok, hide = pcall(judge, event, msg, author, guid)
    hide = ok and hide or false

    if type(lineID) == "number" then
        decided[lineID] = hide
        decidedOrder[#decidedOrder + 1] = lineID
        if #decidedOrder > MEMORY then decided[table.remove(decidedOrder, 1)] = nil end
    end
    return hide
end

for _, event in ipairs(EVENTS) do
    ChatFrame_AddMessageEventFilter(event, ns.ChatFilter)
end
