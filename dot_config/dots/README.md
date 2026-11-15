# `~/.config/dots/`

Snippets auto-sourced by `~/.zshrc` to keep it lean. Each `.zsh` file here
is a self-contained module: drop it in and it sets up its own state — no
edits to `~/.zshrc` needed.

## Loading

`dot_zshrc.tmpl` runs an alphabetical autoload of every `*.zsh` here.
What lands in this directory per machine is decided by `.chezmoiignore`
— the loop is OS-blind.
