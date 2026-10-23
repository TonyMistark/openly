#!/bin/sh
# Sync one release to Gitee: push the tag snapshot, create the release, upload the dmg.
#
# Usage: ./sync-gitee-release.sh <tag> <path-to-dmg>
# Example: ./sync-gitee-release.sh v0.3.0 dist/Openly-0.3.0.dmg
#
# The whole development flow stays on GitHub. This script runs ONCE per
# release, after `gh release create` has finished on GitHub. It:
#   1. pushes the tag (and the commits it points at) as a snapshot —
#      Gitee needs the commit to hang a release on;
#   2. creates the release with the same tag, title and notes as GitHub's;
#   3. uploads the dmg as a release attachment.
#
# Idempotent: an already-pushed tag is reused, an existing release is
# updated in place instead of being created twice.
#
# Auth: Gitee personal access token (projects scope), read from
#   $GITEE_TOKEN, or ~/.config/openly/gitee-token, or ~/.config/wtmd/gitee-token
#   (chmod 600).
# Without a token the script prints manual-upload instructions and exits 0 —
# a missing token must never block the GitHub release.
set -eu

TAG="${1:?usage: sync-gitee-release.sh <tag> <dmg>}"
DMG="${2:?usage: sync-gitee-release.sh <tag> <dmg>}"
OWNER="Micestark"
REPO="Micestark/openly"
API="https://gitee.com/api/v5/repos/$REPO"

TOKEN="${GITEE_TOKEN:-}"
for TOKEN_FILE in "$HOME/.config/openly/gitee-token" "$HOME/.config/wtmd/gitee-token"; do
    if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
        TOKEN="$(tr -d ' \n' < "$TOKEN_FILE")"
    fi
done

if [ -z "$TOKEN" ]; then
    echo "⚠️  No Gitee token — release NOT synced."
    echo "   To sync manually:"
    echo "     1. push the tag:  git push https://gitee.com/$REPO.git refs/tags/$TAG"
    echo "     2. create the release for $TAG at https://gitee.com/$REPO/releases"
    echo "        (title/notes: copy from the GitHub release)"
    echo "     3. upload $DMG as an attachment"
    echo "   To automate next time: create a token (projects scope) and save it to"
    echo "   ~/.config/openly/gitee-token (chmod 600), or export GITEE_TOKEN."
    exit 0
fi

# 1. Tag snapshot. Gitee has no commit to hang a release on until this lands.
echo "→ pushing tag $TAG to Gitee…"
PUSH_LOG="$(mktemp)"
if git push "https://$OWNER:$TOKEN@gitee.com/$REPO.git" "refs/tags/$TAG" > "$PUSH_LOG" 2>&1; then
    echo "  tag pushed"
else
    # "everything up-to-date" / already exists are fine; anything else surfaces
    if git ls-remote "https://$OWNER:$TOKEN@gitee.com/$REPO.git" "refs/tags/$TAG" | grep -q "$TAG"; then
        echo "  tag already on Gitee"
    else
        echo "  ✗ tag push failed:" >&2
        cat "$PUSH_LOG" >&2
        rm -f "$PUSH_LOG"
        exit 1
    fi
fi
rm -f "$PUSH_LOG"

# 2. Release with GitHub's title and notes. If it already exists, reuse it.
echo "→ creating release $TAG on Gitee…"
NAME="$(gh release view "$TAG" --json name --jq .name)"
BODY="$(gh release view "$TAG" --json body --jq .body)"
CREATE_RESPONSE="$(curl -sS -w '\n%{http_code}' -X POST "$API/releases" \
    --data-urlencode "access_token=$TOKEN" \
    --data-urlencode "tag_name=$TAG" \
    --data-urlencode "name=$NAME" \
    --data-urlencode "body=$BODY")"
CREATE_STATUS="$(printf '%s' "$CREATE_RESPONSE" | tail -n1)"
CREATE_BODY="$(printf '%s' "$CREATE_RESPONSE" | sed '$d')"

RELEASE_ID=""
if [ "$CREATE_STATUS" = "201" ]; then
    RELEASE_ID="$(printf '%s' "$CREATE_BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
    echo "  release created"
else
    # Either "already exists" or a real failure — ask the API for the id.
    RELEASE_ID="$(curl -sS "$API/releases/tags/$TAG?access_token=$TOKEN" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')"
    if [ -z "$RELEASE_ID" ]; then
        echo "  ✗ release creation failed (HTTP $CREATE_STATUS):" >&2
        printf '%s\n' "$CREATE_BODY" >&2
        exit 1
    fi
    echo "  release already existed, reusing id $RELEASE_ID"
fi

# 3. Upload the dmg as an attachment. If the same-name attachment already
# exists (a re-run), Gitee rejects it — delete the stale one and retry once.
echo "→ uploading $(basename "$DMG")…"
upload_attachment() {
    curl -sS -X POST "$API/releases/$1/attach_files" \
        -F "access_token=$TOKEN" \
        -F "file=@$2"
}
UPLOAD_RESPONSE="$(upload_attachment "$RELEASE_ID" "$DMG")"
UPLOAD_URL="$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("browser_download_url", ""))' 2>/dev/null || true)"
if [ -z "$UPLOAD_URL" ]; then
    echo "  upload rejected — attempting to replace a stale attachment…"
    OLD_ID="$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' 2>/dev/null || true)"
    if [ -n "$OLD_ID" ]; then
        curl -sS -X DELETE "$API/releases/$RELEASE_ID/attach_files/$OLD_ID" \
            -F "access_token=$TOKEN" > /dev/null
        UPLOAD_RESPONSE="$(upload_attachment "$RELEASE_ID" "$DMG")"
        UPLOAD_URL="$(printf '%s' "$UPLOAD_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("browser_download_url", ""))' 2>/dev/null || true)"
    fi
fi
if [ -z "$UPLOAD_URL" ]; then
    echo "  ✗ attachment upload failed:" >&2
    printf '%s\n' "$UPLOAD_RESPONSE" >&2
    exit 1
fi

echo "✓ Gitee release ready: $UPLOAD_URL"
