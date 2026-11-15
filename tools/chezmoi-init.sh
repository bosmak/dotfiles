#!/usr/bin/env bash
# tools/chezmoi-init.sh — bootstrap script for this dotfiles repo.
#
# Installs the prerequisites the checkout needs, clones the repo, prompts
# for the user info, writes the config, then runs `chezmoi apply`.
#
# Supports Fedora (dnf) and macOS (brew). On macOS, Homebrew is
# installed if missing.
#
# Usage:
#   ./chezmoi-init.sh [GITHUB_USERNAME]
#   curl -fsSL https://raw.githubusercontent.com/bosmak/dotfiles/main/tools/chezmoi-init.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/bosmak/dotfiles/main/tools/chezmoi-init.sh | bash -s -- GITHUB_USERNAME

set -euo pipefail

REPO="${1:-${GITHUB_USERNAME:-bosmak}}"

SOURCE_DIR="${DOTFILES_DIR:-$HOME/.local/share/chezmoi}"
CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# 1. Install the prerequisites the checkout needs (prompts for sudo /
#    Homebrew's password if needed)
NEED=()
for cmd in git curl tar gum; do
    command -v "$cmd" >/dev/null 2>&1 || NEED+=("$cmd")
done
if [ ${#NEED[@]} -gt 0 ]; then
    if [[ ! -r /dev/tty ]] 2>/dev/null; then
        echo "ERROR: prereqs missing and no TTY available." >&2
        echo "Run from an interactive terminal, or install these manually first:" >&2
        if [[ "$OS" == "Linux" ]]; then
            echo "  sudo dnf install -y ${NEED[*]}" >&2
        else
            echo "  brew install ${NEED[*]}" >&2
        fi
        exit 1
    fi
    echo "==> Installing prereqs: ${NEED[*]}"
    "${PKG_INSTALL[@]}" "${NEED[@]}"
fi

# 2. Install chezmoi if missing. This copy is temporary:
#    run_after_60-chezmoi-handover.sh drops it once mise provides one.
if ! command -v chezmoi >/dev/null 2>&1; then
    echo "==> Installing chezmoi (bootstrap copy)"
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

# 4. Prompt for user info (writes ~/.config/chezmoi/chezmoi.toml). The
#    config has to exist before chezmoi starts: it is read once at
#    startup, so a value written later would not reach the templates.
if [ ! -f "$CONFIG" ]; then
    "$SCRIPT_DIR/prompt-config.sh" >/dev/null
fi

# 5. Apply
echo "==> Applying dotfiles"
chezmoi apply --source "$SOURCE_DIR" --force
