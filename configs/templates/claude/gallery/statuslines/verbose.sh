#!/usr/bin/env bash
# statusline: verbose
# Shows: directory, git branch, git status flags, model, context usage, and wall clock.
# Good for large monitors or focused work sessions where you want maximum visibility.

input=$(cat)

cwd=$(echo "$input"   | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input"  | jq -r '.context_window.used_percentage // empty')

cwd="${cwd/#$HOME/~}"

# Git branch + dirty flag
branch=""
git_root=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')
if git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$git_root" symbolic-ref --short HEAD 2>/dev/null); then
  dirty=""
  if ! GIT_OPTIONAL_LOCKS=0 git -C "$git_root" diff --quiet 2>/dev/null || \
     ! GIT_OPTIONAL_LOCKS=0 git -C "$git_root" diff --cached --quiet 2>/dev/null; then
    dirty="*"
  fi
  branch=" [$git_branch${dirty}]"
fi

# Context with color warning when high
ctx=""
if [ -n "$used" ]; then
  used_int=${used%.*}
  if [ "$used_int" -ge 80 ]; then
    ctx=" | ctx:${used_int}% (!)"
  else
    ctx=" | ctx:${used_int}%"
  fi
fi

# Wall clock
clock=$(date "+%H:%M")

printf "%s%s | %s%s | %s" "$cwd" "$branch" "$model" "$ctx" "$clock"
