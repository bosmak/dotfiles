#!/usr/bin/env bash
# Prompts for the user info and writes ~/.config/chezmoi/chezmoi.toml.
# The config is printed on stdout so callers can use it as the config
# file; everything else goes to stderr.

set -euo pipefail

CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_DIR="$SCRIPT_DIR/../ansible/playbooks"

if [ -f "$CONFIG" ]; then
    cat "$CONFIG"
    exit 0
fi

if [[ ! -r /dev/tty ]] 2>/dev/null; then
    echo "ERROR: no TTY; cannot prompt. Create $CONFIG manually with:" >&2
    echo '  [edit]' >&2
    echo '  command = "vim"' >&2
    echo '  [data]' >&2
    echo '  role = "personal"' >&2
    echo '  email = "you@example.com"' >&2
    echo '  name = "Your Name"' >&2
    echo '  playbook = "default"   # or "none", or a basename from ansible/playbooks/' >&2
    exit 1
fi

mkdir -p "$(dirname "$CONFIG")"

# The prompt runs before the apply that installs the prereqs, so gum has to
# be installed here. A failed install just means the plain prompts below.
if ! command -v gum >/dev/null 2>&1; then
    case "$(uname -s)" in
        Darwin) brew install gum >&2 || true ;;
        Linux) sudo dnf install -y gum >&2 || true ;;
    esac
fi

if command -v gum >/dev/null 2>&1; then
    editor=$(gum input --header "Default editor" --value "vim")
    role=$(gum choose --header "What role is this machine?" personal work)
    email=$(gum input --placeholder "Email")
    name=$(gum input --placeholder "Name")
    # Discover available ansible playbooks and let the user pick one or
    # "none". The name carries no system or profile: those are resolved
    # at run time from the OS and the role.
    if [[ -d "$PLAYBOOK_DIR" ]]; then
        # mapfile null-delimited, strip .yml, append "none"
        mapfile -t PLAYBOOKS < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -printf '%f\0' | sort -z | xargs -0 -n1 basename -s .yml)
        PLAYBOOKS+=("none")
        playbook=$(gum choose --header "Which ansible playbook should run on apply? (none = skip ansible)" "${PLAYBOOKS[@]}")
    else
        playbook="none"
    fi
else
    echo >&2
    echo "==> Which editor should chezmoi and git use?" >&2
    read -r -p "Editor command [vim]: " editor < /dev/tty
    editor="${editor:-vim}"
    echo >&2
    echo "==> What role is this machine?" >&2
    echo "  1) personal" >&2
    echo "  2) work" >&2
    role=""
    while [ -z "$role" ]; do
        read -r -p "Choice [1/2]: " choice < /dev/tty
        case "$choice" in
            1|personal) role="personal" ;;
            2|work) role="work" ;;
            *) echo "Please enter 1 or 2." >&2 ;;
        esac
    done
    read -r -p "Email: " email < /dev/tty
    read -r -p "Name: " name < /dev/tty

    echo >&2
    echo "==> Which ansible playbook should run on apply?" >&2
    playbook=""
    if [[ -d "$PLAYBOOK_DIR" ]]; then
        mapfile -t PLAYBOOKS < <(find "$PLAYBOOK_DIR" -maxdepth 1 -type f -name '*.yml' -printf '%f\0' | sort -z | xargs -0 -n1 basename -s .yml)
        i=1
        for pb in "${PLAYBOOKS[@]}"; do
            echo "  $i) $pb" >&2
            i=$((i+1))
        done
        none_index=$i
        echo "  $none_index) none (skip ansible)" >&2
        echo "    (press enter to keep current / auto-detect)" >&2
        while true; do
            read -r -p "Choice [0-$none_index]: " choice < /dev/tty
            case "$choice" in
                "" ) playbook=""; break ;;
                0|none) playbook="none"; break ;;
                *)
                    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= none_index )); then
                        if (( choice == none_index )); then
                            playbook="none"
                        else
                            playbook="${PLAYBOOKS[$((choice-1))]}"
                        fi
                        break
                    fi
                    echo "Please enter a number between 0 and $none_index, or press enter to skip." >&2 ;;
            esac
        done
    else
        echo "  (no ansible/playbooks/ found; defaulting to none)" >&2
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
EOF

# If the user picked a playbook (or explicitly chose "none"), persist it.
# An empty playbook means auto-detect from role+OS.
if [[ -n "${playbook:-}" ]]; then
    # Insert/replace the playbook line in-place.
    if grep -q '^playbook *=' "$CONFIG"; then
        sed -i "s|^playbook *=.*|playbook = \"$playbook\"|" "$CONFIG"
    else
        printf '\nplaybook = "%s"\n' "$playbook" >> "$CONFIG"
    fi
fi

echo "Wrote $CONFIG" >&2
cat "$CONFIG"
