# Dotfiles

Dotfiles managed with [chezmoi](https://www.chezmoi.io/), system
provisioning handled by [ansible](https://www.ansible.com/) via
`run_onchange` scripts in `.chezmoiscripts/`.

## Bootstrap a new machine

**One-liner via the custom bootstrap script** (handles prereqs + clone + prompt + apply):

```bash
export GITHUB_USERNAME=bosmak
sh -c "$(curl -fsSL https://raw.githubusercontent.com/$GITHUB_USERNAME/dotfiles/main/tools/chezmoi-init.sh)" -- $GITHUB_USERNAME
```

**Or via standard chezmoi init** (the bootstrap script is also re-runnable for re-prompting):
```bash
sudo dnf install -y git curl jq unzip
export GITHUB_USERNAME=bosmak
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply "$GITHUB_USERNAME"
```

On first run the user info script will prompt for:
- Role (personal / work)
- Email
- Name
- Ansible playbook (one of the `ansible/playbooks/*.yml` basenames, or
  `none` to skip ansible)

…using `gum` (installed by the prereqs script). The values go into
`~/.config/chezmoi/chezmoi.toml` and drive the role-aware templates.

## Apply changes (existing machine)

```bash
chezmoi apply
```

This re-runs any apply-time scripts (see `.chezmoiscripts/`) whose
tracked content has changed since the last apply, including the
ansible playbook when `ansible/` has changed. The `playbook` setting
in `~/.config/chezmoi/chezmoi.toml` controls whether ansible runs at
all — see the next section.

## Changing which ansible playbook runs

The `playbook` line in `~/.config/chezmoi/chezmoi.toml` controls what
runs at apply time:

| Value          | Behaviour                                          |
| -------------- | -------------------------------------------------- |
| `"none"`       | Skip ansible entirely.                             |
| `"<basename>"` | Run `ansible/playbooks/<basename>.yml`.            |
| (unset)        | Legacy: derive from `<os>-<role>` (old behaviour). |

Edit the file directly:

```toml
[data]
  playbook = "fedora-personal"
```

Or delete the config to re-prompt for everything:

```bash
rm ~/.config/chezmoi/chezmoi.toml
chezmoi apply
```

