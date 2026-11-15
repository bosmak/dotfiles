# Dotfiles

Dotfiles managed with [chezmoi](https://www.chezmoi.io/), with the system
provisioned by [ansible](https://www.ansible.com/).

## Bootstrap a new machine

```bash
# make sure `git`, `curl` and `tar` are available
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply bosmak
```

It prompts for:
- Editor command (default: `vim`) — used by `chezmoi edit` and by git
- Role (personal / work)
- Email
- Name
- Ansible playbook (one of the `ansible/playbooks/*.yml` basenames, or
  `none` to skip ansible)

## Apply changes (existing machine)

```bash
chezmoi apply
```

It can also run the ansible playbook, which changes the system.
