# Dotfiles

Dotfiles managed with [chezmoi](https://www.chezmoi.io/), system
provisioning handled by [ansible](https://www.ansible.com/) via
`run_onchange` scripts in `.chezmoiscripts/`.

## Bootstrap a new machine (Fedora)

**One-liner via the custom bootstrap script** (handles prereqs + clone + prompt + apply):

```bash
export GITHUB_USERNAME=bosmak
sh -c "$(curl -fsSL https://raw.githubusercontent.com/$GITHUB_USERNAME/dotfiles/main/tools/chezmoi-init.sh)" -- $GITHUB_USERNAME
```

**Or via standard chezmoi init** (the bootstrap script is also re-runnable for re-prompting):
```bash
# Absolute minimum to run chezmoi itself
sudo dnf install -y git curl jq unzip
export GITHUB_USERNAME=bosmak
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply "$GITHUB_USERNAME"
```

On first run the user info script will prompt for:
- Role (personal / work)
- Email
- Name

…using `gum` (installed by the prereqs script). The values go into
`~/.config/chezmoi/chezmoi.toml` and drive the role-aware templates.

## Apply changes (existing machine)

```bash
chezmoi apply
```

This also re-runs the ansible playbook if `ansible/` changed (via
the `run_onchange_after_50-ansible` script).

## Re-prompt for user info

```bash
rm ~/.config/chezmoi/chezmoi.toml
chezmoi apply
```

## Layout

```
.chezmoiscripts/             scripts run by chezmoi (before/after apply)
bin/                         one-off setup scripts (not auto-used)
  run_onchange_before_00     install missing prereqs (git, curl, jq, ansible, mise, gum)
  run_once_before_10         prompt for user info, write config
  run_onchange_after_50      run the ansible playbook
ansible/                    system provisioning (OS-aware)
  playbooks/fedora-personal.yml
  roles/installer/
    defaults/main.yml        variables consumed by the role
    tasks/
      main.yml               pre/post-install + flatpak + imports
      dnf.yml                dnf install / COPR / versionlock
      brew.yml               brew install / tap (macOS-ready)
      github.yml             clone repos + install release binaries
      keyboard.yml           keyboard layout/options + ibus
dot_zshrc.tmpl               OS+role aware (sources work.zsh or personal.zsh)
dot_gitconfig.tmpl           role-aware git identity
dot_config/                  XDG config (mise tools, zsh snippets, etc.)
```

## Variables

All knobs are in `playbooks/fedora-personal.yml` (or a new
`playbooks/<os>-<role>.yml` for a new scenario). The role
`ansible/roles/installer/` reads them; see
`ansible/roles/installer/defaults/main.yml` for the full list.
