#!/bin/sh
# One-time fix for the WoW Forever beta bug where the client writes addon settings but never
# loads them again (macOS and Linux; Windows players use LinkSavedSettings.cmd). It links the
# game's RudeBoy save file into the addon as Saved.lua, which the client does load.
#
# Run it once, with the game closed, after the addon has saved at least once (log in with it
# enabled, then /exit). It finds the game folder from its own location, so it must be run from
# the installed copy: <World of Warcraft>/_classic_beta_/Interface/AddOns/RudeBoy/
#
#   sh link-saved-settings.sh

set -e
# logical paths, so a symlinked addon folder still finds the game folder above it
ADDON=$(cd "$(dirname "$0")" && pwd)
GAME=$(cd "$ADDON/../../.." && pwd)
[ -d "$GAME/WTF/Account" ] || { echo "Could not find the game's WTF folder above $ADDON. Run this from Interface/AddOns/RudeBoy inside the game folder."; exit 1; }

SAVE=$(find "$GAME/WTF/Account" -maxdepth 3 -path "*/SavedVariables/RudeBoy.lua" -print 2>/dev/null | head -1)
[ -n "$SAVE" ] || { echo "No RudeBoy.lua save found under $GAME/WTF/Account. Log in with the addon enabled, /exit, then run this again."; exit 1; }

ln -sf "$SAVE" "$ADDON/Saved.lua"
echo "Linked $ADDON/Saved.lua -> $SAVE"
echo "Start the game: the login line should say the settings were restored from the linked save file."
