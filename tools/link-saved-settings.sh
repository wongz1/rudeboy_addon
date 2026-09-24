#!/bin/sh
# One-time fix for the WoW Forever beta bug where the client writes addon settings but never
# loads them again (macOS and Linux). It links the game's RudeBoy save file into the addon as
# Saved.lua, which the client does load. Run it once, with the game closed, after the addon has
# saved at least once (log out or /exit with it enabled).
#
#   usage: tools/link-saved-settings.sh ["/path/to/World of Warcraft/_classic_beta_"]
#
# Windows: use ForeverSVFix or SVShim instead (see the README), or make the link with
#   mklink "Interface\AddOns\RudeBoy\Saved.lua" "WTF\Account\<account>\SavedVariables\RudeBoy.lua"

set -e
GAME="${1:-/Applications/World of Warcraft/_classic_beta_}"
ADDON="$GAME/Interface/AddOns/RudeBoy"
[ -d "$ADDON" ] || { echo "RudeBoy is not installed in $GAME/Interface/AddOns"; exit 1; }

SAVES=$(ls -d "$GAME"/WTF/Account/*/SavedVariables/RudeBoy.lua 2>/dev/null || true)
[ -n "$SAVES" ] || { echo "No RudeBoy.lua save found under $GAME/WTF/Account/*/SavedVariables. Log in with the addon enabled, /exit, then run this again."; exit 1; }
if [ "$(printf '%s\n' "$SAVES" | wc -l)" -gt 1 ]; then
    echo "More than one account has a RudeBoy save; linking the newest:"
    printf '%s\n' "$SAVES"
fi
SAVE=$(ls -t $SAVES | head -1)

ln -sf "$SAVE" "$ADDON/Saved.lua"
echo "Linked $ADDON/Saved.lua -> $SAVE"
echo "Start the game: the login line should say the settings were restored from the linked save file."
