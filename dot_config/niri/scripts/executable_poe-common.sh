#!/usr/bin/env bash

POE_COMMON_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dot_config/niri/scripts/executable_game-common.sh
source "$POE_COMMON_DIR/game-common.sh"

POE_APP_ID="steam_app_238960"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

poe_window_json() {
	local focused_json focused_app_id windows

	focused_json="$(niri msg -j focused-window 2>/dev/null || true)"
	focused_app_id="$(printf '%s' "$focused_json" | jq -r '.app_id // empty' 2>/dev/null || true)"

	if [[ "$focused_app_id" == "$POE_APP_ID" ]]; then
		printf '%s\n' "$focused_json"
		return 0
	fi

	windows="$(niri msg -j windows 2>/dev/null || true)"
	[[ -n "$windows" ]] || return 0
	printf '%s' "$windows" |
		jq -c --arg app_id "$POE_APP_ID" '[.[] | select(.app_id == $app_id)][0] // empty'
}

poe_wide_height() {
	local screen_height="$1"
	printf '%s\n' "$((screen_height * 75 / 100))"
}

poe_output_name() {
	window_output_name "$1"
}

poe_output_geometry() {
	window_output_geometry "$1"
}

ensure_ydotoold() {
	local socket attempts

	command -v ydotool >/dev/null 2>&1 || {
		echo "ydotool is required for the PoE /hideout shortcut" >&2
		return 1
	}
	command -v ydotoold >/dev/null 2>&1 || {
		echo "ydotoold is required for the PoE /hideout shortcut" >&2
		return 1
	}

	socket="${YDOTOOL_SOCKET:-$RUNTIME_DIR/.ydotool_socket}"
	export YDOTOOL_SOCKET="$socket"

	if ydotool debug >/dev/null 2>&1; then
		return 0
	fi

	rm -f "$socket"
	if command -v nohup >/dev/null 2>&1; then
		nohup ydotoold --socket-path "$socket" >/dev/null 2>&1 &
	else
		ydotoold --socket-path "$socket" >/dev/null 2>&1 &
	fi

	attempts=0
	while [[ "$attempts" -lt 40 ]]; do
		attempts=$((attempts + 1))
		if ydotool debug >/dev/null 2>&1; then
			return 0
		fi
		sleep 0.05
	done

	echo "Failed to start ydotoold" >&2
	return 1
}
