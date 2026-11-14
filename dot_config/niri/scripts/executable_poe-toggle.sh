#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=dot_config/niri/scripts/executable_poe-common.sh
source "$SCRIPT_DIR/poe-common.sh"

TOGGLE_STATE_FILE="$RUNTIME_DIR/game-toggle-state"

win_json="$(poe_window_json)"
[[ -n "$win_json" ]] || exit 0

window_id_value="$(window_id "$win_json")"
geometry="$(poe_output_geometry "$win_json" || true)"
read -r screen_width screen_height <<<"$geometry"
[[ "$screen_width" =~ ^[0-9]+$ && "$screen_height" =~ ^[0-9]+$ ]] || exit 0

wide_height="$(poe_wide_height "$screen_height")"
state=""
if [[ -f "$TOGGLE_STATE_FILE" ]]; then
	state="$(<"$TOGGLE_STATE_FILE")"
fi

if [[ "$state" == "wide" ]]; then
	niri msg action fullscreen-window --id "$window_id_value"
	mkdir -p "$(dirname "$TOGGLE_STATE_FILE")"
	printf '%s\n' "fullscreen" >"$TOGGLE_STATE_FILE"
else
	if [[ "$state" == "fullscreen" ]]; then
		niri msg action fullscreen-window --id "$window_id_value"
	fi
	niri msg action move-window-to-tiling --id "$window_id_value"
	niri msg action set-window-width --id "$window_id_value" "$screen_width"
	niri msg action set-window-height --id "$window_id_value" "$wide_height"
	mkdir -p "$(dirname "$TOGGLE_STATE_FILE")"
	printf '%s\n' "wide" >"$TOGGLE_STATE_FILE"
fi

"$SCRIPT_DIR/game-bar-workspace-watch.sh" >/dev/null 2>&1 &
