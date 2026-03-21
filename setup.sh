#!/usr/bin/env bash
# setup.sh - One-key Claude Code configuration setup
# Reads claude-config.json and applies settings to .claude/settings.json
# Idempotent: safe to run multiple times

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/claude-config.json"
CLAUDE_DIR="${SCRIPT_DIR}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
warn()  { echo "[WARN]  $*"; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

# ── Preflight checks ─────────────────────────────────────────────────────────

command -v jq >/dev/null 2>&1 || die "'jq' is required but not installed. Install it with: brew install jq  OR  apt-get install jq"

[[ -f "$CONFIG_FILE" ]] || die "Configuration file not found: $CONFIG_FILE"

info "Reading configuration from: $CONFIG_FILE"

# Validate that the config file is valid JSON
jq empty "$CONFIG_FILE" 2>/dev/null || die "Invalid JSON in $CONFIG_FILE"

# ── Prepare target directory ──────────────────────────────────────────────────

if [[ ! -d "$CLAUDE_DIR" ]]; then
    mkdir -p "$CLAUDE_DIR"
    info "Created directory: $CLAUDE_DIR"
fi

# ── Load or initialise settings.json ─────────────────────────────────────────

if [[ -f "$SETTINGS_FILE" ]]; then
    info "Existing settings found: $SETTINGS_FILE"
    # Validate existing file; if corrupt, start fresh
    if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
        warn "Existing settings.json is invalid JSON — starting fresh"
        existing='{}'
    else
        existing="$(cat "$SETTINGS_FILE")"
    fi
else
    info "No existing settings.json — will create one"
    existing='{}'
fi

# ── Merge permissions ─────────────────────────────────────────────────────────

merge_list() {
    # Return the union of two JSON arrays (deduplicated), preserving order.
    # Usage: merge_list <existing_json_array> <new_json_array>
    local existing_arr="$1"
    local new_arr="$2"
    jq -cn --argjson e "$existing_arr" --argjson n "$new_arr" \
        '($e + $n) | unique'
}

# Extract existing permission lists (default to empty arrays if absent)
existing_allow="$(echo "$existing" | jq -c '.permissions.allow // []')"
existing_deny="$(echo "$existing"  | jq -c '.permissions.deny  // []')"

# Extract config permission lists
config_allow="$(jq -c '.permissions.allow // []' "$CONFIG_FILE")"
config_deny="$(jq  -c '.permissions.deny  // []' "$CONFIG_FILE")"

merged_allow="$(merge_list "$existing_allow" "$config_allow")"
merged_deny="$(merge_list  "$existing_deny"  "$config_deny")"

# ── Merge top-level scalar settings ──────────────────────────────────────────
# Config values override existing values for fields that are explicitly set in
# claude-config.json (i.e. not null/missing).  Fields not mentioned in the
# config are left untouched.

merged_settings="$(
    jq -cn \
        --argjson existing "$existing" \
        --argjson config "$(cat "$CONFIG_FILE")" \
        --argjson allow  "$merged_allow" \
        --argjson deny   "$merged_deny" \
    '
    # Start from existing settings
    $existing

    # Apply config scalar fields (model, theme, …) — only when present in config
    | if ($config | has("model"))  then .model  = $config.model  else . end
    | if ($config | has("theme"))  then .theme  = $config.theme  else . end

    # Merge hooks: existing hooks + config hooks (config wins on key collisions)
    | .hooks = (($existing.hooks // {}) + ($config.hooks // {}))

    # Apply merged permission lists
    | .permissions.allow = $allow
    | .permissions.deny  = $deny
    '
)"

# ── Write result ──────────────────────────────────────────────────────────────

echo "$merged_settings" | jq '.' > "$SETTINGS_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
ok "Claude Code configuration applied successfully."
echo ""
echo "  Settings file : $SETTINGS_FILE"
echo ""
echo "  Permissions (allow):"
echo "$merged_allow" | jq -r '.[]' | sed 's/^/    • /'
echo ""
echo "  Permissions (deny):"
deny_count="$(echo "$merged_deny" | jq 'length')"
if [[ "$deny_count" -eq 0 ]]; then
    echo "    (none)"
else
    echo "$merged_deny" | jq -r '.[]' | sed 's/^/    • /'
fi
echo ""

model_val="$(echo "$merged_settings" | jq -r '.model // "(not set)"')"
echo "  Model         : $model_val"
echo ""
info "Run 'claude' to start a fully configured session."
