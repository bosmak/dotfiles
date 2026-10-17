# Loads every regular file in ./functions/ (shallow glob, alphabetical).
# Drop new snippets in ~/.config/dots/functions/ and they'll be picked up
# automatically — no edits to ~/.zshrc required.
#
# The glob qualifiers:
#   [^.]* — skip dotfiles (e.g. .gitkeep)
#   (N.)  — N: null-glob, empty directory is a harmless no-op
#           .: only regular files (skip subdirs, symlinks-to-dirs, etc.)
for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/dots/functions/[^.]*(.N); do
  source "$f"
done
unset f
