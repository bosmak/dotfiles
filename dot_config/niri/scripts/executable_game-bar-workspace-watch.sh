#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=dot_config/niri/scripts/executable_game-common.sh
source "$SCRIPT_DIR/game-common.sh"

DMS_BAR_ID="default"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
BAR_STATE_FILE="$RUNTIME_DIR/game-bar-workspace-state"
RELEASE_PENDING_FILE="$RUNTIME_DIR/game-release-pending"
LOCK_DIR="$RUNTIME_DIR/game-bar-workspace-watch.lock"
PID_FILE="$LOCK_DIR/pid"
TOGGLE_STATE_FILE="$RUNTIME_DIR/game-toggle-state"
RELEASE_DELAY=3
POLL_INTERVAL=1
cleaned=0

bar_status() {
	command -v dms >/dev/null 2>&1 || return 1
	dms ipc call bar status id "$DMS_BAR_ID" 2>/dev/null
}

save_bar_state() {
	[[ -f "$BAR_STATE_FILE" ]] && return 0

	local status
	status="$(bar_status || true)"
	case "$status" in
	visible | hidden) ;;
	*) status="visible" ;;
	esac

	mkdir -p "$(dirname "$BAR_STATE_FILE")"
	printf '%s\n' "$status" >"$BAR_STATE_FILE"
}

restore_bar_state() {
	[[ -f "$BAR_STATE_FILE" ]] || return 0

	local visible
	visible="$(<"$BAR_STATE_FILE")"
	case "$visible" in
	visible)
		command -v dms >/dev/null 2>&1 || return 1
		dms ipc call bar reveal id "$DMS_BAR_ID" >/dev/null 2>&1 || return 1
		;;
	hidden)
		command -v dms >/dev/null 2>&1 || return 1
		dms ipc call bar hide id "$DMS_BAR_ID" >/dev/null 2>&1 || return 1
		;;
	*)
		rm -f "$BAR_STATE_FILE"
		return 0
		;;
	esac

	rm -f "$BAR_STATE_FILE"
}

hide_bar() {
	[[ -f "$BAR_STATE_FILE" ]] || save_bar_state
	command -v dms >/dev/null 2>&1 || return 0
	dms ipc call bar hide id "$DMS_BAR_ID" >/dev/null 2>&1 || true
}

show_bar() {
	[[ -f "$BAR_STATE_FILE" ]] || return 0
	restore_bar_state || true
}

schedule_release() {
	[[ -f "$RELEASE_PENDING_FILE" ]] && return 0
	date +%s >"$RELEASE_PENDING_FILE"
	debug_log "schedule_release: timer armed"
}

cancel_release() {
	if [[ -f "$RELEASE_PENDING_FILE" ]]; then
		debug_log "cancel_release: timer disarmed"
		rm -f "$RELEASE_PENDING_FILE"
	fi
}

maybe_release() {
	[[ -f "$RELEASE_PENDING_FILE" ]] || return 0

	local scheduled now
	scheduled="$(<"$RELEASE_PENDING_FILE")"
	now="$(date +%s)"
	[[ "$((now - scheduled))" -ge "$RELEASE_DELAY" ]] || return 0

	debug_log "maybe_release: firing (scheduled=$scheduled now=$now delay=${RELEASE_DELAY}s)"
	release_game_workspace
	clear_game_workspace_config
	rm -f "$RELEASE_PENDING_FILE"
	rm -f "$TOGGLE_STATE_FILE"
}

cleanup() {
	if [[ "$cleaned" -eq 1 ]]; then
		return
	fi
	cleaned=1

	show_bar
	cancel_release
	release_game_workspace
	clear_game_workspace_config
	rm -f "$TOGGLE_STATE_FILE"
	rm -f "$PID_FILE"
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock() {
	if mkdir "$LOCK_DIR" 2>/dev/null; then
		printf '%s\n' "$$" >"$PID_FILE"
		return 0
	fi

	if [[ -f "$PID_FILE" ]]; then
		local pid
		pid="$(<"$PID_FILE")"
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			return 1
		fi
	fi

	rm -rf "$LOCK_DIR"
	mkdir "$LOCK_DIR" 2>/dev/null || return 1
	printf '%s\n' "$$" >"$PID_FILE"
}

reconcile() {
	local steam_count

	steam_count="$(steam_windows_count)"
	debug_log "reconcile: steam_count=$steam_count"

	if [[ "$steam_count" -gt 0 ]]; then
		cancel_release
		apply_game_workspace_config
		manage_steam_workspace

		if game_workspace_is_focused; then
			hide_bar
		else
			show_bar
		fi
	else
		show_bar
		schedule_release
		maybe_release
	fi
}

mkdir -p "$RUNTIME_DIR"
acquire_lock || exit 0

# Recover a bar state left behind if the previous watcher was interrupted.
restore_bar_state || true
rm -f "$RELEASE_PENDING_FILE"

trap cleanup EXIT
trap 'exit 0' INT TERM HUP

reconcile

while niri msg version >/dev/null 2>&1; do
	sleep "$POLL_INTERVAL"
	niri msg version >/dev/null 2>&1 || break
	reconcile
done
