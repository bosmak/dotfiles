#!/usr/bin/env bash
# tools/chezmoi-init.sh — bootstrap script for this dotfiles repo.
#
# Installs all prereqs, clones the repo, prompts for user info, writes
# the config, then runs `chezmoi apply`. The apply uses the existing
# config (no second run needed) and the .chezmoiscripts/ run ansible
# with --ask-become-pass to prompt for sudo.
#
# Usage:
#   ./chezmoi-init.sh GITHUB_USERNAME
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/GITHUB_USERNAME/dotfiles/main/tools/chezmoi-init.sh)" -- GITHUB_USERNAME

set -euo pipefail

REPO="${1:-${GITHUB_USERNAME:-}}"
if [ -z "$REPO" ]; then
    echo "Usage: $0 GITHUB_USERNAME" >&2
    exit 1
fi

SOURCE_DIR="${DOTFILES_DIR:-$HOME/.local/share/chezmoi}"
CONFIG="$HOME/.config/chezmoi/chezmoi.toml"

# 1. Install prereqs (prompts for sudo if needed)
NEED=()
for cmd in git curl jq unzip; do
    command -v "$cmd" >/dev/null 2>&1 || NEED+=("$cmd")
done
NEED_DNF=()
# Map package name to the binary it provides. For packages whose binary
# name matches the package name (gum, mise), no mapping is needed.
declare -A PKG_BIN=(
    [ansible-core]=ansible-playbook
)
for pkg in gum ansible-core mise; do
    bin="${PKG_BIN[$pkg]:-$pkg}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        NEED_DNF+=("$pkg")
    fi
done
if [ ${#NEED[@]} -gt 0 ] || [ ${#NEED_DNF[@]} -gt 0 ]; then
    if [[ ! -r /dev/tty ]] 2>/dev/null; then
        echo "ERROR: prereqs missing and no TTY available to prompt for sudo." >&2
        echo "Run from an interactive terminal, or install these manually first:" >&2
        echo "  sudo dnf install -y ${NEED[*]} ${NEED_DNF[*]}" >&2
        exit 1
    fi
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        NEED_DNF+=(ansible-core)
    fi
    echo "==> Installing prereqs: ${NEED[*]} ${NEED_DNF[*]}"
    sudo dnf install -y "${NEED[@]}" "${NEED_DNF[@]}"
fi

# 2. Install chezmoi if missing
if ! command -v chezmoi >/dev/null 2>&1; then
    echo "==> Installing chezmoi"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://get.chezmoi.io | sh -s -- -b "$HOME/.local/bin"
fi
export PATH="$HOME/.local/bin:$PATH"

# 3. Clone the dotfiles repo
if [ ! -d "$SOURCE_DIR/.git" ]; then
    echo "==> Cloning dotfiles from $REPO"
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "https://github.com/$REPO/dotfiles" "$SOURCE_DIR"
fi

# 4. Prompt for user info (writes ~/.config/chezmoi/chezmoi.toml)
if [ ! -f "$CONFIG" ]; then
    if [[ ! -r /dev/tty ]] 2>/dev/null; then
        echo "ERROR: no TTY; cannot prompt. Create $CONFIG manually with:" >&2
        echo '  [data]' >&2
        echo '  role = "personal"' >&2
        echo '  machineName = "your-hostname"' >&2
        echo '  email = "you@example.com"' >&2
        echo '  name = "Your Name"' >&2
        exit 1
    fi
    echo
    echo "==> User config"
    mkdir -p "$(dirname "$CONFIG")"
    if command -v gum >/dev/null 2>&1; then
        role=$(gum choose --header "What role is this machine?" personal work)
        email=$(gum input --placeholder "Email")
        name=$(gum input --placeholder "Name")
    else
        echo "What role is this machine?"
        echo "  1) personal"
        echo "  2) work"
        role=""
        while [ -z "$role" ]; do
            read -r -p "Choice [1/2]: " choice < /dev/tty
            case "$choice" in
                1|personal) role="personal" ;;
                2|work) role="work" ;;
                *) echo "Please enter 1 or 2." ;;
            esac
        done
        read -r -p "Email: " email < /dev/tty
        read -r -p "Name: " name < /dev/tty
    fi
    hostname_val="$(hostname 2>/dev/null || echo 'localhost')"
    cat > "$CONFIG" <<EOF
[edit]
  command = "nvim"

[git]
  autoCommit = false
  autoPush = false

[data]
  role        = "$role"
  machineName = "$hostname_val"
  email       = "$email"
  name        = "$name"
EOF
    echo "Wrote $CONFIG"
fi

# 5. Apply (templates have the config now, scripts run with --ask-become-pass)
echo "==> Applying dotfiles"
chezmoi apply --source "$SOURCE_DIR" --force
