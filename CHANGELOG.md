# Changelog

## 0.1.2

- Hovering a row on the Blocked tab shows the full name and guild.
- The guild invite window is closed after an invite is declined (it stayed open before).
- Release automation: CurseForge upload done directly, with the request shown in the build log.

## 0.1.1

- Guild invites: the guild name is found wherever the client puts it in the event, declining
  falls back to `C_GuildInfo.DeclineGuild`, and the warning says when the client offers no way to
  decline. `/rb debug` shows the last guild invite's raw values.
- `LinkSavedSettings.cmd` for Windows, next to the macOS/Linux script, both inside the addon folder.
- Adding a guild looks its online members up with `/who` at once.
- Release packaging fix so the changelog reaches CurseForge.

## 0.1.0

First release, for WoW Forever.

- Hide whole chat lines that contain your words or phrases. Matches whole words, catches
  stretched letters (`jeeerk`), split letters (`j.e.r.k`) and number stand-ins (`j3rk`), and
  supports `*` wildcards.
- Hide every line from players on your list, with no size limit.
- Hide every line from members of guilds on your list. Members are learned from targets,
  mouseover, nameplates, groups and `/who`; `/rb scan` looks guilds up, splitting big guilds by
  class and level to get past the 50 result limit of `/who`.
- Private warning when a filtered player or guild member invites you or is in your group, or a
  filtered person or guild invites you to a guild. Party and guild invites can each be declined
  automatically.
- Window (`/rb`) with Words, Players, Guilds and Hidden tabs. Words and hidden messages stay
  masked until you press Show.
- Hidden tab listing the last 100 hidden lines, and a preview mode that tags lines instead of
  hiding them.
- Lifetime count of filtered lines.
- Scan reminder, from every 30 minutes to every 12 hours.
- Blocked tab listing everyone being blocked and why, with Exempt to let a person through
  despite their guild being on your list.
- Adding a guild looks its online members up with `/who` straight away.
- Workaround for the WoW Forever beta not loading addon settings: `LinkSavedSettings.cmd`
  (Windows) and `link-saved-settings.sh` (macOS/Linux) in the addon folder link your save file
  into the addon so it is restored at startup.
- Two-part WoW Forever names ("Cat Facts", "Cat-Facts") are matched however the game writes them.
