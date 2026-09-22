--[[
    Commands.lua - /rudeboy (or /rb)

    /rb                          status and help
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
    local words = ns.db.words
    if action == "add" or action == "remove" then
        local done, refused = {}, false
        for piece in (arg .. ","):gmatch("([^,]*),") do
            local w = ns.Trim(piece):lower():gsub("%s+", " ")
            if w ~= "" then
                if action == "add" then
                    if ns.CompileWord(w) then
                        words[w] = true
                        done[#done + 1] = w
                    else
                        P(("\"%s\" has no letters to match."):format(w))
                        refused = true
                    end
                elseif words[w] then
                    words[w] = nil
                    done[#done + 1] = w
                end
            end
        end
        ns.RebuildWords()
        if #done == 0 then
            if refused then return end
            P(action == "add" and "usage: /rb word add <word or phrase>, <another>" or "not on your word list: " .. arg)
        else
            P((action == "add" and "filtering: " or "no longer filtering: ") .. table.concat(done, ", "))
        end
    else
        printList("words", words)
    end
end

local function playerCmd(action, arg)
    local players = ns.db.players
    if action == "add" then
        local name = arg
        if name == "" then
            if not (UnitExists("target") and UnitIsPlayer("target")) then
                P("usage: /rb player add <name>, or target a player first.")
                return
            end
            name = ns.LearnUnit("target")
        end
        players[ns.NormalizeName(name)] = name
        P(("filtering player %s."):format(name))
    elseif action == "remove" then
        local key = ns.NormalizeName(arg)
        if players[key] then
            P(("no longer filtering player %s."):format(players[key]))
            players[key] = nil
        else
            P("not on your player list: " .. arg)
        end
    else
        printList("players", players)
    end
end

local function guildCmd(action, arg)
    local guilds = ns.db.guilds
    if action == "add" then
        local guild = arg
        if guild == "" then
            local _, g = ns.LearnUnit("target")
            if not g then
                P("usage: /rb guild add <guild name>, or target a player who is in the guild.")
                return
            end
            guild = g
        end
        guilds[ns.NormalizeGuild(guild)] = guild
        P(("filtering guild <%s>. Run /rb scan to learn its online members now."):format(guild))
    elseif action == "remove" then
        local key = ns.NormalizeGuild(arg)
        if guilds[key] then
            P(("no longer filtering guild <%s>."):format(guilds[key]))
            guilds[key] = nil
        else
            P("not on your guild list: " .. arg)
        end
    else
        printList("guilds", guilds)
    end
end

local function toggle(key, value, label)
    if value == "on" or value == "off" then ns.db[key] = (value == "on") end
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

    if cmd == "" then
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
