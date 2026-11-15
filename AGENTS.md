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
  command = "vim"

[git]
  autoCommit = false
  autoPush = false

[data]
  role        = "personal"             # personal | work
  email       = "you@example.com"
  name        = "Your Name"
  playbook    = "default"              # playbook basename | "none" | unset
```

Template variables available to `*.tmpl` files:

| Key            | Source                                         |
| -------------- | ---------------------------------------------- |
| `role`         | Prompt: `personal` \| `work`                   |
| `email`        | Prompt                                         |
| `name`         | Prompt                                         |
| `playbook`     | Prompt: playbook basename \| `none` \| unset   |
| `.chezmoi.*`   | Built-in (e.g. `.chezmoi.osRelease.id`)        |

`machineName` is gone: the machine layer is picked at run time from the
`ansible_hostname` fact. The system layer follows the os-release ID, so
there is no key for it either.

The editor is asked at bootstrap and stored in `[edit].command`.
`dot_gitconfig.tmpl` reuses it for `core.editor`, so the two can never
drift apart.

When you add a new template variable, update **both** prompt scripts
and `tools/chezmoi-init.sh`.

## Repository layout

```
.chezmoiscripts/             scripts run by chezmoi (auto-triggered)
  run_onchange_before_00     install missing prereqs (git, curl, jq, gum,
                             ansible-core)
  run_onchange_before_10     prompt for user info, write config (no-op once
                             chezmoi.toml exists)
  run_onchange_after_50      run the ansible playbook (selected via
                             chezmoi.toml `playbook`; legacy OS+role
                             fallback when unset)
  run_after_60               drop the bootstrap chezmoi (~/.local/bin or
                             ~/bin) once mise provides chezmoi
tools/                       one-off setup scripts (not auto-used)
  chezmoi-init.sh            bootstrap (prereqs + clone + apply)
  setup-btrfs-snapper/       snapper + btrfsmaintenance helpers
  win-fonts-script/          install Windows fonts
  pre-commit/                lint helpers used by .pre-commit-config.yaml
    lint-scripts.sh          renders chezmoi templates, then runs
                             shellcheck (bash) or `zsh -f -n` (zsh)
ansible/                     system provisioning (OS-aware)
  playbooks/
    default.yml               generic play: binds system + profile + machine
                             at run time
    tasks/
      apply-layer.yml       loads and merges one variable layer
    vars/                    variable layers (see below)
      system/fedora.yml     OS baseline (any Fedora machine)
      profile/
        fedora-personal.yml persona on top of the system baseline
      machines/
        <hostname>.yml       hardware specifics for this machine
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
      keyboard.yml           xkb layout/options via dconf
      groups.yml             add the running user to supplementary groups
dot_zshrc.tmpl               OS+role aware (sources work.zsh or personal.zsh)
dot_gitconfig.tmpl           role-aware git identity
dot_XCompose                 Linux-only compose sequence overrides
dot_config/                  XDG config
  autostart/                 desktop autostart entries
  DankMaterialShell/         Wayland shell config
  dots/                      dotfile snippets
  environment.d/             systemd user env overrides
  fcitx5/                    fcitx5 profile (input method selection)
  gtk-3.0/, gtk-4.0/         GTK settings (fcitx IM module for XWayland)
  mise/                      mise tool versions
  niri/                      niri compositor config
dot_local/                   XDG_DATA_HOME — flatpak overrides
mise.toml                    repo-local mise tool pins (betterleaks, prek,
                             shellcheck)
.pre-commit-config.yaml      hooks (chezmoi, ansible-lint, shellcheck, zsh)
```

The `installer` role is pure-data driven — add new knobs (packages,
flatpaks, repos, pre-install commands, etc.) in the **variable
layers** under `ansible/playbooks/vars/`. For new scenarios, create a
new `ansible/playbooks/<os>-<role>.yml`; the prompt script
auto-discovers it. See `ansible/roles/installer/README.md` for the
full variable list grouped by phase, and
`ansible/roles/installer/defaults/main.yml` for defaults.

## Variable layers (system → profile → machine)

The repo is cloned on every machine, so anything committed here is
identical everywhere. Three layers are merged in order, each one
refining the previous:

```
ansible/playbooks/vars/system/<system>.yml            OS baseline
ansible/playbooks/vars/profile/<system>-<profile>.yml persona
ansible/playbooks/vars/machines/<hostname>.yml         hardware
```

The playbook binds the first two (`system: fedora`,
`profile: personal`); the third is picked by hostname. Every layer is
**optional** — a missing file simply contributes nothing.

Layers are named `<system>-<profile>` because a profile is always
shaped by its system (dnf vs brew, flatpaks vs casks): a future
`macos-personal.yml` re-lists the personal apps on purpose.

Each layer file uses the same four sections:

| Section    | Meaning                                                     |
| ---------- | ----------------------------------------------------------- |
| `add`      | append to a list (order preserved, duplicates skipped)      |
| `remove`   | subtract from a list                                        |
| `merge`    | deep-merge into a map (`combine`, recursive — lists inside are **replaced**) |
| `override` | replace the value entirely                                  |

```yaml
# ansible/playbooks/vars/machines/<hostname>.yml
add:
  packages: [nvidia-vaapi-driver]
remove:
  packages: [steam]
override:
  keyboard: {layout: us, model: pc105, variant: alt-intl, options: []}
```

The machine is identified by the `ansible_hostname` fact, so the
machine layer file is named after the host the play runs on.

Precedence notes (verified on ansible-core 2.20):

- Within a layer the sections apply in the order `merge` →
  `override` → `add` → `remove`, so a layer's own commands can
  reference values it defines.
- A layer is templated **when it is merged** — a later layer that
  changes a value referenced by an earlier layer's command has to
  re-declare that command.
- `set_fact` beats `vars_files`, `include_vars`, `group_vars`,
  `host_vars` and role defaults, so the merged value is what the
  `installer` role sees. Data passed as **role params** (`vars:`
  under `roles:`) would beat the merge instead — keep it in layers.
- Use `reject('in', ...)` for list merges — `union`/`difference` are
  set-based and shuffle the order (matters for
  `post_install_commands`).
- Layer files are templated at merge time, so `gather_facts` must be
  on (it is) for `ansible_env` to be available.

## Where to put things

| To add / change…                | Edit                                                           |
| ------------------------------- | -------------------------------------------------------------- |
| A new dotfile                   | Drop it at repo root with `dot_` prefix (or under `dot_config/`) |
| An OS- or role-aware dotfile    | Rename to `*.tmpl` and use `{{ .role }}` / `.chezmoi.osRelease.id` |
| A new `[data]` template variable| Update the schema block above, the table below, **both** prompt scripts (`.chezmoiscripts/run_onchange_before_10-…` and `tools/chezmoi-init.sh`) |
| A new package on Fedora         | `ansible/playbooks/vars/system/fedora.yml` (`add.packages`) or `vars/profile/fedora-personal.yml` for personal apps |
| A setting for one machine only  | `ansible/playbooks/vars/machines/<hostname>.yml` (`add`/`remove`/`merge`/`override`) |
| A new persona (work, vm, …)     | `ansible/playbooks/vars/profile/<system>-<profile>.yml` |
| Installer role defaults/flags   | `ansible/roles/installer/defaults/main.yml`                    |
| A new provisioning path         | `ansible/playbooks/<name>.yml` (auto-discovers in prompt) |
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

A script that must run on **every** apply uses `run_after_<NN>-<name>.sh`
with no hash comment — for example `run_after_60-chezmoi-handover.sh`,
which drops the bootstrap chezmoi once mise provides one.

## Package ownership

The apply-time prereqs script installs `git curl jq gum ansible-core`.
**mise is not in that list**: it ships from the `jdxcode/mise` COPR,
which only the ansible playbook enables (`extra_repos` →
`pre_dnf.yml`). The playbook owns mise, and its `mise install --yes`
post-install command installs the tools declared in
`~/.config/mise/config.toml` — including chezmoi. A prereqs script that
installed mise with a plain `dnf install mise` would abort the whole
transaction on a machine where the COPR is not enabled yet, which kills
the apply before the prompt and the playbook run.

## Ansible playbook selection

The `[data].playbook` field in the user's `chezmoi.toml` controls what
runs at apply time:

- `"none"` → skip ansible
- `"<basename>"` → run `ansible/playbooks/<basename>.yml`
- unset / empty → legacy fallback: `playbooks/<os>-<role>.yml`, then
  `playbooks/default.yml`

A basename that no longer exists falls back to `default.yml` instead of
skipping ansible; only when no playbook is available at all does the
script log `Playbook not found: …` and exit 0 without failing the apply.
This is intentional: missing playbooks must not break `chezmoi apply`.

Playbook names carry no system or profile. The play binds them at run
time: the system layer follows the os-release ID and the profile layer
follows `[data].role`.

Backward compatibility is intentional: do not remove the legacy
fallback without a major version bump.

## Validation

Before committing changes, run what `.pre-commit-config.yaml` runs:

```bash
mise install                    # repo tools: prek, betterleaks, shellcheck
bash -n <file>                  # bash syntax (also done by shellcheck)
zsh -f -n <file>                # zsh syntax (also done by the zsh hook)
ansible-playbook --syntax-check ansible/playbooks/<pb>.yml
prek run -a                     # full hook set: shellcheck, zsh, ansible-lint, …
```

The lint hooks live in `.pre-commit-config.yaml`:

- `shellcheck` — every `.sh`/`.bash` file, including the `.sh.tmpl`
  chezmoi templates, which are rendered with `chezmoi execute-template`
  before being checked.
- `zsh-syntax-check` — every `.zsh`/`.zshrc` file with `zsh -f -n`
  (shellcheck does not understand zsh).
- Both are implemented by `tools/pre-commit/lint-scripts.sh`.

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
- **`.chezmoiignore`**: patterns are matched against the **target** path
  relative to `$HOME` (e.g. `.config/niri/**`), *not* the source name
  (`dot_config/niri/**` never matches). After every change that adds,
  removes, or renames source files, re-check `.chezmoiignore`: new
  source paths must either be deployed on purpose or added to it.

## Don't

- Don't forget to update `.chezmoiignore` after a change — check it with
  `chezmoi ignored` and `chezmoi managed` (target-path patterns) when in
  doubt if something should be ignored, ask! Only ignore if you are 100% sure
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
