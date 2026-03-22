#!/usr/bin/env bash
# setup.sh - One-key Claude Code configuration setup
# Reads claude-config.json and permission subfiles, applies settings to
# ~/.claude/settings.json (global user-level).
# Idempotent: safe to run multiple times.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/claude-config.json"
PERMISSIONS_DIR="${SCRIPT_DIR}/permissions"

# Global Claude settings target (req 2.2, 3.5)
CLAUDE_DIR="${HOME}/.claude"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
warn()  { echo "[WARN]  $*"; }
die()   { echo "[ERROR] $*" >&2; exit 1; }

# ── Dependency pre-check and auto-install (req 2.9) ──────────────────────────

# Detect the available system package manager.
detect_pkg_mgr() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        command -v brew >/dev/null 2>&1 && echo "brew" || echo "none"
        return
    fi
    # Linux: inspect /etc/os-release for distro-specific manager
    if [[ -f /etc/os-release ]]; then
        local os_id
        os_id="$(. /etc/os-release && echo "${ID:-}")"
        case "$os_id" in
            debian|ubuntu|linuxmint|raspbian) echo "apt"; return ;;
            fedora)                           echo "dnf"; return ;;
            rhel|centos|rocky|almalinux)
                command -v dnf >/dev/null 2>&1 && echo "dnf" || echo "yum"
                return ;;
        esac
    fi
    # Fallback: probe known package managers
    if   command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v yum     >/dev/null 2>&1; then echo "yum"
    else echo "none"
    fi
}

# Run a command with privilege escalation when needed.
# - As root (uid 0): run directly (no sudo needed)
# - sudo available: prefix with sudo
# - Neither: run directly (will fail if privileges are truly required)
maybe_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

# Install a single dependency using the detected package manager.
install_dep() {
    local dep="$1"
    local pkg_mgr
    pkg_mgr="$(detect_pkg_mgr)"
    info "Installing '$dep' via ${pkg_mgr}..."
    case "$pkg_mgr" in
        brew) brew install "$dep" ;;
        apt)  maybe_sudo apt-get install -y "$dep" ;;
        dnf)  maybe_sudo dnf install -y "$dep" ;;
        yum)  maybe_sudo yum install -y "$dep" ;;
        none)
            echo "[ERROR] No supported package manager found (tried brew/apt/dnf/yum)." >&2
            echo "[ERROR] Install '$dep' manually, then re-run setup.sh:" >&2
            echo "[ERROR]   macOS  : brew install $dep" >&2
            echo "[ERROR]   Debian : sudo apt-get install $dep" >&2
            echo "[ERROR]   Fedora : sudo dnf install $dep" >&2
            return 1 ;;
    esac
}

# Ensure a dependency is present; auto-install if missing.
ensure_dep() {
    local dep="$1"
    if ! command -v "$dep" >/dev/null 2>&1; then
        warn "Required dependency '$dep' not found — attempting auto-install"
        if ! install_dep "$dep"; then
            die "Auto-install of '$dep' failed. Please install it manually and re-run."
        fi
        ok "Installed: $dep"
    fi
}

# jq must be available before we can parse the config file for the full
# dependency list, so check/install it first (hardcoded bootstrap step).
ensure_dep jq

# ── Config validation ─────────────────────────────────────────────────────────

[[ -f "$CONFIG_FILE" ]] || die "Configuration file not found: $CONFIG_FILE"
jq empty "$CONFIG_FILE" 2>/dev/null || die "Invalid JSON in $CONFIG_FILE"
info "Reading configuration from: $CONFIG_FILE"

# Install any additional dependencies declared in the config file (req 2.9).
info "Checking required dependencies..."
while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    ensure_dep "$dep"
done < <(jq -r '.dependencies[]?' "$CONFIG_FILE" 2>/dev/null || true)

# ── Prepare target directory ──────────────────────────────────────────────────

if [[ ! -d "$CLAUDE_DIR" ]]; then
    mkdir -p "$CLAUDE_DIR"
    info "Created directory: $CLAUDE_DIR"
fi

# ── Load or initialise settings.json ─────────────────────────────────────────

if [[ -f "$SETTINGS_FILE" ]]; then
    info "Existing settings found: $SETTINGS_FILE"
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

# ── Helpers: merge JSON arrays ────────────────────────────────────────────────

merge_list() {
    # Return the union of two JSON arrays (deduplicated), preserving order.
    local existing_arr="$1"
    local new_arr="$2"
    jq -cn --argjson e "$existing_arr" --argjson n "$new_arr" \
        '($e + $n) | unique'
}

# ── Load permissions from subfiles (req 2.8) ─────────────────────────────────
# Auto-discover all *.json files under permissions/ and merge their allow/deny
# entries. Adding a new permission requires only adding a subfile — no changes
# to this script.

config_allow='[]'
config_deny='[]'

if [[ -d "$PERMISSIONS_DIR" ]]; then
    subfile_count=0
    for pfile in "${PERMISSIONS_DIR}"/*.json; do
        [[ -f "$pfile" ]] || continue
        if ! jq empty "$pfile" 2>/dev/null; then
            warn "Invalid JSON in $pfile — skipping"
            continue
        fi
        file_allow="$(jq -c '.allow // []' "$pfile")"
        file_deny="$(jq  -c '.deny  // []' "$pfile")"
        config_allow="$(merge_list "$config_allow" "$file_allow")"
        config_deny="$(merge_list  "$config_deny"  "$file_deny")"
        subfile_count=$((subfile_count + 1))
    done
    info "Loaded permissions from ${subfile_count} subfile(s) in permissions/"
else
    info "No permissions/ directory found — checking claude-config.json for permissions"
fi

# Also include any permissions declared directly in claude-config.json
# (supports legacy usage and manual overrides).
extra_allow="$(jq -c '.permissions.allow // []' "$CONFIG_FILE")"
extra_deny="$(jq  -c '.permissions.deny  // []' "$CONFIG_FILE")"
config_allow="$(merge_list "$config_allow" "$extra_allow")"
config_deny="$(merge_list  "$config_deny"  "$extra_deny")"

# ── Merge with existing settings ──────────────────────────────────────────────

existing_allow="$(echo "$existing" | jq -c '.permissions.allow // []')"
existing_deny="$(echo "$existing"  | jq -c '.permissions.deny  // []')"

merged_allow="$(merge_list "$existing_allow" "$config_allow")"
merged_deny="$(merge_list  "$existing_deny"  "$config_deny")"

# ── Merge top-level scalar settings ──────────────────────────────────────────
# Config values override existing values for fields explicitly set in
# claude-config.json. Fields not mentioned in the config are left untouched.

merged_settings="$(
    jq -cn \
        --argjson existing "$existing" \
        --argjson config "$(cat "$CONFIG_FILE")" \
        --argjson allow  "$merged_allow" \
        --argjson deny   "$merged_deny" \
    '
    $existing
    | if ($config | has("model")) then .model = $config.model else . end
    | if ($config | has("theme")) then .theme = $config.theme else . end
    | .hooks = (($existing.hooks // {}) + ($config.hooks // {}))
    | .permissions.allow = $allow
    | .permissions.deny  = $deny
    '
)"

# ── Resolve {SCRIPT_DIR} placeholder in hook commands ────────────────────────

merged_settings="$(echo "$merged_settings" | sed "s|{SCRIPT_DIR}|${SCRIPT_DIR}|g")"

# ── Configure branch cleanup (delete_branch_on_merge) ────────────────────────

branch_cleanup_enabled="$(jq -r '.branch_cleanup.delete_on_merge // false' "$CONFIG_FILE")"

if [[ "$branch_cleanup_enabled" == "true" ]]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")"
        if [[ -n "$repo" ]]; then
            if gh api "repos/${repo}" --method PATCH \
                --field delete_branch_on_merge=true \
                --silent 2>/dev/null; then
                ok "GitHub repo '${repo}' configured: delete_branch_on_merge=true"
            else
                warn "Could not set delete_branch_on_merge on '${repo}' (insufficient permissions?). Configure manually in repo Settings → General."
            fi
        else
            warn "Could not detect GitHub repository. Skipping delete_branch_on_merge configuration."
        fi
    else
        warn "'gh' CLI not available or not authenticated. Skipping delete_branch_on_merge configuration."
        info "To configure manually: gh api repos/<owner>/<repo> --method PATCH --field delete_branch_on_merge=true"
    fi
fi

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

gh_monitor="$(jq -r '.gh_actions.monitor // false' "$CONFIG_FILE")"
gh_interval="$(jq -r '.gh_actions.poll_interval_seconds // 15' "$CONFIG_FILE")"
gh_timeout="$(jq -r '.gh_actions.timeout_minutes // 30' "$CONFIG_FILE")"
if [[ "$gh_monitor" == "true" ]]; then
    echo "  GH Actions    : monitoring enabled (poll every ${gh_interval}s, timeout ${gh_timeout}m)"
else
    echo "  GH Actions    : monitoring disabled"
fi

if [[ "$branch_cleanup_enabled" == "true" ]]; then
    echo "  Branch cleanup: delete_branch_on_merge=true"
else
    echo "  Branch cleanup: disabled"
fi
echo ""

info "Run 'claude' to start a fully configured session."
