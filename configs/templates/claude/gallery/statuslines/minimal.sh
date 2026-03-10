#!/usr/bin/env bash
# statusline: minimal
# Shows: directory and git branch only. No model, no context.
# Good for small terminals or when you want a clean, quiet status line.

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
cwd="${cwd/#$HOME/~}"

branch=""
if git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')" \
    symbolic-ref --short HEAD 2>/dev/null); then
  branch=" [$git_branch]"
fi

printf "%s%s" "$cwd" "$branch"
