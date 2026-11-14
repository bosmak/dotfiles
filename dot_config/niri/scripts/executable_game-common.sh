#!/usr/bin/env bash

TARGET_WORKSPACE="game"
GAME_OUTPUT_NAME="DP-2"
GAME_WORKSPACE_FILE="$HOME/.config/niri/game-workspace.kdl"
DEBUG_LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/game-watch.log"

debug_log() {
	[[ -n "${GAME_DEBUG:-}" ]] || return 0
	mkdir -p "$(dirname "$DEBUG_LOG_FILE")"
	printf '%s %s\n' "$(date +%H:%M:%S.%3N)" "$*" >>"$DEBUG_LOG_FILE"
}

window_id() {
	printf '%s' "$1" | jq -r '.id // empty'
}

window_is_floating() {
	printf '%s' "$1" | jq -r '.is_floating // false'
}

window_workspace_id() {
	printf '%s' "$1" | jq -r '.workspace_id // empty'
}

steam_windows_json() {
	local windows

	windows="$(niri msg -j windows 2>/dev/null || true)"
	if [[ -z "$windows" ]]; then
		printf '[]\n'
		return 0
	fi

	if ! printf '%s' "$windows" | jq -c '[
		.[] | select(
			((.app_id // "") | startswith("steam_app_")) or
			((.app_id // "") == "Tabletop Simulator.x86_64")
		)
	]'; then
		printf '[]\n'
	fi
}

steam_windows_count() {
	local steam_json count

	steam_json="$(steam_windows_json)"
	count="$(printf '%s' "$steam_json" | jq -r 'length' 2>/dev/null || printf '0')"
	[[ "$count" =~ ^[0-9]+$ ]] || count=0
	printf '%s\n' "$count"
}

manage_steam_workspace() {
	local steam_json count attempts game_ws_id window_json wid wsid

	steam_json="$(steam_windows_json)"
	count="$(printf '%s' "$steam_json" | jq -r 'length')"
	[[ "$count" -gt 0 ]] || return 0

	attempts=0
	game_ws_id="$(game_workspace_id || true)"
	while [[ -z "$game_ws_id" && "$attempts" -lt 40 ]]; do
		attempts=$((attempts + 1))
		sleep 0.05
		game_ws_id="$(game_workspace_id || true)"
	done
	[[ -n "$game_ws_id" ]] || return 0

	debug_log "manage_steam_workspace: game_ws_id=$game_ws_id count=$count"

	niri msg action move-workspace-to-monitor \
		--reference "$TARGET_WORKSPACE" "$GAME_OUTPUT_NAME" >/dev/null 2>&1 || true

	while IFS= read -r window_json; do
		[[ -n "$window_json" ]] || continue
		wid="$(printf '%s' "$window_json" | jq -r '.id')"
		wsid="$(printf '%s' "$window_json" | jq -r '.workspace_id')"
		if [[ "$wsid" != "$game_ws_id" ]]; then
			debug_log "manage_steam_workspace: moving window wid=$wid wsid=$wsid to $TARGET_WORKSPACE"
			niri msg action move-window-to-workspace \
				--window-id "$wid" --focus=false "$TARGET_WORKSPACE" >/dev/null 2>&1 || true
		fi
	done < <(printf '%s' "$steam_json" | jq -c '.[]')
}

window_output_name() {
	local workspace_id

	workspace_id="$(window_workspace_id "$1")"
	[[ -n "$workspace_id" ]] || return 1

	niri msg -j workspaces |
		jq -r --argjson workspace_id "$workspace_id" \
			'.[] | select(.id == $workspace_id) | .output // empty' |
		head -n1
}

window_output_geometry() {
	local output_name

	output_name="$(window_output_name "$1")"
	[[ -n "$output_name" ]] || return 1

	niri msg -j outputs |
		jq -r --arg output_name "$output_name" \
			'.[] | select(.name == $output_name) | [.logical.width, .logical.height] | @tsv' |
		head -n1
}

focused_workspace_id() {
	niri msg -j workspaces | jq -r '.[] | select(.is_focused == true) | .id // empty' | head -n1
}

game_workspace_id() {
	niri msg -j workspaces |
		jq -r --arg target "$TARGET_WORKSPACE" \
			'.[] | select(.name == $target) | .id // empty' |
		head -n1
}

game_workspace_is_focused() {
	local game_id focused_id

	game_id="$(game_workspace_id || true)"
	focused_id="$(focused_workspace_id || true)"
	[[ -n "$game_id" && "$game_id" == "$focused_id" ]]
}

apply_game_workspace_config() {
	local cache_dir tmp_file

	cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
	mkdir -p "$cache_dir" "$(dirname "$GAME_WORKSPACE_FILE")"
	tmp_file="$(mktemp "$cache_dir/game-workspace.XXXXXX")"

	{
		printf '%s\n' '// Auto-generated — present while a Steam game runs.'
		printf 'workspace "%s" {\n' "$TARGET_WORKSPACE"
		printf '    open-on-output "%s"\n' "$GAME_OUTPUT_NAME"
		printf '%s\n' '    layout {' '        gaps 0' '    }' '}'
		printf '%s\n' \
			'' \
			'// Route later game windows directly; the watcher moves the first window here.' \
			'window-rule {' \
			'    match app-id=r#"^steam_app_"#' \
			'    match app-id=r#"^Tabletop Simulator\.x86_64$"#' \
			'    open-on-workspace "game"' \
			'}'
	} >"$tmp_file"

	if [[ -f "$GAME_WORKSPACE_FILE" ]] && cmp -s "$tmp_file" "$GAME_WORKSPACE_FILE"; then
		rm -f "$tmp_file"
		return 0
	fi

	chmod 0644 "$tmp_file"
	mv -f "$tmp_file" "$GAME_WORKSPACE_FILE"
}

clear_game_workspace_config() {
	rm -f "$GAME_WORKSPACE_FILE"
}

release_game_workspace() {
	if [[ -n "$(game_workspace_id || true)" ]]; then
		niri msg action unset-workspace-name "$TARGET_WORKSPACE" >/dev/null 2>&1 || true
	fi
}
