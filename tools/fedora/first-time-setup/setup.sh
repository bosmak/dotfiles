#!/usr/bin/env bash
#
# setup.sh — first-time setup for a Fedora workstation.
#
# Run manually; chezmoi and ansible never invoke it.

set -euo pipefail

DNF_CONF="${DNF_CONF:-/etc/dnf/dnf.conf}"
PAM_PASSWD="${PAM_PASSWD:-/etc/pam.d/passwd}"

DNF_OPTIONS=(
    "max_parallel_downloads=10"
    "defaultyes=True"
)

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'
else
    C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""
fi

log()  { printf '%s[%s]%s %s\n' "$C_INFO"  "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
ok()   { printf '%s[%s]%s %s\n' "$C_OK"    "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
warn() { printf '%s[%s]%s %s\n' "$C_WARN"  "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
err()  { printf '%s[%s]%s %s\n' "$C_ERR"   "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [-h|--help]

  --dry-run, -n   print the diffs for every change without applying them
  -h, --help      show this help

Steps:
  1. ${DNF_CONF}   — ${DNF_OPTIONS[*]}
  2. ${PAM_PASSWD}   — enable pam_gnome_keyring.so
EOF
}

DRY_RUN=0
SUDO=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            err "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ $EUID -ne 0 ]]; then
    SUDO=(sudo)
fi

AWK_INI=$(cat <<'AWK'
function flush_section(   i, line, key, cmt) {
    for (i = 1; i <= buf_n; i++) {
        line = buf[i]
        key = ""
        if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) {
            key = line
            sub(/^[ \t]*/, "", key)
            sub(/[ \t]*=.*$/, "", key)
        }
        if (key != "" && (key in keyval)) {
            cmt = ""
            if (match(line, /[ \t]+#/)) cmt = substr(line, RSTART)
            print key "=" keyval[key] (cmt != "" ? " " cmt : "")
            done[key] = 1
        } else {
            print line
        }
    }
    buf_n = 0
    for (i = 1; i <= nkeys; i++) {
        k = keylist[i]
        if (!(k in done)) {
            print k "=" keyval[k]
            done[k] = 1
        }
    }
}

BEGIN {
    n = split(pairs, opt, ";")
    for (i = 1; i <= n; i++) {
        if (opt[i] == "") continue
        p = index(opt[i], "=")
        k = substr(opt[i], 1, p - 1)
        v = substr(opt[i], p + 1)
        keylist[++nkeys] = k
        keyval[k] = v
    }
    sect_seen = 0
    in_sect = 0
    buf_n = 0
}

{
    if ($0 ~ /^[ \t]*\[/) {
        if (in_sect) flush_section()
        s = $0
        sub(/^[ \t]*\[/, "", s)
        sub(/\].*$/, "", s)
        if (s == sect) {
            in_sect = 1
            sect_seen = 1
        } else {
            in_sect = 0
        }
        print
        next
    }
    if (in_sect) {
        buf[++buf_n] = $0
        next
    }
    print
}

END {
    if (in_sect) flush_section()
    if (!sect_seen) {
        print ""
        print "[" sect "]"
        for (i = 1; i <= nkeys; i++) {
            k = keylist[i]
            if (!(k in done)) print k "=" keyval[k]
        }
    }
}
AWK
)

ini_set() {
    local file="$1" section="$2"
    shift 2
    local pairs="" kv
    for kv in "$@"; do
        pairs+="${pairs:+;}$kv"
    done
    awk -v sect="$section" -v pairs="$pairs" "$AWK_INI" "$file"
}

backup_file() {
    local target="$1" bak
    bak="${target}.bak-$(date +%Y%m%d%H%M%S)"
    "${SUDO[@]}" cp -a "$target" "$bak"
    log "Backup: $bak"
}

install_file() {
    local target="$1" staged="$2" mode uid gid
    mode="$(stat -c %a "$target")"
    uid="$(stat -c %u "$target")"
    gid="$(stat -c %g "$target")"
    "${SUDO[@]}" install -o "$uid" -g "$gid" -m "$mode" "$staged" "$target"
    if command -v restorecon >/dev/null 2>&1; then
        "${SUDO[@]}" restorecon -F "$target" || warn "restorecon failed for $target"
    fi
}

show_diff() {
    diff -u --label "$1 (current)" --label "$1 (new)" "$1" "$2" >&2 || true
}

step_dnf_conf() {
    log "Step 1/2: dnf configuration ($DNF_CONF)"

    if [[ ! -f "$DNF_CONF" ]]; then
        warn "$DNF_CONF not found — skipping"
        return 0
    fi

    local staged
    staged="$(mktemp)"
    ini_set "$DNF_CONF" "main" "${DNF_OPTIONS[@]}" > "$staged"

    if cmp -s "$DNF_CONF" "$staged"; then
        ok "$DNF_CONF already configured"
        rm -f "$staged"
        return 0
    fi

    show_diff "$DNF_CONF" "$staged"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "Dry run: $DNF_CONF left unchanged"
        rm -f "$staged"
        return 0
    fi

    backup_file "$DNF_CONF"
    install_file "$DNF_CONF" "$staged"
    rm -f "$staged"
    ok "$DNF_CONF updated (${DNF_OPTIONS[*]})"
}

step_pam_passwd() {
    log "Step 2/2: PAM password stack ($PAM_PASSWD)"

    if [[ ! -f "$PAM_PASSWD" ]]; then
        warn "$PAM_PASSWD not found — skipping"
        return 0
    fi

    if ! grep -qE '^-password[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' "$PAM_PASSWD"; then
        if grep -qE '^password[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' "$PAM_PASSWD"; then
            ok "$PAM_PASSWD already configured"
        else
            warn "No pam_gnome_keyring.so line found in $PAM_PASSWD — skipping"
        fi
        return 0
    fi

    local staged
    staged="$(mktemp)"
    # Drop the leading "-" so the keyring module takes part in the stack.
    sed -E 's/^-password([[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so.*)$/password\1/' \
        "$PAM_PASSWD" > "$staged"

    if cmp -s "$PAM_PASSWD" "$staged"; then
        ok "$PAM_PASSWD already configured"
        rm -f "$staged"
        return 0
    fi

    show_diff "$PAM_PASSWD" "$staged"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "Dry run: $PAM_PASSWD left unchanged"
        rm -f "$staged"
        return 0
    fi

    backup_file "$PAM_PASSWD"
    install_file "$PAM_PASSWD" "$staged"
    rm -f "$staged"
    ok "$PAM_PASSWD updated (pam_gnome_keyring.so enabled)"
}

main() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "Fedora first-time setup starting (dry run — nothing will be changed)"
    else
        log "Fedora first-time setup starting"
    fi

    step_dnf_conf
    step_pam_passwd

    ok "Done."
}

main "$@"
