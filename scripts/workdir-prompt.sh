#!/usr/bin/env bash
# workdir-prompt.sh - UserPromptSubmit hook
#
# Emits a working directory reminder when default_working_dir is configured in
# ~/.claude/settings.json. Claude Code prepends this script's stdout to the
# user's prompt context, ensuring Claude always scopes operations to the
# configured directory regardless of where 'claude' was launched from.

SETTINGS_FILE="${HOME}/.claude/settings.json"

[[ -f "$SETTINGS_FILE" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

workdir="$(jq -r '.default_working_dir // empty' "$SETTINGS_FILE" 2>/dev/null)"
[[ -z "$workdir" ]] && exit 0

echo "Note: Default working directory is '${workdir}'. Resolve all file paths, git commands, and shell operations relative to this directory. If not already there, begin with: cd ${workdir}"
