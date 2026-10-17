# `~/.config/dots/`

Snippets auto-sourced by `~/.zshrc` to keep it lean. Each `.zsh` file here
is a self-contained module: drop it in and it sets up its own state — no
edits to `~/.zshrc` needed.

## Loading

`dot_zshrc.tmpl` runs an alphabetical autoload of every `*.zsh` here.
What lands in this directory per machine is decided by `.chezmoiignore`
— the loop is OS-blind.

- Use `00-`, `10-`, `20-`, … prefixes to control order between snippets
  (e.g. `10-foo.zsh` before `20-bar.zsh`).
- To gate a snippet by OS, add a line to `.chezmoiignore` like:

  ```
  .config/dots/your-snippet.zsh {{ if ne .chezmoi.os "linux" }}
  ```

## Current modules

| File | What it does |
|---|---|
| `00-palette.zsh` | Picks the best palette source available — DankMaterialShell's `dms-colors.json` (matugen output) when present, otherwise the system accent color (macOS `AppleAccentColor`, GNOME `gsettings`, KDE `kdeglobals`) with a Python-derived Material You–style palette as fallback — and applies it to fzf-tab, zsh-syntax-highlighting, zsh-autosuggestions, history-substring-search, Starship, and the terminal background. |
| `20-functions.zsh` | Sources every regular file in `functions/` (alphabetical). Drop new one-off snippets there without touching `~/.zshrc` or adding entries here. |

## `functions/`

A scratchpad for small, self-contained snippets — aliases, helpers,
short scripts you want on the path-as-functions. Loaded by
`20-functions.zsh`, alphabetical.

- Files in here don't need number prefixes — order rarely matters for
  independent helpers.
- Put something that needs ordering earlier/later than its siblings?
  Prefix the file with `10-`, `20-`, etc. and the loader will still
  honor alphabetical order.

## Adding a new module

1. Drop a `something.zsh` file in this directory.
2. Prefix it with a number if it must load before/after a sibling
   (`20-something.zsh` loads after `10-whatever.zsh`).
3. Put any helpers, aliases, and the initial call inside the file — no
   `~/.zshrc` edit required; a `chezmoi apply` is enough.
4. If the snippet only makes sense on some OSes, gate it with a line in
   `.chezmoiignore` (see the example in **Loading** above).

If the file is missing on disk (e.g. on a fresh machine before dotfiles
are deployed, or on an OS where the snippet is gated off), the empty glob
means the loop is a harmless no-op and the shell still starts.
