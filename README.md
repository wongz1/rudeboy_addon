# rudeboy_addon

**Rude Boy** is a WoW Forever addon that cleans up your chat. It changes only what *you* see.
It never sends anything to chat, and nobody else can tell you are using it.

- **Words.** If a chat line contains a word or phrase from your list, the whole line is hidden.
- **Players.** Every line from a player on your list is hidden. This list has no size limit, unlike /ignore.
- **Guilds.** Every line from a member of a guild on your list is hidden. Add each guild you want gone.
- **Group warnings.** You get a private warning (raid-warning text, a sound and a red chat line)
  when someone on your player or guild list:
  - invites you to a group. You can have those invites declined for you automatically.
  - is in your party or raid when you join, or joins after you.

Filtering covers say, yell, emotes, whispers, all channels (General, Trade, LookingForGroup, World),
guild, officer, party, raid and battleground chat. Your own lines are never hidden.

## Install

Copy the `RudeBoy` folder into the game's `Interface/AddOns` folder and restart the client.
If it shows as out of date, tick "Load out of date AddOns" (see the note in `RudeBoy/RudeBoy.toc`).

## The window

Type `/rb` to open it (again, or Escape, to close). It has a tab each for **Words**, **Players**
and **Guilds**: type into the box and press Add (or Enter), and each entry has a Remove button.
Players and Guilds also have **Add target**, and Guilds has **Scan** (see below). Checkboxes at
the bottom turn chat hiding, group warnings and invite declining on and off, and `-` / `+` set
the scan reminder. **About** explains what the addon does and why guild lists need regular scans.

The Words tab never shows your words on its own: every entry reads `********` until you press
**Show**, and they are masked again when you reopen the window or switch tabs. Adding or removing
words from the window reports how many, not which.

## Commands

`/rudeboy` or `/rb`

```
/rb                          open or close the window
/rb status                   status and help in chat
/rb on | off                 hide chat lines or not
/rb word add <w1, w2, ...>   filter words or phrases, comma separated
/rb word remove <word>
/rb word list
/rb player add [name]        no name = your current target
/rb player remove <name>
/rb player list
/rb guild add [guild]        no guild = your target's guild
/rb guild remove <guild>
/rb guild list
/rb scan [guild]             /who your filtered guilds so their online members are learned
/rb check                    check your current group now
/rb alerts on | off          group and invite warnings (on by default)
/rb autodecline on | off     decline invites from filtered people (off by default)
/rb reminder <minutes>       how old a scan gets before you're reminded (30 to 720, default 720)
/rb log                      the last 20 hidden lines, with their text
/rb test <text>              would this line be hidden by your word list?
/rb debug                    how the game writes names: yours, your target's, recent senders
```

All lists are shared by every character on the account.

## How words match

Case doesn't matter, and the whole line is hidden if any entry matches.

| Entry | Hides | Does not hide |
| --- | --- | --- |
| `jerk` | jerk, JERK!!, jeeerk, j.e.r.k, j e r k, j3rk | jerky, ajerk |
| `jerk*` | jerk, jerks, jerky | ajerk |
| `*jerk` | jerk, ajerk | jerks |
| `go away` | go away, goaway, go. away | |

Entries match whole words, so a short word doesn't hide every longer word that contains it
(`ass` does not hide "class" or "assassin"). Use `*` when you do want the longer words caught.
Number and symbol stand-ins (`0 1 3 4 5 7 @ $` for `o i e a s t a s`) are handled.
Use `/rb test <text>` to try an entry before you rely on it, and `/rb log` to see what was
hidden in case something harmless got caught.

## How guild filtering works (read this)

Chat messages from the game don't say which guild the sender is in, so the addon can only hide a
guild member it has already seen. It learns guilds from:

- players you target or mouse over, and nameplates
- your party and raid members
- `/who` results, which is what `/rb scan` uses.

After adding guilds, run `/rb scan`. One `/who` shows at most 50 people, so a search that comes
back full is split into one search per class, and a class that is still full is split by level
range. The game only lets an addon run `/who` when you press a key or click, so each `/rb scan` sends
one search. Run it again until it says "Scan finished". A macro on a key makes this one key press
per search. With no guild name it works through every guild on your list; `/rb scan <guild>` does
just that guild. Online members are hidden from then on. What the addon learns is saved and remembered for 30 days after it
last saw each player. A `/who` that shows someone has left the guild clears them.

**Scan reminder.** Each finished scan is timed. At login, and while you play, Rude Boy prints
"Your guild lists are X hours old, run /rb scan" in chat once your last scan is older than your
reminder setting: anything from 30 minutes to 12 hours in 30 minute steps (default 12 hours). It
won't repeat more than once per that interval. It can only remind you; the scan itself needs your
key press or click.

A guild entry can use `*` too: `Streamer*` covers every guild whose name starts with "Streamer".
`/rb scan` skips wildcard entries, since `/who` needs a full guild name.

## Tests

The addon runs outside the game against a mocked WoW API:

```bash
luajit tests/run.lua
```

## Not yet checked in the real client

- The interface number in the `.toc` (copied from CatFacts).
- How WoW Forever writes two-part names in chat, `/who` and invites. The game has been seen writing
  "Cat Facts" (Blizzard's saved data) and "Cat-Facts" (settings folders), so names are compared with
  spaces, hyphens and case ignored, and a server suffix is only dropped when it is this server or
  follows a name that already has a space. "Cat Facts", "Cat-Facts" and "CatFacts" are the same
  player; "Cat" alone is not. Chat senders are also checked by the name the game gives for their
  GUID, in case a line shows them another way. `/rb debug` prints exactly what the game returns.
- The `/who` line format used to learn guilds from chat is the English client's.
