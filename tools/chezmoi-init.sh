#!/usr/bin/env bash
# tools/chezmoi-init.sh — bootstrap script for this dotfiles repo.
#
# Installs all prereqs, clones the repo, prompts for user info, writes
# the config, then runs `chezmoi apply`.
#
# Supports Fedora (dnf) and macOS (brew). On macOS, Homebrew is
# installed if missing.
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

# 0. Detect OS and pick a package manager. On macOS, install Homebrew
#    if it's not already on PATH or at the default prefix locations.
OS="$(uname -s)"
case "$OS" in
    Linux)
        PKG_INSTALL=(sudo dnf install -y)
        ;;
    Darwin)
        BREW_BIN=""
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [[ -x "$candidate" ]]; then
                BREW_BIN="$candidate"
                break
            fi
        done
        if [[ -z "$BREW_BIN" ]] && command -v brew >/dev/null 2>&1; then
            BREW_BIN="$(command -v brew)"
        fi
        if [[ -z "$BREW_BIN" ]]; then
            if [[ ! -r /dev/tty ]] 2>/dev/null; then
                echo "ERROR: Homebrew not installed and no TTY to run the installer." >&2
                echo "Install it manually from https://brew.sh, then re-run this script." >&2
                exit 1
            fi
            echo "==> Installing Homebrew"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
                if [[ -x "$candidate" ]]; then
                    BREW_BIN="$candidate"
                    break
                fi
            done
        fi
        if [[ -z "$BREW_BIN" ]]; then
            echo "ERROR: Homebrew install did not produce a brew binary at the expected paths." >&2
            exit 1
        fi
        # Make brew available in this shell.
        eval "$("$BREW_BIN" shellenv)"
        PKG_INSTALL=(brew install)
        ;;
    *)
        echo "ERROR: unsupported OS: $OS (only Linux and macOS are supported)" >&2
        exit 1
        ;;
esac

# 1. Install prereqs (prompts for sudo / Homebrew's password if needed)
NEED=()
for cmd in git curl jq unzip; do
    command -v "$cmd" >/dev/null 2>&1 || NEED+=("$cmd")
done
NEED_PKG=()
# Map package name to the binary it provides. For packages whose binary
# name matches the package name (gum, mise), no mapping is needed.
declare -A PKG_BIN=(
    [ansible-core]=ansible-playbook
)
for pkg in gum ansible-core mise; do
    bin="${PKG_BIN[$pkg]:-$pkg}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        NEED_PKG+=("$pkg")
    fi
done
if [ ${#NEED[@]} -gt 0 ] || [ ${#NEED_PKG[@]} -gt 0 ]; then
    if [[ ! -r /dev/tty ]] 2>/dev/null; then
        echo "ERROR: prereqs missing and no TTY available." >&2
        echo "Run from an interactive terminal, or install these manually first:" >&2
        if [[ "$OS" == "Linux" ]]; then
            echo "  sudo dnf install -y ${NEED[*]} ${NEED_PKG[*]}" >&2
        else
            echo "  brew install ${NEED[*]} ${NEED_PKG[*]}" >&2
        fi
        exit 1
    fi
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        NEED_PKG+=(ansible-core)
    fi
    echo "==> Installing prereqs: ${NEED[*]} ${NEED_PKG[*]}"
    "${PKG_INSTALL[@]}" "${NEED[@]}" "${NEED_PKG[@]}"
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
        echo '  playbook = "none"   # or a basename from ansible/playbooks/' >&2
        exit 1
    fi
    echo
    echo "==> User config"
    mkdir -p "$(dirname "$CONFIG")"
    if command -v gum >/dev/null 2>&1; then
        role=$(gum choose --header "What role is this machine?" personal work)
        email=$(gum input --placeholder "Email")
        name=$(gum input --placeholder "Name")
        # Discover available ansible playbooks (basenames without .yml) and let
        # the user pick one or "none". Defaults to "none" when the playbook
        # tree is absent.
        PLAYBOOK_DIR="$SOURCE_DIR/ansible/playbooks"
        if [[ -d "$PLAYBOOK_DIR" ]]; then
            mapfile -t PLAYBOOKS < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -printf '%f\0' | sort -z | xargs -0 -n1 basename -s .yml)
            PLAYBOOKS=(none "${PLAYBOOKS[@]}")
            playbook=$(gum choose --header "Which ansible playbook should run on apply? (none = skip ansible)" "${PLAYBOOKS[@]}")
        else
            playbook="none"
        fi
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

        echo
        echo "==> Which ansible playbook should run on apply?"
        PLAYBOOK_DIR="$SOURCE_DIR/ansible/playbooks"
        playbook=""
        if [[ -d "$PLAYBOOK_DIR" ]]; then
            mapfile -t PLAYBOOKS < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -printf '%f\0' | sort -z | xargs -0 -n1 basename -s .yml)
            echo "  0) none (skip ansible)"
            i=1
            for pb in "${PLAYBOOKS[@]}"; do
                echo "  $i) $pb"
                i=$((i+1))
            done
            echo "    (press enter to keep current / auto-detect from role)"
            while true; do
                read -r -p "Choice [0-$((i-1))]: " choice < /dev/tty
                case "$choice" in
                    "" ) playbook=""; break ;;
                    0|none) playbook="none"; break ;;
                    *)
                        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < i )); then
                            playbook="${PLAYBOOKS[$((choice-1))]}"
                            break
                        fi
                        echo "Please enter a number between 0 and $((i-1)), or press enter to skip." ;;
                esac
            done
        else
            echo "  (no ansible/playbooks/ found; defaulting to none)"
            playbook="none"
        fi
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

    # Persist playbook choice (or "none"). Empty means auto-detect.
    if [[ -n "${playbook:-}" ]]; then
        if grep -q '^playbook *=' "$CONFIG"; then
            sed -i "s|^playbook *=.*|playbook = \"$playbook\"|" "$CONFIG"
        else
            printf '\nplaybook = "%s"\n' "$playbook" >> "$CONFIG"
        fi
    fi
    echo "Wrote $CONFIG"
fi

# 5. Apply
echo "==> Applying dotfiles"
chezmoi apply --source "$SOURCE_DIR" --force
