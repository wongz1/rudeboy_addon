--[[
    Commands.lua - /rudeboy (or /rb)

    /rb                          open the window
    /rb status                   status and help in chat
    /rb on | off                 hide chat lines or not
    /rb word add <w1, w2, ...>   filter words or phrases (comma separated, "*" is a wildcard)
    /rb word remove <word>
    /rb word list
    /rb player add [name]        no name = your target
    /rb player remove <name>
    /rb player list
    /rb guild add [guild]        no guild = your target's guild
    /rb guild remove <guild>
    /rb guild list
    /rb scan [guild]             /who your filtered guilds so their online members are learned;
                                 run it again for each next search (big guilds are split up)
    /rb check                    check your current group now
    /rb alerts on | off          group and invite warnings
    /rb autodecline on | off     decline invites from filtered people
    /rb log                      the last hidden lines, with their text
    /rb test <text>              would this line be hidden?
]]

local ADDON, ns = ...
local P = ns.Print

local HELP = {
    "/rb - open the window,  /rb status - this text",
    "/rb on | off - hide chat lines or not",
    "/rb word add <w1, w2, ...> | remove <word> | list",
    "/rb player add [name] | remove <name> | list   (no name = your target)",
    "/rb guild add [guild] | remove <guild> | list   (no guild = your target's guild)",
    "/rb scan [guild] - /who your guilds to learn who is in them (run again for each next search)",
    "/rb check - check your group now",
    "/rb alerts on | off,  /rb autodecline on | off",
    "/rb log - the last hidden lines,  /rb test <text> - would it be hidden?",
}

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function sortedValues(t)
    local list = {}
    for k, v in pairs(t) do list[#list + 1] = (v == true) and k or v end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

local function onOff(v) return v and "ON" or "OFF" end

local function printStatus()
    local db = ns.db
    P(("v%s. Hiding chat: %s. Group alerts: %s. Auto-decline invites: %s."):format(
        ns.VERSION, onOff(db.enabled), onOff(db.alerts), onOff(db.autoDecline)))
    P(("%d words, %d players, %d guilds filtered. Guilds known for %d players."):format(
        count(db.words), count(db.players), count(db.guilds), count(db.known)))
    P(("hidden %d lines this session, %d in total."):format(ns.hiddenSession, db.hiddenTotal))
    for _, line in ipairs(HELP) do P("  " .. line) end
end

local function printList(title, t)
    local list = sortedValues(t)
    if #list == 0 then
        P(title .. ": none.")
    else
        P(("%s (%d): %s"):format(title, #list, table.concat(list, ", ")))
    end
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

local function wordCmd(action, arg)
    if action == "add" or action == "remove" then
        local done = {}
        for piece in (arg .. ","):gmatch("([^,]*),") do
            if ns.Trim(piece) ~= "" then
                local w, err = (action == "add" and ns.AddWord or ns.RemoveWord)(piece)
                if w then done[#done + 1] = w else P(err) end
            end
        end
        if #done > 0 then
            P((action == "add" and "filtering: " or "no longer filtering: ") .. table.concat(done, ", "))
        elseif ns.Trim(arg) == "" then
            P(("usage: /rb word %s <word or phrase>, <another>"):format(action))
        end
    else
        printList("words", ns.db.words)
    end
end

-- Your target's name and guild, or nil and why not.
function ns.TargetInfo()
    if not (UnitExists("target") and UnitIsPlayer("target")) then return nil, nil, "target a player first." end
    local name, guild = ns.LearnUnit("target")
    return name, guild
end

local function playerCmd(action, arg)
    if action == "add" then
        local name, err = arg, nil
        if name == "" then
            local _
            name, _, err = ns.TargetInfo()
            if not name then P("usage: /rb player add <name>, or " .. err) return end
        end
        local added
        added, err = ns.AddPlayer(name)
        P(added and ("filtering player %s."):format(added) or err)
    elseif action == "remove" then
        local removed, err = ns.RemovePlayer(arg)
        P(removed and ("no longer filtering player %s."):format(removed) or err)
    else
        printList("players", ns.db.players)
    end
end

local function guildCmd(action, arg)
    if action == "add" then
        local guild = arg
        if guild == "" then
            local _, g = ns.TargetInfo()
            if not g then P("usage: /rb guild add <guild name>, or target a player who is in the guild.") return end
            guild = g
        end
        local added, err = ns.AddGuild(guild)
        P(added and ("filtering guild <%s>. Run /rb scan to learn its online members now."):format(added) or err)
    elseif action == "remove" then
        local removed, err = ns.RemoveGuild(arg)
        P(removed and ("no longer filtering guild <%s>."):format(removed) or err)
    else
        printList("guilds", ns.db.guilds)
    end
end

local function toggle(key, value, label)
    if value == "on" or value == "off" then ns.db[key] = (value == "on") ns.Changed() end
    P(("%s: %s."):format(label, onOff(ns.db[key])))
end

local function printLog()
    if #ns.log == 0 then P("nothing hidden this session.") return end
    P("last hidden lines (oldest first):")
    for _, e in ipairs(ns.log) do
        P(("  %s [%s] %s: %s  |cff999999(%s)|r"):format(e.at, e.event:gsub("^CHAT_MSG_", ""):lower(), tostring(e.author), tostring(e.msg), e.reason))
    end
end

---------------------------------------------------------------------------

SLASH_RUDEBOY1 = "/rudeboy"
SLASH_RUDEBOY2 = "/rb"
SlashCmdList["RUDEBOY"] = function(input)
    if not ns.db then P("not loaded yet.") return end
    input = ns.Trim(input)
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local action, arg = rest:match("^(%S*)%s*(.-)$")
    action = action:lower()

    if cmd == "" or cmd == "ui" or cmd == "show" then
        ns.ToggleUI()
    elseif cmd == "status" or cmd == "help" then
        printStatus()
    elseif cmd == "on" or cmd == "off" then
        toggle("enabled", cmd, "hiding chat")
    elseif cmd == "word" or cmd == "words" then
        wordCmd(action, arg)
    elseif cmd == "player" or cmd == "players" then
        playerCmd(action, arg)
    elseif cmd == "guild" or cmd == "guilds" then
        guildCmd(action, arg)
    elseif cmd == "scan" then
        ns.Scan(rest)
    elseif cmd == "check" then
        ns.CheckGroup(true)
    elseif cmd == "alerts" then
        toggle("alerts", action, "group alerts")
    elseif cmd == "autodecline" then
        toggle("autoDecline", action, "auto-decline invites")
    elseif cmd == "log" then
        printLog()
    elseif cmd == "test" then
        local why = ns.MatchWord(rest)
        P(why and ("would be hidden (word \"%s\")."):format(why) or "would be shown.")
    else
        P("unknown command. Type /rb for help.")
    end
end
