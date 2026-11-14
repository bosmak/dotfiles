#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=dot_config/niri/scripts/executable_poe-common.sh
source "$SCRIPT_DIR/poe-common.sh"

focused_json="$(niri msg -j focused-window 2>/dev/null || true)"
app_id="$(printf '%s' "$focused_json" | jq -r '.app_id // empty' 2>/dev/null || true)"
[[ "$app_id" == "$POE_APP_ID" ]] || exit 0

ensure_ydotoold
ydotool key 28:1 28:0
sleep 0.03
ydotool type --key-delay 1 "/hideout"
sleep 0.03
ydotool key 28:1 28:0
