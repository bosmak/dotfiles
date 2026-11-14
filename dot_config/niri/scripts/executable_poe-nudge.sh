#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=dot_config/niri/scripts/executable_poe-common.sh
source "$SCRIPT_DIR/poe-common.sh"

mode="${1:-step}"
direction="${2:-up}"

win_json="$(poe_window_json)"
[[ -n "$win_json" ]] || exit 0
[[ "$(window_is_floating "$win_json")" == "true" ]] || exit 0

window_id_value="$(window_id "$win_json")"
geometry="$(poe_output_geometry "$win_json" || true)"
read -r _screen_width screen_height <<<"$geometry"
[[ "$screen_height" =~ ^[0-9]+$ ]] || exit 0

if [[ "$mode" == "pixel" ]]; then
	amount=1
else
	amount=$((screen_height / 36))
	[[ "$amount" -ge 1 ]] || amount=1
fi

case "$direction" in
up) delta="-$amount" ;;
down) delta="+$amount" ;;
*) exit 0 ;;
esac

niri msg action move-floating-window --id "$window_id_value" --y "$delta"
