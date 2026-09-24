#!/bin/sh
# Tries the CurseForge upload API four accepted ways with the same zip and metadata, to find
# out why the release workflow gets "Missing field `metadata`". Stops at the first success,
# which is a real upload of the file. Prints CurseForge's replies only, never the token.
#
#   sh tools/cf-upload-test.sh
#
# It zips the RudeBoy folder itself (the same layout as a release, without Saved.lua), and prompts for the API token (from https://authors.curseforge.com/account/api-tokens) and
# optionally the account email for the HTTP basic auth variant.

set -u
cd "$(dirname "$0")/.." || exit 1
version=$(sed -n 's/^## Version: *//p' RudeBoy/RudeBoy.toc | tr -d '\r')
ZIP="/tmp/RudeBoy-v$version-forever.zip"
rm -rf /tmp/rb-build && mkdir -p /tmp/rb-build/RudeBoy && cp RudeBoy/*.lua RudeBoy/*.toc RudeBoy/*.cmd RudeBoy/*.sh LICENSE /tmp/rb-build/RudeBoy/ \
    && rm -f /tmp/rb-build/RudeBoy/Saved.lua && (cd /tmp/rb-build && rm -f "$ZIP" && zip -qr "$ZIP" RudeBoy) || exit 1
echo "built $ZIP"
PROJECT=1709294
URL="https://wow.curseforge.com/api/projects/$PROJECT/upload-file"

printf 'CurseForge API token (not shown): '
stty -echo; read -r TOKEN; stty echo; echo
printf 'Account email, for the basic-auth variant (Enter to skip): '
read -r EMAIL

changelog=$(awk '/^## /{n++} n==1' CHANGELOG.md)
ids=$(curl -sS -H "x-api-token: $TOKEN" https://wow.curseforge.com/api/game/versions \
    | jq -c '[.[] | select(.gameVersionTypeID == 88568 and .name == "1.60.1") | .id]')
echo "version $version, game version ids $ids"
jq -n --arg name "v$version" --argjson ids "$ids" --arg cl "$changelog" \
    '{displayName: $name, gameVersions: $ids, releaseType: "beta", changelog: $cl, changelogType: "markdown"}' > /tmp/rb-meta.json

try() {
    label="$1"; shift
    code=$(curl -sS -w "%{http_code}" -o /tmp/rb-result.json "$@")
    echo "== $label -> HTTP $code"
    head -c 400 /tmp/rb-result.json; echo
    [ "$code" = "200" ]
}

try "1. x-api-token header, metadata as a form value" \
    -H "x-api-token: $TOKEN" -F "metadata=</tmp/rb-meta.json" -F "file=@$ZIP" "$URL" && exit 0
try "2. x-api-token header, metadata as an attached JSON file" \
    -H "x-api-token: $TOKEN" -F "metadata=@/tmp/rb-meta.json;type=application/json" -F "file=@$ZIP" "$URL" && exit 0
try "3. token in the query string" \
    -F "metadata=</tmp/rb-meta.json" -F "file=@$ZIP" "$URL?token=$TOKEN" && exit 0
if [ -n "$EMAIL" ]; then
    try "4. HTTP basic auth (email:token)" \
        -u "$EMAIL:$TOKEN" -F "metadata=</tmp/rb-meta.json" -F "file=@$ZIP" "$URL" && exit 0
fi
echo "All variants failed; paste the replies above (they contain no secrets)."
exit 1
