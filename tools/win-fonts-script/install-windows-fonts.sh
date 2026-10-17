#!/usr/bin/env bash
#
# install-windows-fonts.sh
#
# Downloads the Windows 11 Enterprise evaluation ISO from Microsoft's
# fwlink, extracts install.wim with 7z, copies every .ttf/.ttc out of
# 1/Windows/Fonts/ into /usr/local/share/fonts/MicrosoftFonts/, and then
# deletes the downloaded ISO + all intermediate files to reclaim ~7 GB.
#
# On-demand script, not idempotent: every run re-downloads the ISO and
# re-installs the fonts from scratch.
#
# WINDOWS_ISO_FWLINK_ID   pin a specific id (skips auto-resolution)
# WINDOWS_EVAL_PAGE        override the page to scrape for the current id
#
# If WINDOWS_ISO_FWLINK_ID is unset, the script scrapes
# $WINDOWS_EVAL_PAGE for the first `go.microsoft.com/fwlink/?linkid=N`
# it finds and uses that. Microsoft rotates the id every 6-12 months when
# they refresh the eval center; the page URL and link shape are stable.

set -euo pipefail

# ---- configuration ---------------------------------------------------------

WINDOWS_EVAL_PAGE="${WINDOWS_EVAL_PAGE:-https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise}"
WINDOWS_ISO_FWLINK_ID="${WINDOWS_ISO_FWLINK_ID:-}"

DEST_DIR="/usr/local/share/fonts/MicrosoftFonts"
FONT_PACKAGES=(fontconfig)

# ---- logging helpers -------------------------------------------------------

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_INFO=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'
else
    C_RESET=""; C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""
fi

# All diagnostic output goes to stderr. Anything that writes to stdout must
# be intentional "data" (e.g. resolve_fwlink_id's id) so that command
# substitution (`id=$(...)`) only captures the intended value.
log()  { printf '%s[%s]%s %s\n' "$C_INFO"  "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
ok()   { printf '%s[%s]%s %s\n' "$C_OK"    "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
warn() { printf '%s[%s]%s %s\n' "$C_WARN"  "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
err()  { printf '%s[%s]%s %s\n' "$C_ERR"   "$(date +%H:%M:%S)" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- fwlink resolution -----------------------------------------------------

resolve_fwlink_id() {
    # The eval-center page lists every localized download variant as an
    # `<a aria-label="Download Windows 11 Enterprise ISO ... (en-US)" ...>`
    # plus a bunch of unrelated fwlink ids in the nav/footer. We match the
    # ISO <a> by its aria-label and pull the linkid out of the same tag.
    # Picking en-US specifically avoids the en-GB/de-DE/fr-FR/etc. duplicates.
    log "Resolving current fwlink id from $WINDOWS_EVAL_PAGE"
    local html id
    if ! html=$(curl --fail --silent --location --max-time 30 "$WINDOWS_EVAL_PAGE"); then
        warn "Failed to fetch $WINDOWS_EVAL_PAGE"
        return 1
    fi
    id=$(printf '%s\n' "$html" \
         | grep -oE 'aria-label="Download Windows 11[^"]*ISO[^"]*\(en-US\)"[^>]*linkid=[0-9]+' \
         | head -n1 \
         | grep -oE '[0-9]+$' || true)
    if [[ -z "$id" ]]; then
        warn "No en-US ISO download link found on $WINDOWS_EVAL_PAGE (page layout may have changed)"
        warn "fwlink ids seen on page:"
        printf '%s\n' "$html" \
            | grep -oE 'linkid=[0-9]+' | sort -u | sed 's/^/  /' >&2
        return 1
    fi
    printf '%s\n' "$id"
}

# ---- preflight -------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "Must run as root (needs dnf, write to /usr/local, restorecon)."

command -v dnf  >/dev/null || die "dnf not found (Fedora/RHEL only)."
command -v 7z   >/dev/null || die "p7zip not found. Install: dnf install p7zip p7zip-plugins."
command -v curl >/dev/null || die "curl not found."

# ---- main ------------------------------------------------------------------

WORK="$(mktemp -d -t windows-fonts.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

log "Working directory: $WORK"

if [[ -z "$WINDOWS_ISO_FWLINK_ID" ]]; then
    if id=$(resolve_fwlink_id); then
        WINDOWS_ISO_FWLINK_ID="$id"
        ok "Resolved fwlink id: $WINDOWS_ISO_FWLINK_ID"
    else
        die "Could not auto-resolve fwlink id. Set WINDOWS_ISO_FWLINK_ID=<digits> and re-run."
    fi
fi
ISO_URL="https://go.microsoft.com/fwlink/?linkid=${WINDOWS_ISO_FWLINK_ID}"
log "ISO URL: $ISO_URL"

log "Installing font packages: ${FONT_PACKAGES[*]}"
dnf install -y "${FONT_PACKAGES[@]}"

install -d -m 0755 "$DEST_DIR"

log "Downloading Windows evaluation ISO (~7 GB, timeout 30 min)"
curl --fail --location \
     --connect-timeout 30 \
     --max-time 1800 \
     --output "${WORK}/windows.iso" \
     "$ISO_URL"

# Sanity-check: a real Windows ISO is several GB. If we got back something
# small, the fwlink redirected to an HTML error page and we'd just be
# feeding 7z garbage. Surface the diagnostic instead.
iso_size=$(stat -c %s "${WORK}/windows.iso")
if (( iso_size < 1073741824 )); then    # < 1 GiB
    warn "Downloaded file is only ${iso_size} bytes — not a real ISO."
    warn "First 500 bytes of what was downloaded:"
    head -c 500 "${WORK}/windows.iso" | sed 's/^/  /' >&2
    die "ISO download looks bogus. The fwlink id may have rotated; set WINDOWS_ISO_FWLINK_ID explicitly."
fi
ok "Downloaded $(numfmt --to=iec --suffix=B "$iso_size")"

log "Extracting install.wim from ISO"
install -d -m 0755 "${WORK}/wim"
7z e -y "${WORK}/windows.iso" sources/install.wim -o"${WORK}/wim"

log "Extracting TrueType fonts from install.wim"
install -d -m 0755 "${WORK}/fonts"
7z e -y "${WORK}/wim/install.wim" \
    '1/Windows/Fonts/*.ttf' \
    '1/Windows/Fonts/*.ttc' \
    -o"${WORK}/fonts"

log "Installing fonts to $DEST_DIR"
cp -a "${WORK}/fonts/." "$DEST_DIR/"
find "$DEST_DIR" -type f -exec chmod 0644 {} +
find "$DEST_DIR" -type d -exec chmod 0755 {} +

if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != "Disabled" ]]; then
    log "Restoring SELinux context on $DEST_DIR"
    restorecon -Fr "$DEST_DIR"
else
    log "SELinux disabled, skipping restorecon"
fi

if command -v fc-cache >/dev/null 2>&1; then
    log "Rebuilding fontconfig cache"
    fc-cache -f "$DEST_DIR" || warn "fc-cache failed; fonts will appear after next login"
fi

ok "Done."