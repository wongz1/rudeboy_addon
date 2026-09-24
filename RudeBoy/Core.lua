--[[
    Core.lua - saved settings, the three filter lists, and the guild cache.

    RudeBoyDB (account wide, so every character shares the same lists):
        enabled      hide chat lines (true/false)
        alerts       warn about filtered people in your group or inviting you
        autoDecline  decline party invites from filtered people
        declineGuild decline guild invites from filtered people or filtered guilds
        words        { [entry] = true }                 words and phrases, see ns.CompileWord
        players      { [normalized name] = "Shown Name" }
        guilds       { [normalized guild] = "Shown Guild" }
        known        { [normalized name] = { g = "Guild", t = time seen, n = "Shown Name" } }
        exempt       { [normalized name] = "Shown Name" }   let through despite player/guild lists
        hiddenTotal  lifetime count of hidden lines; hiddenByKind splits it by word/player/guild
        countingSince  the date the lifetime count started
        lastScan     time() the last /rb scan finished
        reminderMinutes  remind to scan when lastScan is older than this (30 to 720)
        log          the last 100 hidden lines, oldest first (the window's Hidden tab)
        preview      show would-be-hidden lines with a tag instead of hiding them
        keywords     { [normalized word] = "Shown Word" }   block every guild whose name contains it
        recentAuthors  the last few chat senders as the game wrote them (/rb debug)

    Chat messages don't say which guild the sender is in, so guilds are learned whenever the
    game shows them: your target, mouseover, nameplates, group members and /who results.
    A guild filter can only hide someone the addon has seen at least once.
]]

local ADDON, ns = ...
ns.VERSION = "0.1.3"

-- True when Saved.lua (see the .toc) has already put the last save in place. The client's own
-- loading, when it works, happens later, at ADDON_LOADED.
ns.restoredFromLink = RudeBoyDB ~= nil

local PREFIX = "|cffff5555RudeBoy|r: "
local KNOWN_DAYS = 30        -- forget a player's guild after this many days unseen

function ns.Print(msg)
    print(PREFIX .. tostring(msg))
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- WoW Forever characters have a first and a last name, and the game has been seen writing
-- them both as "Cat Facts" (UnitName) and as "Cat-Facts" (the settings folder). A hyphen can
-- also start a server suffix, "Cat Facts-Server". So the suffix is only dropped when it is
-- this server's name, or when the part before it already has a space; then spaces, hyphens
-- and apostrophes are removed. All of these are "catfacts":
--     Cat Facts   Cat-Facts   CatFacts   cat facts   Cat Facts-Server   Cat-Facts-<this server>
local function squash(s)
    return (s:lower():gsub("[%s%-']", ""))
end

local function realmKey()
    local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName())
    return type(r) == "string" and r ~= "" and squash(r) or nil
end

function ns.NormalizeName(name)
    if type(name) ~= "string" then return "" end
    name = trim(name)
    local base, suffix = name:match("^(.+)%-([^%-]+)$")
    if base and (base:find("%s") or squash(suffix) == realmKey()) then name = base end
    return squash(name)
end

-- Every name a chat sender may go by: the name on the line, and the name the game gives for
-- their GUID, in case the two are written differently.
function ns.NamesFor(author, guid)
    local names = { author }
    if type(guid) == "string" and guid ~= "" and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
        -- On WoW Forever this gives the first name only ("Deew" for "Deew Acidni"), which is
        -- less complete than the line's own name and must not be matched on its own.
        if ok and type(name) == "string" and name ~= "" and (name:find("%s") or not tostring(author):find("%s")) then
            names[#names + 1] = name
            if type(realm) == "string" and realm ~= "" then names[#names + 1] = name .. "-" .. realm end
        end
    end
    return names
end

-- The full name of a unit. WoW Forever's UnitName gives the first name, with the last name
-- as a second value where standard clients put the server; a second value that isn't this
-- server is taken as the last name. The name the game gives for the unit's GUID is used
-- when it is the more complete one.
function ns.UnitFullName(unit)
    local name, second = UnitName(unit)
    if type(name) ~= "string" or name == "" then return nil end
    if type(second) == "string" and second ~= "" and not name:find("%s") and squash(second) ~= realmKey() then
        name = name .. " " .. second
    end
    if UnitGUID and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, byGuid = pcall(GetPlayerInfoByGUID, UnitGUID(unit) or "")
        if ok and type(byGuid) == "string" and byGuid:find("%s") and not name:find("%s") then name = byGuid end
    end
    return name
end

function ns.NormalizeGuild(guild)
    if type(guild) ~= "string" then return "" end
    return (guild:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
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

-- Guild keywords block every guild whose name contains the word, for a streamer's many guilds.
-- "Olympus" is the one behind the checkbox in the window.
ns.OLYMPUS = "Olympus"

function ns.IsGuildFiltered(guild)
    local key = ns.NormalizeGuild(guild)
    if key == "" then return nil end
    for k, shown in pairs(ns.db.keywords) do
        if key:find(k, 1, true) then return ("guilds containing \"%s\""):format(shown) end
    end
    return wildcardMatch(ns.db.guilds, key)
end

function ns.AddKeyword(word)
    word = trim(word)
    local key = ns.NormalizeGuild(word)
    if key == "" then return nil, "type a word first." end
    ns.db.keywords[key] = word
    ns.Changed()
    return word
end

function ns.RemoveKeyword(word)
    local key = ns.NormalizeGuild(word)
    local shown = ns.db.keywords[key]
    if not shown then return nil, "not a guild keyword: " .. trim(word) end
    ns.db.keywords[key] = nil
    ns.Changed()
    return shown
end

-- Records that `name` is in `guild`. An empty string means "in no guild" (known from /who).
-- nil is ignored: the game also returns nil when it hasn't loaded someone's guild yet.
function ns.RememberGuild(name, guild)
    local key = ns.NormalizeName(name)
    if key == "" or guild == nil or not ns.db then return end
    ns.db.known[key] = { g = guild, t = time(), n = trim(name) }
    ns.Changed()   -- the Blocked tab lists members of listed guilds
end

-- Exemptions: people let through even though they, or their guild, are on your lists.
-- Words still apply to what they say.
function ns.IsExempt(name)
    return ns.db.exempt[ns.NormalizeName(name)]
end

function ns.Exempt(name)
    name = trim(name)
    local key = ns.NormalizeName(name)
    if key == "" then return nil, "type a player name first." end
    ns.db.exempt[key] = name
    ns.Changed()
    return name
end

function ns.Unexempt(name)
    local key = ns.NormalizeName(name)
    local shown = ns.db.exempt[key]
    if not shown then return nil, "not exempt: " .. trim(name) end
    ns.db.exempt[key] = nil
    ns.Changed()
    return shown
end

function ns.GuildOf(name)
    local entry = ns.db and ns.db.known[ns.NormalizeName(name)]
    if entry and entry.g ~= "" then return entry.g end
    return nil
end

-- Why a person should be avoided, or nil. `guild` may be passed when already known, and
-- `guid` lets the name the game gives for it be checked too.
function ns.PersonReason(name, guild, guid)
    local names = ns.NamesFor(name, guid)
    for _, n in ipairs(names) do
        if ns.IsExempt(n) then return nil end
    end
    for _, n in ipairs(names) do
        if ns.IsPlayerFiltered(n) then return "player on your list" end
    end
    if not guild then
        for _, n in ipairs(names) do
            guild = ns.GuildOf(n)
            if guild then break end
        end
    end
    local g = guild and ns.IsGuildFiltered(guild)
    if g then return ("guild <%s>"):format(guild) end
    return nil
end

-- Why a chat line should be hidden, or nil.
function ns.LineReason(msg, author, guid)
    local why = ns.PersonReason(author, nil, guid)
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
    if db.declineGuild == nil then db.declineGuild = false end
    db.words = db.words or {}
    db.players = db.players or {}
    db.guilds = db.guilds or {}
    db.known = db.known or {}
    db.hiddenTotal = db.hiddenTotal or 0
    db.hiddenByKind = db.hiddenByKind or {}
    for _, kind in ipairs({ "word", "player", "guild" }) do db.hiddenByKind[kind] = db.hiddenByKind[kind] or 0 end
    db.countingSince = db.countingSince or (date and date("%Y-%m-%d")) or ""
    db.reminderMinutes = db.reminderMinutes or 720
    db.log = db.log or {}
    db.exempt = db.exempt or {}
    if db.preview == nil then db.preview = false end
    db.keywords = db.keywords or {}
    if db.olympus then db.keywords[ns.NormalizeGuild(ns.OLYMPUS)] = ns.OLYMPUS end   -- older setting
    db.olympus = nil

    local cutoff = time() - KNOWN_DAYS * 86400
    for k, v in pairs(db.known) do
        if type(v) ~= "table" or (v.t or 0) < cutoff then db.known[k] = nil end
    end

    ns.db = db
    ns.RebuildWords()
end

-- If the game hands the saved table over after the addon has already started fresh, the global
-- RudeBoyDB stops being the table the addon works on. This adopts the saved one and carries the
-- fresh session's lists and counts into it, so nothing done since login is lost.
function ns.AdoptLateDB()
    local fresh, saved = ns.db, RudeBoyDB
    if not fresh or not saved or saved == fresh then return false end
    ns.LoadDB()   -- fills in any missing defaults on the saved table, and points ns.db at it
    local db = ns.db
    for _, list in ipairs({ "words", "players", "guilds", "exempt", "known" }) do
        for k, v in pairs(fresh[list] or {}) do db[list][k] = v end
    end
    for _, e in ipairs(fresh.log or {}) do db.log[#db.log + 1] = e end
    db.hiddenTotal = db.hiddenTotal + (fresh.hiddenTotal or 0)
    for kind, n in pairs(fresh.hiddenByKind or {}) do db.hiddenByKind[kind] = (db.hiddenByKind[kind] or 0) + n end
    ns.RebuildWords()
    ns.Changed()
    return true
end
