# `~/.config/dots/`

Snippets sourced by shell configs to keep them lean. Each `.zsh` file here
is a self-contained module: source it from `~/.zshrc` (or wherever) and it
sets up its own state.

## Current modules

| File | Source from `~/.zshrc` | What it does |
|---|---|---|
| `dank-palette.zsh` | after plugins, before `eval "$(starship init zsh)"` | Wires DankMaterialShell's matugen palette into fzf-tab, zsh-syntax-highlighting, zsh-autosuggestions, history-substring-search, Starship, and the terminal background. |

## Adding a new module

1. Drop a `something.zsh` file in this directory.
2. Source it from `~/.zshrc`:

   ```zsh
   [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/dots/something.zsh" ]] \
     && source "${XDG_CONFIG_HOME:-$HOME/.config}/dots/something.zsh"
   ```

3. Put any helpers, aliases, and the initial call inside the file so the
   one-liner above is all `~/.zshrc` needs.

The `[[ -f ... ]] && source ...` guard makes the snippet optional — if the
file is missing (e.g. on a fresh machine before dotfiles are deployed),
the shell still starts.
