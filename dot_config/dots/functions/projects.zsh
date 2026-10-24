# ~/.config/dots/functions/projects.zsh
#
# Quickly switch to Git projects in ~/Workspace.
#
#   p copr                 # open ~/Workspace/copr
#   p mlops/api            # open a nested project
#   p mlops                # open the only Git project below an organization
#   p api                  # open a uniquely named nested project
#   p new-copr             # create ~/Workspace/copr as a Git repository
#   P co<Tab>              # complete project paths and names
#
# Missing projects are created as Git repositories after confirmation.
# Set WORKSPACE_DIR to use a workspace other than ~/Workspace.

projects() {
  emulate -L zsh
  setopt local_options

  local workspace="${WORKSPACE_DIR:-$HOME/Workspace}"

  if (( $# > 1 )); then
    print -u2 "usage: ${(%):-%N} [<project>]"
    return 2
  fi

  if [[ ! -d $workspace ]]; then
    print -u2 "Workspace not found: ${workspace}"
    return 1
  fi

  if (( $# == 0 )); then
    builtin cd -- "$workspace"
    return $?
  fi

  local requested=$1
  requested="${requested%/}"

  # A relative path may contain directories, but it must not escape the
  # workspace.
  if [[ -z $requested || $requested == /* || $requested == *$'\n'* || $requested == *$'\r'* ]]; then
    print -u2 "Invalid project path: ${requested}"
    return 1
  fi

  local -a components
  components=("${(s:/:)requested}")
  local component
  for component in "${components[@]}"; do
    if [[ -z $component || $component == . || $component == .. ]]; then
      print -u2 "Invalid project path: ${requested}"
      return 1
    fi
  done

  # Preserve the original "new-" convention while allowing any missing
  # project to be created too.
  local target=$requested
  if [[ $target == new-* ]]; then
    target=${target#new-}
  fi

  if [[ -z $target ]]; then
    print -u2 "Invalid project path: ${requested}"
    return 1
  fi

  # Find all Git repositories below the workspace. A requested path can
  # match a repository exactly, contain repositories, or identify one by a
  # unique path suffix (for example, "mlops/api").
  local -a repo_roots
  local repo_root
  while IFS= read -r -d '' repo_root; do
    repo_roots+=("$repo_root")
  done < <(_project_repository_roots "$workspace")

  local -a matches
  local best_score=0
  local relative score
  for repo_root in "${repo_roots[@]}"; do
    relative="${repo_root#"$workspace"/}"
    [[ -z $relative ]] && continue

    score=0
    if [[ $relative == "$target" ]]; then
      score=100
    elif [[ $relative == "${target}/"* ]]; then
      score=90
    elif [[ $relative == *"/${target}" ]]; then
      score=80
    elif [[ ${relative:t} == "${target:t}" ]]; then
      score=70
    fi

    if (( score > best_score )); then
      matches=("$repo_root")
      best_score=$score
    elif (( score == best_score && score > 0 )); then
      matches+=("$repo_root")
    fi
  done

  if (( ${#matches} )); then
    local selected
    if (( ${#matches} == 1 )); then
      selected=${matches[1]}
    else
      print -r -- "Multiple projects match '${target}':"
      local index
      for (( index = 1; index <= ${#matches}; index++ )); do
        repo_root=${matches[index]}
        relative="${repo_root#"$workspace"/}"
        print -r -- "  ${index}) ${relative}"
      done

      local choice
      read -r "choice?Select a project [1-${#matches}]: " || return 1
      if [[ $choice != <-> ]] || (( choice < 1 || choice > ${#matches} )); then
        print -u2 "Invalid selection: ${choice}"
        return 1
      fi
      selected=${matches[choice]}
    fi

    builtin cd -- "$selected"
    return $?
  fi

  local project_dir="${workspace}/${target}"
  if [[ -e $project_dir && ! -d $project_dir ]]; then
    print -u2 "Project path is not a directory: ${project_dir}"
    return 1
  fi

  # Existing organizational directories without a repository are still
  # useful, so open them when no nested project matched.
  if [[ -d $project_dir ]]; then
    builtin cd -- "$project_dir"
    return $?
  fi

  print -r -- "Project '${target}' does not exist in ${workspace}."

  if ! command -v git >/dev/null 2>&1; then
    print -u2 "Git is required to create a project."
    return 127
  fi

  local answer
  while true; do
    read -r "answer?Create '${target}' as a Git repository? (Y/n) " || return 1
    [[ -z $answer ]] && answer=Y

    case $answer in
      [Yy] | [Yy][Ee][Ss])
        break
        ;;
      [Nn] | [Nn][Oo])
        print -r -- "Project '${target}' was not created."
        return 1
        ;;
      *)
        print -r -- "Please answer Y or n."
        ;;
    esac
  done

  if ! mkdir -p -- "$project_dir"; then
    print -u2 "Could not create project directory: ${project_dir}"
    return 1
  fi

  if ! git init --quiet -- "$project_dir"; then
    print -u2 "Could not initialize Git repository: ${project_dir}"
    return 1
  fi

  builtin cd -- "$project_dir"
}

# Print repository roots separated by NUL bytes so paths containing spaces
# remain intact.
_project_repository_roots() {
  local workspace=$1
  local -a git_entries
  local git_entry

  git_entries=("$workspace"/**/.git(N))
  for git_entry in "${git_entries[@]}"; do
    print -rN -- "${git_entry:h}"
  done
}

# Use ordinary functions rather than aliases so completion can be attached
# reliably to both the short command and its uppercase variant.
p() {
  projects "$@"
}

P() {
  projects "$@"
}

_projects() {
  local workspace="${WORKSPACE_DIR:-$HOME/Workspace}"
  local -a repo_roots
  local repo_root

  [[ -d $workspace ]] || return 1

  while IFS= read -r -d '' repo_root; do
    repo_roots+=("$repo_root")
  done < <(_project_repository_roots "$workspace")

  local -a entries
  local relative basename
  for repo_root in "${repo_roots[@]}"; do
    relative="${repo_root#"$workspace"/}"
    [[ -z $relative ]] && continue

    # Offer the full relative path ("mlops/api") and the short name
    # ("api"), so both "P mlops/a" and "P a" can complete.
    entries+=("${relative//:/\\:}:Git repository")
    basename=${relative:t}
    if [[ $basename != $relative ]]; then
      entries+=("${basename//:/\\:}:${relative//:/\\:}")
    fi
  done

  (( ${#entries} )) || return 1
  _describe -t projects 'project' entries
}

if (( $+functions[compdef] )); then
  compdef _projects projects p P
fi
