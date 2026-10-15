# `installer` role

Opinionated, OS-aware installer for the dotfiles. Pure data-driven —
declare what you want in the playbook, the role figures out the right
package manager and orders the work correctly.

## Execution flow

The single source of truth is `tasks/main.yml`. It is just an
orchestrator; each step delegates to its own file.

```
Linux                          macOS
──────                         ──────
pre_dnf                        pre_brew
  pre_packages_url               extra_repos (tap)
  extra_repos                    pre_packages
  pre_packages
  locked_packages
pre_install_commands           pre_install_commands
dnf                            brew
  packages_url                   packages
  packages                       packages_replace
  packages_replace
flatpak                        (skipped)
github                         github
keyboard                       (skipped)
groups                         groups
post_install_commands          post_install_commands
```

The split between `pre_dnf` and `dnf` (and the parallel
`pre_brew` / `brew`) is the interesting one — it lets
`pre_install_commands` sit in the middle, so workflows like "set up a
third-party repo → install from it" work on either platform:

```
pre_dnf         install rpmfusion + versionlock plugin, enable COPRs
                bootstrap dnf so anything below can rely on it being there
pre_install_*   curl a vendor `.repo` file into /etc/yum.repos.d/
                (or run any shell arbitrary the user needs)
dnf             install the actual packages — they can now see the
                repos enabled above
```

Both phases use the same engine (`dnf` or `brew`) but different variable
names so you control ordering precisely.

## File layout

```
defaults/main.yml    every knob this role consumes (all default to [])
tasks/
  main.yml          orchestrator — imports the others
  pre_dnf.yml       Linux: bootstrap packages (runs first)
  dnf.yml           Linux: main package install
  pre_brew.yml      macOS: tap + bootstrap packages
  brew.yml          macOS: main package install
  flatpak.yml       Linux: flatpak repos + apps
  github.yml        clone repos + install release binaries
  keyboard.yml      xkb layout + ibus engine via dconf
  groups.yml        add the running user to supplementary groups
```

## Variables

All listed in `defaults/main.yml`. Grouped by phase:

### `pre_dnf` phase
| Variable | Purpose |
| --- | --- |
| `pre_packages_url` | `.rpm` URLs to download to `/tmp` *before* anything else. Use for vendor release-rpm that just adds a repo (e.g. `protonvpn-stable-release`). |
| `extra_repos` | COPR repos to `dnf copr enable -y`. Run before `pre_packages` so packages installed next can come from them. |
| `pre_packages` | OS-level bootstrap deps installed via dnf (e.g. `rpmfusion-free-release`, `python3-dnf-plugin-versionlock`). |
| `locked_packages` | `versionlock add <name>-<ver>` for anything you don't want drifted. Runs last in this phase so it pins what we just installed. |

### `pre_install_commands` / `post_install_commands`
Arbitrary shell, run with `become: true` if requested. Use
`creates:` to make them idempotent.

### `dnf` main phase
| Variable | Purpose |
| --- | --- |
| `packages_url` | `.rpm` URLs that depend on repos added by `pre_install_commands` (e.g. a vendor `.rpm` only available after their `.repo` file lands). Download-only — does not install. |
| `packages` | Main dnf package list. |
| `packages_replace` | `[{old: ..., new: ...}]` pairs installed with `allowerasing: true`. |

### `flatpak`
| Variable | Purpose |
| --- | --- |
| `flatpak_repos` | List of `{name, url}` flatpak remotes to add. |
| `flatpak` | Flatpak app IDs to install. Currently all install from `flatpak_repos[0]` (no per-app `remote`). |

### `github`
| Variable | Purpose |
| --- | --- |
| `github_repositories` | Repos to clone (shallow) into a target path. |
| `github_release_binaries` | Release-binary installs. Per-arch `{filename, sha256}`, fetched, verified, extracted and dropped into `~/.local/bin/<link_name>`. Idempotent via sha256 stat. |

### `keyboard`
```yaml
keyboard:
  layout: us
  model: pc105
  variant: alt-intl
  options: []
  ibus_engine: xkb:us:alt-intl:eng
```
Writes xkb layout + ibus engine via `dconf`. Linux-only.

### `user_groups`
| Variable | Purpose |
| --- | --- |
| `user_groups` | Supplementary group names to add the running user to (e.g. `docker`, `libvirt`, `plugdev`). Uses `append: true` so existing membership is preserved. Groups that don't yet exist on the system are created first, so order vs. package install doesn't matter. Runs after `keyboard` and before `post_install_commands`. |

## Usage

The playbook just maps variables in:

```yaml
- hosts: localhost
  roles:
    - role: installer
      vars:
        pre_packages:
          - rpmfusion-free-release
          - python3-dnf-plugin-versionlock
        extra_repos:
          - jdxcode/mise
        pre_packages_url:
          - https://repo.protonvpn.com/.../protonvpn-stable-release-1.0.4-1.noarch.rpm
        packages:
          - firefox
          - mise
        locked_packages:
          - name: xwayland-satellite
            version: "0.8.1-1.fc44"
```

## Conventions

- **Prefixed variables belong to `pre_dnf`.** Anything `pre_*` runs in
  the pre-phase. Anything without that prefix runs in the main phase.
- **URLs and repos before packages.** Both phases obey this — URLs
  (which often contain a `.repo`-providing rpm) are downloaded before
  repos are added, and repos are added before packages are installed.
- **URLs are installed, not just downloaded.** Both `pre_packages_url`
  and `packages_url` use `ansible.builtin.dnf` with `name: "{{ item }}"`
  and `disable_gpg_check: true`, so an HTTP(S) URL installs the RPM
  directly. No `/tmp` round-trip.
- **Idempotent commands use `creates:`**. Both `pre_install_commands`
  and `post_install_commands` support it.
- **Unknown arch = skipped** in `github_release_binaries`. Allows
  shipping per-arch asset maps in the playbook without gating them
  with conditionals here.
