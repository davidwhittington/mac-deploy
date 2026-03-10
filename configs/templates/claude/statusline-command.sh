#!/usr/bin/env bash
# ~/.claude/statusline-command.sh
# Claude Code status line — shows working directory, git branch, model, context usage.
#
# Part of mac-deploy. Source: configs/templates/claude/statusline-command.sh
# To use a different layout, swap this file for one from gallery/statuslines/.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten home directory
cwd="${cwd/#$HOME/~}"

# Git branch (non-blocking)
branch=""
if git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."')" \
    symbolic-ref --short HEAD 2>/dev/null); then
  branch=" [$git_branch]"
fi

# Context usage
ctx=""
if [ -n "$used" ]; then
  used_int=${used%.*}
  ctx=" | ctx:${used_int}%"
fi

printf "%s%s | %s%s" "$cwd" "$branch" "$model" "$ctx"
