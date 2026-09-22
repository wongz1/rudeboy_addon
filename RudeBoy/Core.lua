--[[
    Core.lua - saved settings, the three filter lists, and the guild cache.

    RudeBoyDB (account wide, so every character shares the same lists):
        enabled      hide chat lines (true/false)
        alerts       warn about filtered people in your group or inviting you
        autoDecline  decline group invites from filtered people
        words        { [entry] = true }                 words and phrases, see ns.CompileWord
        players      { [normalized name] = "Shown Name" }
        guilds       { [normalized guild] = "Shown Guild" }
        known        { [normalized name] = { g = "Guild", t = time seen } }

    Chat messages don't say which guild the sender is in, so guilds are learned whenever the
    game shows them: your target, mouseover, nameplates, group members and /who results.
    A guild filter can only hide someone the addon has seen at least once.
]]

local ADDON, ns = ...
ns.VERSION = "0.1.0"

local PREFIX = "|cffff5555RudeBoy|r: "
local KNOWN_DAYS = 30        -- forget a player's guild after this many days unseen

function ns.Print(msg)
    print(PREFIX .. tostring(msg))
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- "Bob Builder-Stormrage", "bob builder" and "BobBuilder" are all "bobbuilder".
function ns.NormalizeName(name)
    if type(name) ~= "string" then return "" end
    name = name:gsub("%-.*$", "")
    return (name:lower():gsub("%s+", ""))
end

function ns.NormalizeGuild(guild)
    if type(guild) ~= "string" then return "" end
    return (guild:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
ns.Trim = trim

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

-- Turns a user entry into a Lua pattern that is matched against lower case chat text.
--   * whole words only: "ass" hides "ass" and "ass!" but not "class" or "assassin"
--   * stretched letters: "fuuuuck" matches "fuck"
--   * letters split by spaces or punctuation: "f.u.c.k" and "f u c k" match "fuck"
--   * a "*" is a wildcard: "idiot*" also hides "idiots", "*hole" hides "pothole" too
--   * a phrase is matched with or without its spaces: "go away" also hides "goaway"
function ns.CompileWord(entry)
    entry = trim(entry):lower()
    local startWild = entry:find("^%*") ~= nil
    local endWild = entry:find("%*$") ~= nil
    local core = entry:gsub("^%*+", ""):gsub("%*+$", ""):gsub("%s+", "")
    if not core:find("[^%*]") then return nil end

    local parts = {}
    for c in core:gmatch(".") do
        if c == "*" then
            parts[#parts + 1] = "%w*"
        elseif c:find("%w") then
            parts[#parts + 1] = c .. "+"
        else
            parts[#parts + 1] = "%" .. c .. "+"
        end
    end
    return (startWild and "" or "%f[%w]") .. table.concat(parts, "[%s%p]*") .. (endWild and "" or "%f[%W]")
end

-- Stand-ins people use to dodge filters. Only used to match, never shown.
local LEET = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s" }

-- Color codes, textures and link wrappers removed, so "[Some Item]" is matched as its text.
function ns.PlainText(msg)
    local s = tostring(msg or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", "")
    return s:lower()
end

local compiled   -- { { entry = , pattern = } } rebuilt when the word list changes

function ns.RebuildWords()
    compiled = {}
    for entry in pairs(ns.db.words) do
        local pattern = ns.CompileWord(entry)
        if pattern then compiled[#compiled + 1] = { entry = entry, pattern = pattern } end
    end
    table.sort(compiled, function(a, b) return a.entry < b.entry end)
end

-- Returns the entry that matched, or nil.
function ns.MatchWord(msg)
    if not compiled or #compiled == 0 then return nil end
    local plain = ns.PlainText(msg)
    local leet = plain:gsub("[013457@%$]", LEET)
    for _, w in ipairs(compiled) do
        if plain:find(w.pattern) or leet:find(w.pattern) then return w.entry end
    end
    return nil
end

---------------------------------------------------------------------------
-- Players and guilds
---------------------------------------------------------------------------

-- A list key may hold "*" wildcards: "toxic*" matches every guild that starts with "toxic".
local function wildcardMatch(list, key)
    if key == "" then return nil end
    if list[key] then return list[key] end
    for k, shown in pairs(list) do
        if k:find("*", 1, true) then
            local pattern = "^" .. k:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
            if key:find(pattern) then return shown end
        end
    end
    return nil
end

function ns.IsPlayerFiltered(name)
    return wildcardMatch(ns.db.players, ns.NormalizeName(name))
end

function ns.IsGuildFiltered(guild)
    return wildcardMatch(ns.db.guilds, ns.NormalizeGuild(guild))
end

-- Records that `name` is in `guild`. An empty string means "in no guild" (known from /who).
-- nil is ignored: the game also returns nil when it hasn't loaded someone's guild yet.
function ns.RememberGuild(name, guild)
    local key = ns.NormalizeName(name)
    if key == "" or guild == nil or not ns.db then return end
    ns.db.known[key] = { g = guild, t = time() }
end

function ns.GuildOf(name)
    local entry = ns.db and ns.db.known[ns.NormalizeName(name)]
    if entry and entry.g ~= "" then return entry.g end
    return nil
end

-- Why a person should be avoided, or nil. `guild` may be passed when already known.
function ns.PersonReason(name, guild)
    local p = ns.IsPlayerFiltered(name)
    if p then return "player on your list" end
    guild = guild or ns.GuildOf(name)
    local g = guild and ns.IsGuildFiltered(guild)
    if g then return ("guild <%s>"):format(guild) end
    return nil
end

-- Why a chat line should be hidden, or nil.
function ns.LineReason(msg, author)
    local why = ns.PersonReason(author)
    if why then return why end
    local word = ns.MatchWord(msg)
    if word then return ("word \"%s\""):format(word) end
    return nil
end

---------------------------------------------------------------------------
-- Editing the lists, shared by the slash commands and the window. Each returns the entry as
-- stored on success, or nil and a reason.
---------------------------------------------------------------------------

-- Lets the window redraw when a list changes from anywhere.
function ns.Changed()
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.AddWord(entry)
    local w = trim(entry):lower():gsub("%s+", " ")
    if w == "" then return nil, "type a word first." end
    if not ns.CompileWord(w) then return nil, ("\"%s\" has no letters to match."):format(w) end
    ns.db.words[w] = true
    ns.RebuildWords()
    ns.Changed()
    return w
end

function ns.RemoveWord(entry)
    local w = trim(entry):lower():gsub("%s+", " ")
    if not ns.db.words[w] then return nil, "not on your word list: " .. w end
    ns.db.words[w] = nil
    ns.RebuildWords()
    ns.Changed()
    return w
end

function ns.AddPlayer(name)
    name = trim(name)
    local key = ns.NormalizeName(name)
    if key == "" then return nil, "type a player name first." end
    ns.db.players[key] = name
    ns.Changed()
    return name
end

function ns.RemovePlayer(name)
    local key = ns.NormalizeName(name)
    local shown = ns.db.players[key]
    if not shown then return nil, "not on your player list: " .. trim(name) end
    ns.db.players[key] = nil
    ns.Changed()
    return shown
end

function ns.AddGuild(guild)
    guild = trim(guild)
    local key = ns.NormalizeGuild(guild)
    if key == "" then return nil, "type a guild name first." end
    ns.db.guilds[key] = guild
    ns.Changed()
    return guild
end

function ns.RemoveGuild(guild)
    local key = ns.NormalizeGuild(guild)
    local shown = ns.db.guilds[key]
    if not shown then return nil, "not on your guild list: " .. trim(guild) end
    ns.db.guilds[key] = nil
    ns.Changed()
    return shown
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------

function ns.LoadDB()
    RudeBoyDB = RudeBoyDB or {}
    local db = RudeBoyDB
    if db.enabled == nil then db.enabled = true end
    if db.alerts == nil then db.alerts = true end
    if db.autoDecline == nil then db.autoDecline = false end
    db.words = db.words or {}
    db.players = db.players or {}
    db.guilds = db.guilds or {}
    db.known = db.known or {}
    db.hiddenTotal = db.hiddenTotal or 0

    local cutoff = time() - KNOWN_DAYS * 86400
    for k, v in pairs(db.known) do
        if type(v) ~= "table" or (v.t or 0) < cutoff then db.known[k] = nil end
    end

    ns.db = db
    ns.RebuildWords()
end
