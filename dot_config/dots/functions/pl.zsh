# ~/.config/dots/functions/pl.zsh
#
# pl — list the Git projects of the workspace as a tree with Git status.
#
#   pl                # the whole workspace
#   pl mlops          # only the "mlops" subtree
#
# Layout:
#
#   .
#   ├── copr                        (main)      ↻   1↓
#   ├── other-project               (main)      ✓
#   └── mlops
#       └── infrastructure          (feat/XYZ)  ↻   1↑ 1↓
#
# Status legend:
#   (branch)   current branch (or "detached@<sha>" / "(empty)")
#   ✓          in sync with the remote and a clean working tree
#   ↻          out of sync with the remote
#   1↑         commits to push        1↓  commits to pull
#   ⇢          no remote to push to   ⚠  the upstream branch is gone
#   *          uncommitted changes
#
# Set WORKSPACE_DIR to use a workspace other than ~/Workspace.

# Kind of every node of the tree: "dir" (container) or "repo" (Git project).
typeset -gA _pl_kind
# Branch and status columns of every repository node.
typeset -gA _pl_branch _pl_status
# Column widths, computed before rendering.
typeset -g _pl_name_width _pl_branch_width
# Result of the last _pl_repo_status call.
typeset -g _pl_s_branch _pl_s_status

pl() {
  emulate -L zsh
  setopt local_options pipefail typeset_silent

  local workspace="${WORKSPACE_DIR:-$HOME/Workspace}"
  local root_rel=""
  local relative parent part key index
  local -a repo_roots git_entries parts
  local repo_root git_entry

  if (( $# > 1 )); then
    print -u2 "usage: ${(%):-%N} [path]"
    return 2
  fi

  if [[ ! -d $workspace ]]; then
    print -u2 "Workspace not found: ${workspace}"
    return 1
  fi

  # Optional subtree filter, for example "pl mlops".
  if (( $# == 1 )); then
    root_rel="${1%/}"
    if [[ -z $root_rel || $root_rel == /* || $root_rel == *..* ]]; then
      print -u2 "Invalid path: $1"
      return 1
    fi
    if [[ ! -d "${workspace}/${root_rel}" ]]; then
      print -u2 "Path not found in the workspace: ${root_rel}"
      return 1
    fi
  fi

  # Collect the repositories of the workspace.
  if (( $+functions[_project_repository_roots] )); then
    while IFS= read -r -d '' repo_root; do
      repo_roots+=("$repo_root")
    done < <(_project_repository_roots "$workspace")
  else
    for git_entry in "${workspace}"/**/.git(N); do
      repo_roots+=("${git_entry:h}")
    done
  fi

  # Build the tree: every directory on the way to a repository, plus the
  # repositories themselves.
  _pl_kind=()
  for repo_root in "${repo_roots[@]}"; do
    relative="${repo_root#"$workspace"/}"
    [[ -z $relative ]] && continue

    parts=("${(s:/:)relative}")
    parent=""
    for (( index = 1; index < ${#parts}; index++ )); do
      part=${parts[index]}
      key="${parent:+${parent}/}${part}"
      [[ ${_pl_kind[$key]} == repo ]] || _pl_kind[$key]=dir
      parent=$key
    done

    key="${parent:+${parent}/}${parts[-1]}"
    _pl_kind[$key]=repo
  done

  # Gather the Git status of every repository.
  _pl_branch=()
  _pl_status=()
  for key in "${(@k)_pl_kind}"; do
    [[ ${_pl_kind[$key]} == repo ]] || continue
    _pl_repo_status "${workspace}/${key}"
    _pl_branch[$key]=$_pl_s_branch
    _pl_status[$key]=$_pl_s_status
  done

  # Column widths.
  _pl_name_width=0
  _pl_branch_width=0
  for key in "${(@k)_pl_kind}"; do
    (( ${#key:t} > _pl_name_width )) && _pl_name_width=${#key:t}
    if [[ ${_pl_kind[$key]} == repo ]]; then
      (( ${#_pl_branch[$key]} > _pl_branch_width )) && _pl_branch_width=${#_pl_branch[$key]}
    fi
  done

  # Root of the tree.
  local root_label="."
  if [[ -n $root_rel ]]; then
    root_label=$root_rel
  elif [[ -d ${workspace}/.git ]]; then
    # The workspace itself is a repository: show its status on the root.
    _pl_repo_status "$workspace"
    _pl_branch[$root_label]=$_pl_s_branch
    _pl_status[$root_label]=$_pl_s_status
    (( ${#_pl_s_branch} > _pl_branch_width )) && _pl_branch_width=${#_pl_s_branch}
  fi

  _pl_print_node "$root_label" "$root_label" ""

  if [[ -n $root_rel ]]; then
    _pl_render_tree "${workspace}/${root_rel}" "$root_rel" ""
  else
    _pl_render_tree "$workspace" "" ""
  fi
}

# Print a single tree line, with the branch and status columns when the
# node is a repository.
_pl_print_node() {
  emulate -L zsh
  setopt local_options typeset_silent extended_glob

  local name=$1 key=$2 connector=$3
  local text="$name"
  local branch=${_pl_branch[$key]}
  local state=${_pl_status[$key]}
  local color=""

  if [[ -n $branch ]]; then
    # The "r" flag pads on the right, keeping the text left aligned.
    text="${(r:${_pl_name_width}:)name}  ${(r:${_pl_branch_width}:)branch}"

    if [[ -n $state ]]; then
      text+="  ${state}"
      if [[ $state == *'*' || $state == *'⚠'* ]]; then
        color="red"
      elif [[ $state == *'↻'* || $state == *'⇢'* ]]; then
        color="yellow"
      else
        color="green"
      fi
    fi
  fi

  # Drop the trailing padding of the last column.
  text="${text%%[[:space:]]#}"

  local code=""
  if [[ -n $color && -t 1 && ${TERM:-dumb} != dumb ]]; then
    case $color in
      red) code=$'\e[31m' ;;
      yellow) code=$'\e[33m' ;;
      green) code=$'\e[32m' ;;
    esac
  fi

  if [[ -n $code ]]; then
    print -r -- "${connector}${code}${text}"$'\e[0m'
  else
    print -r -- "${connector}${text}"
  fi
}

# Render the children of a directory node.
_pl_render_tree() {
  emulate -L zsh
  setopt local_options typeset_silent

  local absolute=$1 relative=$2 prefix=$3
  local child_absolute child_name child_relative
  local index count
  local connector child_prefix
  local -a children

  for child_absolute in "$absolute"/*(N/); do
    child_name=${child_absolute:t}
    child_relative="${relative:+${relative}/}${child_name}"
    [[ -n ${_pl_kind[$child_relative]} ]] || continue
    children+=("$child_name")
  done

  (( ${#children} )) || return 0
  children=(${(o)children})

  count=${#children}
  for (( index = 1; index <= count; index++ )); do
    child_name=${children[index]}
    child_relative="${relative:+${relative}/}${child_name}"
    if (( index == count )); then
      connector="${prefix}└── "
      child_prefix="${prefix}    "
    else
      connector="${prefix}├── "
      child_prefix="${prefix}│   "
    fi

    _pl_print_node "$child_name" "$child_relative" "$connector"
    _pl_render_tree "${absolute}/${child_name}" "$child_relative" "$child_prefix"
  done
}

# Fill _pl_s_branch and _pl_s_status for a repository.
_pl_repo_status() {
  emulate -L zsh
  setopt local_options pipefail typeset_silent

  local repo=$1
  local branch upstream ahead=0 behind=0 dirty=0
  local porcelain sha counts symbol=""
  local -a tokens

  _pl_s_branch=""
  _pl_s_status=""

  branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [[ -z $branch ]]; then
    sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)
    if [[ -n $sha ]]; then
      branch="detached@${sha}"
    else
      branch="(empty)"
    fi
  fi

  upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
  if [[ -z $upstream ]]; then
    upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null)
  fi

  porcelain=$(git -C "$repo" status --porcelain 2>/dev/null)
  [[ -n $porcelain ]] && dirty=1

  if [[ -z $upstream ]]; then
    if git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
      symbol="⇢"
    fi
  elif ! git -C "$repo" rev-parse --verify --quiet "${upstream}^{commit}" >/dev/null 2>&1; then
    symbol="⚠"
  else
    counts=$(git -C "$repo" rev-list --left-right --count "HEAD...${upstream}" 2>/dev/null)
    if [[ -n $counts ]]; then
      ahead=${counts%%$'\t'*}
      behind=${counts##*$'\t'}
      ahead=${ahead:-0}
      behind=${behind:-0}
    fi
    if (( ahead > 0 || behind > 0 )); then
      symbol="↻"
      if (( ahead > 0 )); then
        tokens+=("${ahead}↑")
      fi
      if (( behind > 0 )); then
        tokens+=("${behind}↓")
      fi
    else
      symbol="✓"
    fi
  fi

  if (( dirty )); then
    tokens+=("*")
  fi

  _pl_s_branch="(${branch})"

  # The symbol is padded to two columns so that the counters line up.
  if [[ -n $symbol ]]; then
    if (( ${#tokens} )); then
      _pl_s_status="${(r:2:)symbol}  ${(j: :)tokens}"
    else
      _pl_s_status=$symbol
    fi
  elif (( ${#tokens} )); then
    _pl_s_status="${(j: :)tokens}"
  fi
}

_pl() {
  emulate -L zsh
  setopt local_options typeset_silent

  local workspace="${WORKSPACE_DIR:-$HOME/Workspace}"
  local -a entries
  local entry

  [[ -d $workspace ]] || return 1

  for entry in "$workspace"/*(N/); do
    entries+=("${entry:t}:directory")
  done

  (( ${#entries} )) || return 1
  _describe -t projects 'project' entries
}

if (( $+functions[compdef] )); then
  compdef _pl pl
fi
