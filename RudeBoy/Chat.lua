--[[
    Chat.lua - hides whole chat lines.

    A line is hidden when its sender is on your player list, the sender is known to be in a
    guild on your guild list, or the text contains one of your words. Your own lines are
    never hidden.

    The game runs a chat filter once per chat window showing the line, so the decision is
    kept by line ID: the line is judged, counted and logged once.

    Every hidden line goes into RudeBoyDB.log (the last 100, saved with your settings), shown
    on the window's Hidden tab. Preview mode leaves the lines in chat with a grey tag saying
    why they would be hidden, for testing.
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

ns.LOG_SIZE = 100
local MEMORY = 300         -- how many line IDs to remember decisions for

ns.hiddenSession = 0

local decided, decidedOrder = {}, {}

-- The last few senders exactly as the game wrote them, for /rb debug. Saved too, so the
-- names can be read from the SavedVariables file outside the game.
ns.recentAuthors = {}
local function noteAuthor(author, guid)
    local list = ns.recentAuthors
    if ns.db then ns.db.recentAuthors = list end
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

local function judge(event, msg, author, guid, where)
    if not (ns.db and ns.db.enabled) then return false end
    if isSelf(author, guid) then return false end
    local reason = ns.LineReason(msg, author, guid)
    if not reason then return false end

    ns.hiddenSession = ns.hiddenSession + 1
    ns.db.hiddenTotal = ns.db.hiddenTotal + 1
    local log = ns.db.log
    log[#log + 1] = {
        at = date and date("%m-%d %H:%M") or "",
        where = where,
        author = author,
        msg = msg,
        kind = reason:match("^%a+"),   -- "word", "player" or "guild"; never names the word
        reason = reason,
    }
    while #log > ns.LOG_SIZE do table.remove(log, 1) end
    ns.Changed()
    return reason
end

-- Chat filter: returning true removes the line from that chat window; returning false with
-- changed arguments shows the changed line (preview mode).
-- Arguments after msg and author follow the CHAT_MSG_* payload: arg4 is the channel string,
-- arg9 the channel name, arg11 the line ID, arg12 the GUID.
function ns.ChatFilter(frame, event, msg, author, ...)
    local lineID = select(9, ...)
    local reason
    if type(lineID) == "number" then reason = decided[lineID] end
    if reason == nil then
        local guid = select(10, ...)
        pcall(noteAuthor, author, guid)
        local where = event:gsub("^CHAT_MSG_", ""):lower()
        local channel = select(7, ...)
        if type(channel) == "string" and channel ~= "" then where = channel end

        -- An error here would break chat, so fail open: show the line.
        local ok, r = pcall(judge, event, msg, author, guid, where)
        reason = ok and r or false
        if type(lineID) == "number" then
            decided[lineID] = reason
            decidedOrder[#decidedOrder + 1] = lineID
            if #decidedOrder > MEMORY then decided[table.remove(decidedOrder, 1)] = nil end
        end
    end

    if not reason then return false end
    if ns.db.preview then
        return false, ("|cff888888[RudeBoy: %s]|r %s"):format(reason, tostring(msg)), author, ...
    end
    return true
end

for _, event in ipairs(EVENTS) do
    ChatFrame_AddMessageEventFilter(event, ns.ChatFilter)
end
