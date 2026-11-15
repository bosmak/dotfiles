# Dotfiles

Dotfiles managed with [chezmoi](https://www.chezmoi.io/), system
provisioning handled by [ansible](https://www.ansible.com/) via
`run_onchange` scripts in `.chezmoiscripts/`.

## Bootstrap a new machine

```bash
# make sure `git` and `curl` are available
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply bosmak
```

`git` is needed for the clone, which happens before the apply can
install anything. `jq`, `gum` and `ansible-core` are installed during
the apply, `mise` by the ansible playbook.

The apply prompts for the user info, so re-running `chezmoi apply` after
deleting `~/.config/chezmoi/chezmoi.toml` re-prompts for it.

On first run the user info script will prompt for:
- Editor command (default: `vim`) — used by `chezmoi edit` and by git
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

## Variable layers: system → profile → machine

The playbook binds the three layers at run time: the system comes from
the os-release ID, the profile from your role, and the machine from
the hostname:

```
ansible/playbooks/vars/system/fedora.yml            OS baseline
ansible/playbooks/vars/profile/fedora-personal.yml persona
ansible/playbooks/vars/machines/<hostname>.yml   hardware
```

Each layer is optional and refines the previous one:

```yaml
# ansible/playbooks/vars/machines/<hostname>.yml
add:
  packages: [nvidia-vaapi-driver]   # appended to the list
remove:
  packages: [steam]                 # subtracted from the list
merge:
  post_install_vars: {dms_hidden_apps: [my-app]}
override:
  keyboard: {layout: br}            # replaces the value
```

The machine is matched by hostname — the playbook reads the
`ansible_hostname` fact. Create one layer file per machine that
needs it; the others just get the system + profile layers.


## Changing which ansible playbook runs

The `playbook` line in `~/.config/chezmoi/chezmoi.toml` controls what
runs at apply time:

| Value          | Behaviour                                          |
| -------------- | -------------------------------------------------- |
| `"none"`       | Skip ansible entirely.                             |
| `"<basename>"` | Run `ansible/playbooks/<basename>.yml`.            |
| (unset)        | Legacy: derive from `<os>-<role>`, then `default`. |

A basename that no longer exists falls back to `default.yml` instead of
skipping ansible. The playbook name carries no system or profile: both
are resolved when the play runs.

Edit the file directly:

```toml
[data]
  playbook = "default"
```

Or delete the config to re-prompt for everything:

```bash
rm ~/.config/chezmoi/chezmoi.toml
chezmoi apply
```

