# AGENTS.md

Guidance for AI coding agents working on this repository. **Humans read
[README.md](README.md) instead** — that file documents how to use the
dotfiles; this one documents how to change them.

For chezmoi mechanics (templates, `chezmoiignore`, `run_onchange`,
CLI flags), see the official docs: <https://www.chezmoi.io/docs/>.

## What this repo is

A [chezmoi](https://www.chezmoi.io/) dotfiles repo with
[ansible](https://www.ansible.com/) for system provisioning. The
source tree under `dot_*` and `dot_config/` is what gets deployed to
`$HOME`. The `ansible/` tree is consumed by `.chezmoiscripts/`
at apply time. Everything else (`tools/`, `mise.toml`,
`.pre-commit-config.yaml`, `AGENTS.md`) is repo-internal and listed
in `.chezmoiignore` so it never reaches the user's machine.

## Runtime config (not in this repo)

User-specific values live in `~/.config/chezmoi/chezmoi.toml` under
`[data]`. They are **not** committed. The repo's prompt scripts
(`run_onchange_before_10-prompt-user-info.sh.tmpl` and
`tools/chezmoi-init.sh`) write this file on first run.

Full schema:

```toml
[edit]
  command = "nvim"

[git]
  autoCommit = false
  autoPush = false

[data]
  role        = "personal"             # personal | work
  machineName = "your-hostname"        # hostname at bootstrap
  email       = "you@example.com"
  name        = "Your Name"
  playbook    = "fedora-personal"      # playbook basename | "none" | unset
```

Template variables available to `*.tmpl` files:

| Key            | Source                                         |
| -------------- | ---------------------------------------------- |
| `role`         | Prompt: `personal` \| `work`                   |
| `machineName`  | `hostname`                                     |
| `email`        | Prompt                                         |
| `name`         | Prompt                                         |
| `playbook`     | Prompt: playbook basename \| `none` \| unset   |
| `.chezmoi.*`   | Built-in (e.g. `.chezmoi.osRelease.id`)        |

When you add a new template variable, update **both** prompt scripts
and `tools/chezmoi-init.sh`.

## Repository layout

```
.chezmoiscripts/             scripts run by chezmoi (auto-triggered)
  run_onchange_before_00     install missing prereqs (git, curl, jq, unzip,
                             ansible-core, mise, gum)
  run_onchange_before_10     prompt for user info, write config (no-op once
                             chezmoi.toml exists)
  run_onchange_after_50      run the ansible playbook (selected via
                             chezmoi.toml `playbook`; legacy OS+role
                             fallback when unset)
tools/                       one-off setup scripts (not auto-used)
  chezmoi-init.sh            full bootstrap (prereqs + clone + prompt + apply)
  setup-btrfs-snapper/       snapper + btrfsmaintenance helpers
  win-fonts-script/          install Windows fonts
ansible/                     system provisioning (OS-aware)
  playbooks/fedora-personal.yml
  roles/installer/           pure data-driven installer role
    README.md                full role documentation
    defaults/main.yml        variables consumed by the role
    tasks/
      main.yml               orchestrator — imports the others
      pre_dnf.yml            Linux: bootstrap packages (runs first)
      dnf.yml                Linux: main package install
      pre_brew.yml           macOS: tap + bootstrap packages
      brew.yml               macOS: main package install
      flatpak.yml            Linux: flatpak repos + apps
      github.yml             clone repos + install release binaries
      keyboard.yml           xkb layout/options + ibus
      groups.yml             add the running user to supplementary groups
dot_zshrc.tmpl               OS+role aware (sources work.zsh or personal.zsh)
dot_gitconfig.tmpl           role-aware git identity
dot_XCompose                 Linux-only compose sequence overrides
dot_config/                  XDG config
  autostart/                 desktop autostart entries
  DankMaterialShell/         Wayland shell config
  dots/                      dotfile snippets
  environment.d/             systemd user env overrides
  mise/                      mise tool versions
  niri/                      niri compositor config
dot_local/                   XDG_DATA_HOME — flatpak overrides
mise.toml                    repo-local mise tool pins (betterleaks, prek)
.pre-commit-config.yaml      hooks (chezmoi, ansible-lint, shellcheck, …)
```

The `installer` role is pure-data driven — add new knobs (packages,
flatpaks, repos, pre-install commands, etc.) in
`ansible/playbooks/fedora-personal.yml`. For new scenarios, create a
new `ansible/playbooks/<os>-<role>.yml`; the prompt script
auto-discovers it. See `ansible/roles/installer/README.md` for the
full variable list grouped by phase, and
`ansible/roles/installer/defaults/main.yml` for defaults.

## Where to put things

| To add / change…                | Edit                                                           |
| ------------------------------- | -------------------------------------------------------------- |
| A new dotfile                   | Drop it at repo root with `dot_` prefix (or under `dot_config/`) |
| An OS- or role-aware dotfile    | Rename to `*.tmpl` and use `{{ .role }}` / `.chezmoi.osRelease.id` |
| A new `[data]` template variable| Update the schema block above, the table below, **both** prompt scripts (`.chezmoiscripts/run_onchange_before_10-…` and `tools/chezmoi-init.sh`) |
| A new package on Fedora         | `ansible/playbooks/fedora-personal.yml` (`packages:` list)     |
| Installer role defaults/flags   | `ansible/roles/installer/defaults/main.yml`                    |
| A new OS×role provisioning path| `ansible/playbooks/<os>-<role>.yml` (auto-discovers in prompt) |
| A new apply-time script         | `.chezmoiscripts/run_<when>_<NN>-<name>.sh.tmpl` (see [chezmoi run_onchange docs](https://www.chezmoi.io/docs/usage-guides/manage-machine-dotfiles/)) |
| A repo-only file (don't deploy) | Add it to `.chezmoiignore` (see [chezmoiignore reference](https://www.chezmoi.io/docs/reference/chezmoiignore/)) |

## How `run_onchange` works

Each `.chezmoiscripts/run_onchange_*.sh.tmpl` has a hash comment at
the top of the form:

```
# <name> hash: {{ output "bash" "-c" "<command>" | trim }}
```

chezmoi re-renders that template on every apply and compares the hash
to the previously rendered value. **If the hash differs, the script
runs.** This means:

- Editing the hash command itself triggers a one-shot re-run (often
  what you want).
- Editing any tracked file under `ansible/` triggers
  `run_onchange_after_50-ansible.sh` (which runs the playbook with
  `--ask-become-pass`). **Be careful — ansible applies can modify the
  user's system.**
- Editing the prereqs list in `run_onchange_before_00-install-prereqs.sh.tmpl`
  triggers a re-install on the next apply.

If you add a new `run_onchange` script, copy the hash pattern from an
existing one and choose a `bash -c` body that changes whenever the
script's triggers change.

## Ansible playbook selection

The `[data].playbook` field in the user's `chezmoi.toml` controls what
runs at apply time:

- `"none"` → skip ansible
- `"<basename>"` → run `ansible/playbooks/<basename>.yml`
- unset / empty → legacy fallback: `playbooks/<os>-<role>.yml`

If the resolved playbook file doesn't exist (e.g. `playbooks/<basename>.yml`
isn't checked in), the script logs `Playbook not found: …` and exits 0
without failing the apply. This is intentional: missing playbooks must
not break `chezmoi apply`.

Backward compatibility is intentional: do not remove the legacy
fallback without a major version bump.

## Validation

Before committing changes, run what `.pre-commit-config.yaml` runs:

```bash
bash -n <file>                  # bash syntax (also done by shellcheck)
ansible-playbook --syntax-check ansible/playbooks/<pb>.yml
pre-commit run --all-files      # full hook set: shellcheck, ansible-lint, …
```

To preview what chezmoi would change without applying:

```bash
chezmoi diff
chezmoi apply --dry-run --verbose
```

## Conventions

- **Bash**: `set -euo pipefail`, quote expansions, prefer
  `[[ … ]]` over `[ … ]`. Aim for shellcheck-clean.
- **Templates**: prefer `{{ .var | default "fallback" }}` over
  conditional `if` blocks when the fallback is simple. See the
  [chezmoi template docs](https://www.chezmoi.io/docs/templates/) for
  the full syntax.
- **Missing `[data]` keys are an error**, not nil. `{{ .var | default "x" }}`
  fails with `map has no entry for key "var"` if `var` is absent from
  `chezmoi.toml`. Use `{{ if hasKey . "var" }}{{ .var }}{{ end }}`
  instead when the key is optional (e.g. the `playbook` field).
- **Ansible**: pure-data driven — push new knobs into
  `roles/installer/defaults/main.yml`, not into task `vars:`.
- **Hash comments**: keep the hash command body on one line; multi-line
  `bash -c` payloads break chezmoi's hash extraction.

## Don't

- Don't modify `~/.config/chezmoi/chezmoi.toml` directly — it's
  user-managed; change the prompt scripts instead.
- Don't remove the legacy `playbook` fallback (unset → OS+role auto-detect)
  without coordinating with existing users.
- Don't add a script that auto-applies ansible without
  `--ask-become-pass` (or equivalent sudo handling) — the user's
  machine state matters.
- Don't commit secrets. The repo is a public dotfiles mirror.

## References

- [chezmoi documentation](https://www.chezmoi.io/docs/) — main entry point
- [chezmoi CLI reference](https://www.chezmoi.io/docs/reference/) — all `chezmoi` subcommands
- [chezmoi templates](https://www.chezmoi.io/docs/templates/) — `{{ .var }}` syntax, sprig functions
- [chezmoiignore reference](https://www.chezmoi.io/docs/reference/chezmoiignore/) — exclude patterns
- [Managing dotfiles across machines](https://www.chezmoi.io/docs/usage-guides/manage-machine-dotfiles/) — covers `run_onchange` and per-machine config