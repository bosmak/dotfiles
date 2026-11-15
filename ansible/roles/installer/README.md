# `installer` role

Opinionated, OS-aware installer for the dotfiles. Pure data-driven —
declare what you want in the playbook, the role figures out the right
package manager and orders the work correctly.

## Execution flow

`tasks/main.yml` is just an orchestrator; each step delegates to its own
file. The order is what matters:

| File | Runs | What it does |
| --- | --- | --- |
| `pre_dnf.yml` | Linux, first | bootstrap packages (rpmfusion + versionlock plugin), enable COPRs |
| `pre_brew.yml` | macOS, first | tap + bootstrap packages |
| `pre_install_commands` | both | arbitrary shell, e.g. drop a vendor `.repo` file |
| `dnf.yml` | Linux | main package install |
| `brew.yml` | macOS | main package install |
| `flatpak.yml` | Linux | flatpak repos + apps |
| `github.yml` | both | clone repos + install release binaries |
| `keyboard.yml` | Linux | xkb layout + options via dconf |
| `groups.yml` | both | add the running user to supplementary groups |
| `post_install_commands` | both | arbitrary shell |

Every knob this role consumes is listed in `defaults/main.yml` and
defaults to `[]`.

The split between `pre_dnf` and `dnf` (and the parallel `pre_brew` /
`brew`) is the interesting one — it lets `pre_install_commands` sit in
the middle, so workflows like "set up a third-party repo → install from
it" work on either platform:

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

## Variables

All listed in `defaults/main.yml`. Grouped by phase:

### `pre_dnf` phase
| Variable | Purpose |
| --- | --- |
| `pre_packages_url` | `.rpm` URLs to download to `/tmp` *before* anything else. Use for vendor release-rpm that just adds a repo (e.g. `protonvpn-stable-release`). |
| `extra_repos` | COPR repos to `dnf copr enable -y`. Run before `pre_packages` so packages installed next can come from them. |
| `pre_packages` | OS-level bootstrap deps installed via dnf (e.g. `rpmfusion-free-release`, `python3-dnf-plugin-versionlock`). |
| `locked_packages` | `versionlock add <name>-<ver>` for anything you don't want drifted. Runs last in this phase so it pins what we just installed. |

### Lock contention (dnf)
Another package manager — usually PackageKit refreshing in the
background, sometimes a manual `dnf upgrade` — can hold the dnf repo
lock while this playbook runs. dnf then fails with:

```
Failed to acquire system repo lock for reading, lock located at "/var/lib/dnf/system-repo.lock"
```

Two mechanisms deal with it:

1. **Wait** — `dnf_lock.yml` blocks until the lock is free (probing
   both POSIX record locks and BSD `flock`, since libdnf does not use
   the same one everywhere). It runs first in the `pre_dnf` phase.
2. **Retry** — every dnf task retries while the error looks like lock
   contention. A *different* error (a package that does not exist, a
   broken repo) is **not** retried and fails the play immediately.

| Variable | Default | Purpose |
| --- | --- | --- |
| `dnf_lock_timeout` | `120` | Seconds to wait for the lock to be released. |
| `dnf_lock_retries` | `6` | How many times a blocked dnf task is retried. |
| `dnf_lock_delay` | `10` | Seconds between retries. |
| `dnf_retry_errors` | `[lock, already in progress]` | Error fragments that mean "dnf is busy". |

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
```
Writes the xkb layout + options via `dconf`. Linux-only.

### `user_groups`
| Variable | Purpose |
| --- | --- |
| `user_groups` | Supplementary group names to add the running user to (e.g. `docker`, `libvirt`, `plugdev`). Uses `append: true` so existing membership is preserved. Groups that don't yet exist on the system are created first, so order vs. package install doesn't matter. Runs after `keyboard` and before `post_install_commands`. |

## Usage

The knobs live in the variable layers under
`ansible/playbooks/vars/`, merged in order (system → profile →
machine) before the role runs:

```yaml
# ansible/playbooks/vars/system/fedora.yml — OS baseline
add:
  extra_repos:
    - jdxcode/mise
  pre_packages:
    - rpmfusion-free-release
    - python3-dnf-plugin-versionlock
  pre_packages_url:
    - https://repo.protonvpn.com/.../protonvpn-stable-release-1.0.4-1.noarch.rpm
  packages:
    - firefox
    - mise
  locked_packages:
    - name: xwayland-satellite
      version: "0.8.1-1.fc44"
```

A layer can then refine the previous one — a profile on top of the
system baseline, a machine on top of the profile:

```yaml
# ansible/playbooks/vars/profile/fedora-personal.yml
add:
  packages: [steam]              # appended to the base list
# ansible/playbooks/vars/machines/<hostname>.yml
add:
  packages: [iwlwifi-mvm-firmware]
remove:
  packages: [steam]              # subtracted from the list
override:
  keyboard: {layout: br}         # replaces the base value
```

The merge happens in `ansible/playbooks/tasks/apply-layer.yml`
(`set_fact`, which outranks `vars_files`, `include_vars`,
`group_vars`/`host_vars` and role defaults). The layer data therefore
**must** stay out of the role params — data passed there would win
over the merge.

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
