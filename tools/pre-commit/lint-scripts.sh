#!/usr/bin/env bash
#
# Lint shell sources in this chezmoi repo.
#
# Usage: lint-scripts.sh <bash|zsh> <file>...
#
# chezmoi templates (*.tmpl) are rendered with `chezmoi execute-template`
# before being checked, so a template is linted as the shell code it
# actually produces. Each checked copy is written to a temporary tree that
# mirrors the repository layout, so diagnostics point at the real paths.
#
# bash -> shellcheck, zsh -> `zsh -f -n` (shellcheck does not understand zsh).

set -euo pipefail

usage() {
    echo "usage: ${0##*/} <bash|zsh> <file>..." >&2
    exit 2
}

[[ $# -ge 2 ]] || usage

lang="$1"
shift

case "$lang" in
    bash)
        checker=$(command -v shellcheck || true)
        if [[ -z "$checker" ]] && command -v mise >/dev/null 2>&1; then
            checker=$(mise where shellcheck 2>/dev/null || true)
        fi
        if [[ -z "$checker" ]]; then
            echo "shellcheck not found: run 'mise install shellcheck' or install the shellcheck package" >&2
            exit 2
        fi
        ;;
    zsh)
        checker=$(command -v zsh || true)
        if [[ -z "$checker" ]]; then
            echo "zsh not found: install the zsh package" >&2
            exit 2
        fi
        ;;
    *)
        usage
        ;;
esac

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

status=0

for file in "$@"; do
    [[ -f "$file" ]] || continue

    rel="${file#"$PWD"/}"
    target="$tmpdir/$rel"
    mkdir -p "$(dirname "$target")"

    # chezmoi only renders files whose source name ends in .tmpl, so those
    # are rendered before being checked. Everything else is checked as is.
    if [[ "$file" == *.tmpl ]]; then
        if ! command -v chezmoi >/dev/null 2>&1; then
            echo "chezmoi not found: cannot render $file" >&2
            status=2
            continue
        fi
        if ! chezmoi execute-template <"$file" >"$target"; then
            echo "chezmoi failed to render $file" >&2
            status=2
            continue
        fi
    else
        cp "$file" "$target"
    fi

    rc=0
    output=$(
        case "$lang" in
            bash) "$checker" -s bash "$target" ;;
            zsh) "$checker" -f -n "$target" ;;
        esac 2>&1
    ) || rc=$?

    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" | sed "s|$tmpdir/||g"
    fi

    if ((rc != 0)) && ((status == 0)); then
        status=1
    fi
done

exit "$status"
