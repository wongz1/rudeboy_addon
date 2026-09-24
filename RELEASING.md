# Releasing Rude Boy

## Every release

1. Test in game. At minimum: `/rb` opens the window, a filtered word disappears from chat (or
   gets tagged with preview on), and `/rb debug` shows sensible names.
2. Set the new version in both places, e.g. `0.2.0`:
   - `RudeBoy/RudeBoy.toc`: `## Version: 0.2.0`
   - `RudeBoy/Core.lua`: `ns.VERSION = "0.2.0"`

   (`luajit tests/run.lua` fails if they differ.)
3. Add a `## 0.2.0` section at the top of `CHANGELOG.md`. It becomes the release notes.
4. Commit and push, then tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

The Release workflow then runs the tests, checks the tag matches the `.toc` version, builds
`RudeBoy-v0.2.0.zip` (only the `RudeBoy` folder, see `.pkgmeta`) and publishes it to GitHub
Releases, plus every site set up below. Watch it under the repo's Actions tab.

## First upload by hand (no automation needed)

1. Build the zip: `git tag v0.1.0 && git push origin v0.1.0` builds and attaches it to a GitHub
   Release, or zip the `RudeBoy` folder yourself (only the addon files and LICENSE, no
   `Saved.lua`, `tests` or docs), with `RudeBoy/` as the zip's top-level folder.
2. Sign in at https://authors.curseforge.com with a CurseForge (Overwolf) account.
3. **Start a project** > World of Warcraft > Addon. Fill in: name "Rude Boy", summary and
   description from "Project page text" below, category **Chat & Communication**, license **MIT**,
   and a screenshot or two of the window and a hidden line in chat.
4. Submit the project for approval. New projects are reviewed by CurseForge staff, usually within
   a day or two.
5. **Upload file**: choose the zip, set the release type (Beta is honest for a first version on a
   beta client), pick the game version (see "Game version" below), and paste the version's
   changelog section. Uploaded files are scanned and usually appear within a few hours.
6. Once the project page exists, copy its **Project ID** (shown on the project's overview page)
   into `RudeBoy/RudeBoy.toc` as `## X-Curse-Project-ID: <id>` so later releases can upload
   automatically.

## One-time setup

### Allow workflow files to be pushed

The GitHub CLI login needs the `workflow` permission to push `.github/workflows`:

```bash
gh auth refresh -h github.com -s workflow
```

### CurseForge

1. Create the project at https://authors.curseforge.com (category: Chat & Communication, license:
   MIT). Use the text under "Project page text" below.
2. Add its project ID to `RudeBoy/RudeBoy.toc`: `## X-Curse-Project-ID: 123456`
3. Create an API token at https://authors.curseforge.com/account/api-tokens and save it as the
   repository secret `CF_API_KEY` (GitHub: Settings > Secrets and variables > Actions).

### Wago Addons

1. Create the project at https://addons.wago.io/developers.
2. Add its ID to the `.toc`: `## X-Wago-ID: abcd1234`
3. Create an API token in your Wago account and save it as the secret `WAGO_API_TOKEN`.

### WoWInterface (optional)

1. Upload the first version by hand at https://www.wowinterface.com to get an addon ID.
2. Add it to the `.toc`: `## X-WoWI-ID: 12345`
3. Save an API token from your WoWInterface account as the secret `WOWI_API_TOKEN`.

### Game version

The sites tag each upload with a game version worked out from `## Interface:`. `16001` is WoW
Forever's number (confirm with `/run print((select(4, GetBuildInfo())))`). If a site doesn't list
WoW Forever yet, its upload may be rejected or land under Classic; check the first upload's game
version on each site and say in the description that the addon is for WoW Forever.

## Project page text

**Summary:** Hide toxic chat by word, player or guild, and get a private warning when those
people are in or invite you to your group.

**Description:**

Rude Boy cleans up your chat in WoW Forever. It only changes what you see: it never sends anything
to chat, and nobody can tell you use it.

- **Words**: any line containing a word or phrase on your list is removed completely. Catches
  stretched letters, letters split by dots or spaces, and number stand-ins.
- **Players**: hide everything from a player, with no size limit (unlike /ignore).
- **Guilds**: hide everything from a guild's members, for whole communities you want gone.
- **Group warnings**: a private alert when someone on your lists invites you or is in your group,
  so you can leave first. Invites from them can be declined automatically.
- **Hidden tab**: see what was removed and why, with the text masked until you choose to look.
- **Lifetime counter** of lines filtered.

Type `/rb` to open the window. Your word list stays masked until you press Show.

Guild filtering note: chat doesn't say which guild a player is in, so Rude Boy learns guild members
as it sees them (targets, nameplates, groups) and from `/who` scans (the Scan button). Scan now and
then to catch members who were offline; the addon reminds you.
