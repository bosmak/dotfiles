#!/usr/bin/env bash
# tools/chezmoi-init.sh — bootstrap script for this dotfiles repo.
#
# Installs the few prerequisites the checkout needs, clones the repo and
# applies it. The apply-time scripts in .chezmoiscripts/ install the
# remaining prereqs, prompt for the user info and run the ansible
# playbook.
#
# Supports Fedora (dnf) and macOS (brew). On macOS, Homebrew is
# installed if missing.
#
# Usage:
#   ./chezmoi-init.sh [GITHUB_USERNAME]
#   curl -fsSL https://bsmk.xyz/dotfiles | bash
#   curl -fsSL https://bsmk.xyz/dotfiles | bash -s -- GITHUB_USERNAME

set -euo pipefail

REPO="${1:-${GITHUB_USERNAME:-bosmak}}"

SOURCE_DIR="${DOTFILES_DIR:-$HOME/.local/share/chezmoi}"

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
#    Homebrew's password if needed). tar is here because the chezmoi
#    installer unpacks a tarball.
NEED=()
for cmd in git curl tar; do
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

# 2. Install chezmoi if missing. This is only a bootstrap: mise owns the
#    chezmoi version (dot_config/mise/config.toml), and
#    run_after_60-chezmoi-handover.sh drops this binary once mise has one.
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
CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
if [ ! -f "$CONFIG" ]; then
    if [[ ! -r /dev/tty ]] 2>/dev/null; then
        echo "ERROR: no TTY; cannot prompt. Create $CONFIG manually with:" >&2
        echo '  [edit]' >&2
        echo '  command = "vim"' >&2
        echo '  [data]' >&2
        echo '  role = "personal"' >&2
        echo '  email = "you@example.com"' >&2
        echo '  name = "Your Name"' >&2
        echo '  playbook = "default"   # or "none"' >&2
        exit 1
    fi
    echo
    echo "==> User config"
    mkdir -p "$(dirname "$CONFIG")"
    if command -v gum >/dev/null 2>&1; then
        editor=$(gum input --header "Default editor" --value "vim")
        role=$(gum choose --header "What role is this machine?" personal work)
        email=$(gum input --header "Email")
        name=$(gum input --header "Name")
        # Discover the available playbooks and let the user pick one or
        # "none". The name carries no system or profile: those are
        # resolved at run time from the OS and the role.
        PLAYBOOK_DIR="$SOURCE_DIR/ansible/playbooks"
        if [[ -d "$PLAYBOOK_DIR" ]]; then
            mapfile -t PLAYBOOKS < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -printf '%f\0' | sort -z | xargs -0 -n1 basename -s .yml)
            PLAYBOOKS+=("none")
            playbook=$(gum choose --header "Which ansible playbook should run on apply? (none = skip ansible)" "${PLAYBOOKS[@]}")
        else
            playbook="none"
        fi
    else
        echo "Default editor"
        read -r -p "Editor command [vim]: " editor < /dev/tty
        editor="${editor:-vim}"
        echo
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
        echo "Email"
        read -r -p "Email: " email < /dev/tty
        echo "Name"
        read -r -p "Name: " name < /dev/tty

        echo
        echo "==> Which ansible playbook should run on apply?"
        PLAYBOOK_DIR="$SOURCE_DIR/ansible/playbooks"
        playbook="default"
        if [[ -d "$PLAYBOOK_DIR" ]]; then
            mapfile -t PLAYBOOKS < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -printf '%f\0' | sort -z | xargs -0 -n1 basename -s .yml)
            PLAYBOOKS+=("none")
            i=1
            for pb in "${PLAYBOOKS[@]}"; do
                echo "  $i) $pb"
                i=$((i+1))
            done
            default_index=$i
            echo "  $default_index) none (skip ansible)"
            while true; do
                read -r -p "Choice [1-$default_index]: " choice < /dev/tty
                case "$choice" in
                    "" ) playbook="${PLAYBOOKS[0]}"; break ;;
                    * )
                        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= default_index )); then
                            if (( choice == default_index )); then
                                playbook="none"
                            else
                                playbook="${PLAYBOOKS[$((choice-1))]}"
                            fi
                            break
                        fi
                        echo "Please enter a number between 1 and $default_index." ;;
                esac
            done
        else
            playbook="none"
        fi
    fi
    cat > "$CONFIG" <<EOF
[edit]
  command = "$editor"

[git]
  autoCommit = false
  autoPush = false

[data]
  role        = "$role"
  email       = "$email"
  name        = "$name"
  playbook    = "$playbook"
EOF
    echo "Wrote $CONFIG"
fi

# 5. Apply. `chezmoi init` renders .chezmoi.toml.tmpl first, so the
#    answers are in place before the templates run.
echo "==> Applying dotfiles"
chezmoi init --source "$SOURCE_DIR" --apply
