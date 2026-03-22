#!/usr/bin/env bash
# tests/test_setup.sh - Test suite for claude-one-key-setup MVP
# Verifies acceptance criteria from REQUIREMENT.md
# Naming convention: test_[feature]_[scenario]_[expected_result]

set -euo pipefail

# Ensure local bin (for gh installed without root) is in PATH
export PATH="${HOME}/bin:${PATH}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="${REPO_ROOT}/setup.sh"
CONFIG_FILE="${REPO_ROOT}/claude-config.json"
PERMISSIONS_DIR="${REPO_ROOT}/permissions"

# Session 3: setup.sh writes to global ~/.claude/settings.json (req 2.2, 3.5)
SETTINGS_FILE="${HOME}/.claude/settings.json"

# ── Test harness ──────────────────────────────────────────────────────────────

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1 — $2"; FAIL=$((FAIL + 1)); }

# Setup: remove the global settings.json to get a clean state for each test group.
# We only remove the settings file (not the whole ~/.claude dir) to avoid
# clobbering other user config.
setup_clean_env() {
    rm -f "${SETTINGS_FILE}"
}

# ── TC Group 1: claude-config.json ────────────────────────────────────────────

echo ""
echo "=== TC-01..TC-07: claude-config.json ==="

# TC-01: File exists at well-known path
if [[ -f "$CONFIG_FILE" ]]; then
    pass "TC-01: claude-config.json exists at repo root"
else
    fail "TC-01: claude-config.json exists at repo root" "file not found"
fi

# TC-02: File is valid JSON
if jq empty "$CONFIG_FILE" 2>/dev/null; then
    pass "TC-02: claude-config.json is valid JSON"
else
    fail "TC-02: claude-config.json is valid JSON" "jq parse error"
fi

# TC-03: permissions/git.json contains Bash(cd * && git *) — permissions moved to subfiles (req 2.8)
git_perm_file="${PERMISSIONS_DIR}/git.json"
if [[ -f "$git_perm_file" ]]; then
    cd_git_entry=$(jq -r '.allow[]' "$git_perm_file" 2>/dev/null | grep -Fx "Bash(cd * && git *)" || true)
    if [[ -n "$cd_git_entry" ]]; then
        pass "TC-03: permissions/git.json contains Bash(cd * && git *)"
    else
        fail "TC-03: permissions/git.json contains Bash(cd * && git *)" "entry missing"
    fi
else
    fail "TC-03: permissions/git.json contains Bash(cd * && git *)" "file not found"
fi

# TC-04: Permission subfiles support allow/deny structure
if [[ -f "$git_perm_file" ]]; then
    has_deny=$(jq 'has("allow") and has("deny")' "$git_perm_file" 2>/dev/null)
    if [[ "$has_deny" == "true" ]]; then
        pass "TC-04: permission subfiles have allow/deny structure"
    else
        fail "TC-04: permission subfiles have allow/deny structure" "allow or deny key missing"
    fi
else
    fail "TC-04: permission subfiles have allow/deny structure" "git.json not found"
fi

# TC-05: Config supports model setting
has_model=$(jq 'has("model")' "$CONFIG_FILE" 2>/dev/null)
if [[ "$has_model" == "true" ]]; then
    pass "TC-05: config has model field"
else
    fail "TC-05: config has model field" "field missing"
fi

# TC-06: Config supports hooks field
has_hooks=$(jq 'has("hooks")' "$CONFIG_FILE" 2>/dev/null)
if [[ "$has_hooks" == "true" ]]; then
    pass "TC-06: config has hooks field"
else
    fail "TC-06: config has hooks field" "field missing"
fi

# TC-07: Config file is human-readable (pretty-printed JSON with indentation)
first_line=$(head -1 "$CONFIG_FILE")
if [[ "$first_line" == "{" ]]; then
    pass "TC-07: claude-config.json is human-readable (pretty-printed)"
else
    fail "TC-07: claude-config.json is human-readable" "not indented/pretty-printed"
fi

# ── TC Group 2: setup.sh basic functionality ──────────────────────────────────

echo ""
echo "=== TC-08..TC-15: setup.sh functionality ==="

# TC-08: Script exists and is executable
if [[ -x "$SETUP_SCRIPT" ]]; then
    pass "TC-08: setup.sh exists and is executable"
else
    fail "TC-08: setup.sh exists and is executable" "not executable or missing"
fi

# TC-09: Script references CONFIG_FILE (reads from config, not hardcoded)
if grep -q 'CONFIG_FILE' "$SETUP_SCRIPT" && grep -q 'claude-config.json' "$SETUP_SCRIPT"; then
    pass "TC-09: setup.sh reads from config file variable"
else
    fail "TC-09: setup.sh reads from config file variable" "no CONFIG_FILE reference"
fi

# TC-10: Script creates ~/.claude/settings.json when absent
setup_clean_env
output=$(bash "$SETUP_SCRIPT" 2>&1)
if [[ -f "$SETTINGS_FILE" ]]; then
    pass "TC-10: setup.sh creates ~/.claude/settings.json when absent"
else
    fail "TC-10: setup.sh creates ~/.claude/settings.json when absent" "file not created"
fi

# TC-11: Generated settings.json is valid JSON
if jq empty "$SETTINGS_FILE" 2>/dev/null; then
    pass "TC-11: generated settings.json is valid JSON"
else
    fail "TC-11: generated settings.json is valid JSON" "invalid JSON output"
fi

# TC-12: Generated settings.json contains Bash(cd * && git *) in allow-list
cd_git_in_output=$(jq -r '.permissions.allow[]' "$SETTINGS_FILE" 2>/dev/null | grep -Fx "Bash(cd * && git *)" || true)
if [[ -n "$cd_git_in_output" ]]; then
    pass "TC-12: output settings.json has Bash(cd * && git *) in allow"
else
    fail "TC-12: output settings.json has Bash(cd * && git *) in allow" "permission missing"
fi

# TC-13: Script provides clear output with recognizable prefixes
if echo "$output" | grep -qE '\[OK\]|\[INFO\]|\[WARN\]|\[ERROR\]'; then
    pass "TC-13: setup.sh provides clear labeled output"
else
    fail "TC-13: setup.sh provides clear labeled output" "no [OK]/[INFO] prefixes found"
fi

# TC-14: Script does not require root (verify it runs as non-root successfully)
if echo "$output" | grep -q '\[OK\]'; then
    pass "TC-14: setup.sh runs without root privileges"
else
    fail "TC-14: setup.sh runs without root privileges" "script failed"
fi

# TC-15: Script handles missing jq gracefully via ensure_dep (code inspection check)
if grep -q 'ensure_dep' "$SETUP_SCRIPT" && grep -q 'jq' "$SETUP_SCRIPT"; then
    pass "TC-15: setup.sh uses ensure_dep for jq dependency"
else
    fail "TC-15: setup.sh uses ensure_dep for jq dependency" "no ensure_dep/jq check found"
fi

# ── TC Group 3: Idempotency ───────────────────────────────────────────────────

echo ""
echo "=== TC-16..TC-17: Idempotency ==="

# TC-16: Running script twice produces identical settings.json
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1
content_run1=$(cat "$SETTINGS_FILE")
bash "$SETUP_SCRIPT" > /dev/null 2>&1
content_run2=$(cat "$SETTINGS_FILE")
if [[ "$content_run1" == "$content_run2" ]]; then
    pass "TC-16: idempotent — two runs produce identical settings.json"
else
    fail "TC-16: idempotent — two runs produce identical settings.json" "content differs between runs"
fi

# TC-17: Running 3x still produces same result
bash "$SETUP_SCRIPT" > /dev/null 2>&1
content_run3=$(cat "$SETTINGS_FILE")
if [[ "$content_run1" == "$content_run3" ]]; then
    pass "TC-17: idempotent — three runs produce identical settings.json"
else
    fail "TC-17: idempotent — three runs produce identical settings.json" "content differs on 3rd run"
fi

# ── TC Group 4: Merge behavior ────────────────────────────────────────────────

echo ""
echo "=== TC-18..TC-22: Merge behavior ==="

# TC-18: Script merges allow permissions (does not replace)
setup_clean_env
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(npm *)"],
    "deny": []
  }
}
EOF
bash "$SETUP_SCRIPT" > /dev/null 2>&1
merged_allow=$(jq -c '.permissions.allow | sort' "$SETTINGS_FILE")
has_npm=$(echo "$merged_allow" | jq 'contains(["Bash(npm *)"])')
has_cdgit=$(echo "$merged_allow" | jq 'contains(["Bash(cd * && git *)"])')
if [[ "$has_npm" == "true" && "$has_cdgit" == "true" ]]; then
    pass "TC-18: allow permissions merged (existing + config combined)"
else
    fail "TC-18: allow permissions merged" "existing=[$has_npm] cdgit=[$has_cdgit] merged_allow=$merged_allow"
fi

# TC-19: Script preserves existing deny list
setup_clean_env
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'EOF'
{
  "permissions": {
    "allow": [],
    "deny": ["Bash(rm -rf *)"]
  }
}
EOF
bash "$SETUP_SCRIPT" > /dev/null 2>&1
has_deny=$(jq '.permissions.deny | contains(["Bash(rm -rf *)"])' "$SETTINGS_FILE")
if [[ "$has_deny" == "true" ]]; then
    pass "TC-19: existing deny-list entry preserved after merge"
else
    fail "TC-19: existing deny-list entry preserved" "deny entry missing"
fi

# TC-20: Script preserves existing theme (not in config, should be kept)
setup_clean_env
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'EOF'
{
  "theme": "dark",
  "permissions": {"allow": [], "deny": []}
}
EOF
bash "$SETUP_SCRIPT" > /dev/null 2>&1
theme_val=$(jq -r '.theme // "missing"' "$SETTINGS_FILE")
if [[ "$theme_val" == "dark" ]]; then
    pass "TC-20: existing theme preserved when not declared in config"
else
    fail "TC-20: existing theme preserved" "theme was: $theme_val (expected: dark)"
fi

# TC-21: Model from config overrides existing model
setup_clean_env
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'EOF'
{
  "model": "claude-opus-4-6",
  "permissions": {"allow": [], "deny": []}
}
EOF
bash "$SETUP_SCRIPT" > /dev/null 2>&1
model_val=$(jq -r '.model' "$SETTINGS_FILE")
expected_model=$(jq -r '.model' "$CONFIG_FILE")
if [[ "$model_val" == "$expected_model" ]]; then
    pass "TC-21: config model overrides existing model"
else
    fail "TC-21: config model overrides existing model" "got $model_val, expected $expected_model"
fi

# TC-22: Hooks merged (existing + config; config wins on key collision)
setup_clean_env
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'EOF'
{
  "hooks": {"pre-commit": "echo user-hook"},
  "permissions": {"allow": [], "deny": []}
}
EOF
bash "$SETUP_SCRIPT" > /dev/null 2>&1
hook_val=$(jq -r '.hooks["pre-commit"] // "missing"' "$SETTINGS_FILE")
if [[ "$hook_val" == "echo user-hook" ]]; then
    pass "TC-22: existing hooks preserved when config hooks is empty"
else
    fail "TC-22: existing hooks preserved" "hook was: $hook_val"
fi

# ── TC Group 5: Error handling ────────────────────────────────────────────────

echo ""
echo "=== TC-23..TC-25: Error handling ==="

# TC-23: Script exits with error when config file missing
mv "$CONFIG_FILE" "${CONFIG_FILE}.bak"
err_output=$(bash "$SETUP_SCRIPT" 2>&1 || true)
exit_code=$?
mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
if echo "$err_output" | grep -q '\[ERROR\]'; then
    pass "TC-23: missing config file produces [ERROR] message and non-zero exit"
else
    fail "TC-23: missing config file produces error" "no [ERROR] in output"
fi

# TC-24: Script exits with error when config file has invalid JSON
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
echo "not-valid-json" > "$CONFIG_FILE"
err_output2=$(bash "$SETUP_SCRIPT" 2>&1 || true)
mv "${CONFIG_FILE}.bak" "$CONFIG_FILE"
if echo "$err_output2" | grep -q '\[ERROR\]'; then
    pass "TC-24: invalid JSON in config produces [ERROR] message"
else
    fail "TC-24: invalid JSON in config produces error" "no [ERROR] in output"
fi

# TC-25: Script handles corrupt settings.json gracefully (warns, starts fresh)
setup_clean_env
mkdir -p "$(dirname "$SETTINGS_FILE")"
echo "not-valid-json" > "$SETTINGS_FILE"
warn_output=$(bash "$SETUP_SCRIPT" 2>&1)
is_valid=$(jq empty "$SETTINGS_FILE" 2>/dev/null && echo "yes" || echo "no")
if echo "$warn_output" | grep -q '\[WARN\]' && [[ "$is_valid" == "yes" ]]; then
    pass "TC-25: corrupt settings.json triggers [WARN] and is overwritten with valid JSON"
else
    fail "TC-25: corrupt settings.json handled gracefully" "warn=${warn_output} valid=${is_valid}"
fi

# ── TC Group 6: Edit permission (req 2.5) ────────────────────────────────────

echo ""
echo "=== TC-26..TC-27: Edit permission (req 2.5) ==="

# TC-26: Edit(**/*) present in permissions/file-editing.json (permissions moved to subfiles, req 2.8)
edit_perm_file="${PERMISSIONS_DIR}/file-editing.json"
if [[ -f "$edit_perm_file" ]]; then
    edit_entry=$(jq -r '.allow[]' "$edit_perm_file" 2>/dev/null | grep -Fx 'Edit(**/*)'  || true)
    if [[ -n "$edit_entry" ]]; then
        pass "TC-26: permissions/file-editing.json contains Edit(**/*)"
    else
        fail "TC-26: permissions/file-editing.json contains Edit(**/*)" "entry missing"
    fi
else
    fail "TC-26: permissions/file-editing.json contains Edit(**/*)" "file not found"
fi

# TC-27: Edit(**/*) appears in generated settings.json after setup
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1
edit_in_output=$(jq -r '.permissions.allow[]' "$SETTINGS_FILE" 2>/dev/null | grep -Fx 'Edit(**/*)'  || true)
if [[ -n "$edit_in_output" ]]; then
    pass "TC-27: generated settings.json contains Edit(**/*)"
else
    fail "TC-27: generated settings.json contains Edit(**/*)" "permission missing from output"
fi

# ── TC Group 7: GH Actions config & hook wiring (req 2.6) ────────────────────

echo ""
echo "=== TC-28..TC-33: GH Actions monitoring (req 2.6) ==="

# TC-28: claude-config.json has gh_actions section with required fields
has_monitor=$(jq 'has("gh_actions") and (.gh_actions | has("monitor")) and (.gh_actions | has("poll_interval_seconds")) and (.gh_actions | has("timeout_minutes"))' "$CONFIG_FILE" 2>/dev/null)
if [[ "$has_monitor" == "true" ]]; then
    pass "TC-28: config has gh_actions section with monitor/poll_interval_seconds/timeout_minutes"
else
    fail "TC-28: config has gh_actions section" "required fields missing"
fi

# TC-29: PostToolUse hook referencing gh-actions-monitor.sh wired in claude-config.json
has_hook=$(jq '.hooks.PostToolUse // [] | .[0].hooks[0].command // ""' "$CONFIG_FILE" 2>/dev/null | grep -q 'gh-actions-monitor.sh' && echo "true" || echo "false")
if [[ "$has_hook" == "true" ]]; then
    pass "TC-29: PostToolUse hook references gh-actions-monitor.sh in claude-config.json"
else
    fail "TC-29: PostToolUse hook references gh-actions-monitor.sh" "hook not found or command mismatch"
fi

# TC-30: Monitor script exists and is executable
MONITOR_SCRIPT="${REPO_ROOT}/scripts/gh-actions-monitor.sh"
if [[ -x "$MONITOR_SCRIPT" ]]; then
    pass "TC-30: scripts/gh-actions-monitor.sh exists and is executable"
else
    fail "TC-30: scripts/gh-actions-monitor.sh exists and is executable" "missing or not executable"
fi

# TC-31: Monitor script exits 0 (no-op) for non-push bash commands
non_push_input='{"tool_input": {"command": "ls -la"}}'
exit_code=0
echo "$non_push_input" | bash "$MONITOR_SCRIPT" > /dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    pass "TC-31: monitor script exits 0 (no-op) for non-push commands"
else
    fail "TC-31: monitor script exits 0 for non-push commands" "exit code: $exit_code"
fi

# TC-32: Monitor script reads poll_interval and timeout from config (code inspection)
if grep -q 'poll_interval_seconds' "$MONITOR_SCRIPT" && grep -q 'timeout_minutes' "$MONITOR_SCRIPT"; then
    pass "TC-32: monitor script references poll_interval_seconds and timeout_minutes from config"
else
    fail "TC-32: monitor script reads config interval/timeout" "config references missing"
fi

# TC-33: {SCRIPT_DIR} placeholder is resolved in hook command written to settings.json
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1
hook_cmd=$(jq -r '.hooks.PostToolUse[0].hooks[0].command // ""' "$SETTINGS_FILE" 2>/dev/null)
if echo "$hook_cmd" | grep -q '{SCRIPT_DIR}'; then
    fail "TC-33: {SCRIPT_DIR} placeholder resolved in settings.json hook command" "placeholder still present: $hook_cmd"
elif [[ -z "$hook_cmd" ]]; then
    fail "TC-33: {SCRIPT_DIR} placeholder resolved in settings.json hook command" "hook command not found in settings.json"
else
    pass "TC-33: {SCRIPT_DIR} placeholder resolved to absolute path in settings.json"
fi

# ── TC Group 8: Branch cleanup config (req 2.7) ───────────────────────────────

echo ""
echo "=== TC-34..TC-36: Branch cleanup (req 2.7) ==="

# TC-34: claude-config.json has branch_cleanup.delete_on_merge field
has_branch_cleanup=$(jq 'has("branch_cleanup") and (.branch_cleanup | has("delete_on_merge"))' "$CONFIG_FILE" 2>/dev/null)
if [[ "$has_branch_cleanup" == "true" ]]; then
    pass "TC-34: config has branch_cleanup.delete_on_merge field"
else
    fail "TC-34: config has branch_cleanup.delete_on_merge field" "field missing"
fi

# TC-35: setup.sh reports GH Actions monitoring status in summary output
setup_clean_env
summary_output=$(bash "$SETUP_SCRIPT" 2>&1)
if echo "$summary_output" | grep -qi 'GH Actions'; then
    pass "TC-35: setup.sh reports GH Actions monitoring status in summary"
else
    fail "TC-35: setup.sh reports GH Actions monitoring status" "no GH Actions line in output"
fi

# TC-36: setup.sh reports branch cleanup status in summary output
if echo "$summary_output" | grep -qi 'Branch cleanup'; then
    pass "TC-36: setup.sh reports branch cleanup status in summary"
else
    fail "TC-36: setup.sh reports branch cleanup status" "no Branch cleanup line in output"
fi

# ── TC Group 9: Global settings target (req 2.2, 3.5) ────────────────────────

echo ""
echo "=== TC-37..TC-39: Global settings target (req 2.2, 3.5) ==="

# TC-37: setup.sh targets $HOME/.claude/settings.json (global, not project-level)
if grep -q 'HOME.*\.claude' "$SETUP_SCRIPT" || grep -q '\$HOME' "$SETUP_SCRIPT"; then
    if ! grep -q 'SCRIPT_DIR.*\.claude' "$SETUP_SCRIPT"; then
        pass "TC-37: setup.sh targets \$HOME/.claude (global settings)"
    else
        fail "TC-37: setup.sh targets \$HOME/.claude (global settings)" "SCRIPT_DIR/.claude reference found — still writing to project dir"
    fi
else
    fail "TC-37: setup.sh targets \$HOME/.claude (global settings)" "\$HOME reference not found"
fi

# TC-38: After running setup.sh, global settings file exists
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1
if [[ -f "$SETTINGS_FILE" ]]; then
    pass "TC-38: global settings file created at ~/.claude/settings.json"
else
    fail "TC-38: global settings file created at ~/.claude/settings.json" "file not found: $SETTINGS_FILE"
fi

# TC-39: After running setup.sh, project-level .claude/settings.json is NOT created
project_settings="${REPO_ROOT}/.claude/settings.json"
# Run fresh to ensure we only check what this run produces
setup_clean_env
rm -f "$project_settings"
bash "$SETUP_SCRIPT" > /dev/null 2>&1
if [[ ! -f "$project_settings" ]]; then
    pass "TC-39: setup.sh does NOT write to project-level .claude/settings.json"
else
    fail "TC-39: setup.sh does NOT write to project-level .claude/settings.json" "project-level file was created"
fi

# ── TC Group 10: Permission subfiles (req 2.8) ───────────────────────────────

echo ""
echo "=== TC-40..TC-46: Permission subfiles (req 2.8) ==="

# TC-40: permissions/ directory exists
if [[ -d "$PERMISSIONS_DIR" ]]; then
    pass "TC-40: permissions/ directory exists"
else
    fail "TC-40: permissions/ directory exists" "directory not found"
fi

# TC-41: permissions/git.json exists and is valid JSON with allow/deny
git_perm="${PERMISSIONS_DIR}/git.json"
if [[ -f "$git_perm" ]] && jq empty "$git_perm" 2>/dev/null && jq -e 'has("allow") and has("deny")' "$git_perm" >/dev/null 2>&1; then
    pass "TC-41: permissions/git.json exists, is valid JSON, has allow/deny keys"
else
    fail "TC-41: permissions/git.json exists, is valid JSON, has allow/deny keys" "file missing, invalid, or missing keys"
fi

# TC-42: permissions/file-editing.json exists and is valid JSON with allow/deny
edit_perm="${PERMISSIONS_DIR}/file-editing.json"
if [[ -f "$edit_perm" ]] && jq empty "$edit_perm" 2>/dev/null && jq -e 'has("allow") and has("deny")' "$edit_perm" >/dev/null 2>&1; then
    pass "TC-42: permissions/file-editing.json exists, is valid JSON, has allow/deny keys"
else
    fail "TC-42: permissions/file-editing.json exists, is valid JSON, has allow/deny keys" "file missing, invalid, or missing keys"
fi

# TC-43: setup.sh auto-discovers subfiles without hardcoded list (code inspection)
if grep -q 'permissions.*\*\.json\|PERMISSIONS_DIR.*\*.json' "$SETUP_SCRIPT"; then
    pass "TC-43: setup.sh auto-discovers subfiles via glob (no hardcoded list)"
else
    fail "TC-43: setup.sh auto-discovers subfiles via glob" "no glob discovery pattern found"
fi

# TC-44: All permissions from subfiles appear in generated settings.json
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1
all_subfile_perms=()
for pfile in "${PERMISSIONS_DIR}"/*.json; do
    while IFS= read -r perm; do
        all_subfile_perms+=("$perm")
    done < <(jq -r '.allow[]?' "$pfile" 2>/dev/null || true)
done
all_pass=true
for perm in "${all_subfile_perms[@]}"; do
    found=$(jq -r '.permissions.allow[]' "$SETTINGS_FILE" 2>/dev/null | grep -Fx "$perm" || true)
    if [[ -z "$found" ]]; then
        fail "TC-44: all subfile permissions appear in generated settings.json" "missing: $perm"
        all_pass=false
        break
    fi
done
if [[ "$all_pass" == "true" ]]; then
    pass "TC-44: all subfile permissions appear in generated settings.json"
fi

# TC-45: No duplicate permissions in generated settings.json (dedup enforcement)
total_count=$(jq '.permissions.allow | length' "$SETTINGS_FILE" 2>/dev/null)
unique_count=$(jq '.permissions.allow | unique | length' "$SETTINGS_FILE" 2>/dev/null)
if [[ "$total_count" == "$unique_count" ]]; then
    pass "TC-45: no duplicate permissions in generated settings.json"
else
    fail "TC-45: no duplicate permissions in generated settings.json" "total=$total_count unique=$unique_count"
fi

# TC-46: Adding a new subfile is auto-discovered without script changes
# Create a temp subfile, run setup, verify its permission appears, then clean up
tmp_perm="${PERMISSIONS_DIR}/test-tmp-perm.json"
cat > "$tmp_perm" <<'TMPEOF'
{
  "description": "Temp test permission",
  "allow": ["Bash(echo test-only *)"],
  "deny": []
}
TMPEOF
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1
tmp_found=$(jq -r '.permissions.allow[]' "$SETTINGS_FILE" 2>/dev/null | grep -Fx "Bash(echo test-only *)" || true)
rm -f "$tmp_perm"
if [[ -n "$tmp_found" ]]; then
    pass "TC-46: new permission subfile auto-discovered without script changes"
else
    fail "TC-46: new permission subfile auto-discovered without script changes" "new permission not found in output"
fi

# ── TC Group 11: Dependency auto-install (req 2.9) ───────────────────────────

echo ""
echo "=== TC-47..TC-51: Dependency auto-install (req 2.9) ==="

# TC-47: claude-config.json declares dependencies field
has_deps=$(jq 'has("dependencies")' "$CONFIG_FILE" 2>/dev/null)
if [[ "$has_deps" == "true" ]]; then
    pass "TC-47: claude-config.json has dependencies field"
else
    fail "TC-47: claude-config.json has dependencies field" "field missing"
fi

# TC-48: dependencies field includes jq and gh
has_jq=$(jq '.dependencies | contains(["jq"])' "$CONFIG_FILE" 2>/dev/null)
has_gh=$(jq '.dependencies | contains(["gh"])' "$CONFIG_FILE" 2>/dev/null)
if [[ "$has_jq" == "true" && "$has_gh" == "true" ]]; then
    pass "TC-48: dependencies includes jq and gh"
else
    fail "TC-48: dependencies includes jq and gh" "jq=$has_jq gh=$has_gh"
fi

# TC-49: setup.sh bootstraps jq before reading config (chicken-and-egg check)
# Verify ensure_dep jq appears before the config read in the script
jq_line=$(grep -n 'ensure_dep jq' "$SETUP_SCRIPT" | head -1 | cut -d: -f1)
config_read_line=$(grep -n '\-f.*CONFIG_FILE' "$SETUP_SCRIPT" | head -1 | cut -d: -f1)
if [[ -n "$jq_line" && -n "$config_read_line" && "$jq_line" -lt "$config_read_line" ]]; then
    pass "TC-49: jq bootstrapped (ensure_dep jq) before config file is parsed"
else
    fail "TC-49: jq bootstrapped before config file is parsed" "jq_line=$jq_line config_read_line=$config_read_line"
fi

# TC-50: setup.sh installs deps from config's dependencies array (not hardcoded)
if grep -q 'dependencies\[\]\?' "$SETUP_SCRIPT" || grep -q "dependencies\[\]" "$SETUP_SCRIPT"; then
    pass "TC-50: setup.sh reads dependencies list from config (not hardcoded)"
else
    fail "TC-50: setup.sh reads dependencies list from config (not hardcoded)" "no config dependencies read found"
fi

# TC-51: detect_pkg_mgr supports brew/apt/dnf/yum (code inspection)
if grep -q 'brew' "$SETUP_SCRIPT" && grep -q 'apt' "$SETUP_SCRIPT" && grep -q 'dnf' "$SETUP_SCRIPT" && grep -q 'yum' "$SETUP_SCRIPT"; then
    pass "TC-51: detect_pkg_mgr supports brew/apt/dnf/yum"
else
    fail "TC-51: detect_pkg_mgr supports brew/apt/dnf/yum" "one or more package managers missing"
fi

# ── TC Group 12: maybe_sudo() sudo-less container support (req 2.9, Session 4) ──

echo ""
echo "=== TC-52..TC-54: maybe_sudo() sudo-less container support (req 2.9) ==="

# TC-52: maybe_sudo() function exists in setup.sh (code inspection)
if grep -q 'maybe_sudo()' "$SETUP_SCRIPT"; then
    pass "TC-52: maybe_sudo() helper function exists in setup.sh"
else
    fail "TC-52: maybe_sudo() helper function exists in setup.sh" "function not found"
fi

# TC-53: install_dep() uses maybe_sudo (not hardcoded sudo) for apt/dnf/yum
apt_uses_maybe=$(grep 'apt-get install' "$SETUP_SCRIPT" | grep 'maybe_sudo' || true)
dnf_uses_maybe=$(grep 'dnf install' "$SETUP_SCRIPT" | grep 'maybe_sudo' || true)
yum_uses_maybe=$(grep 'yum install' "$SETUP_SCRIPT" | grep 'maybe_sudo' || true)
if [[ -n "$apt_uses_maybe" && -n "$dnf_uses_maybe" && -n "$yum_uses_maybe" ]]; then
    pass "TC-53: install_dep() uses maybe_sudo for apt/dnf/yum (not hardcoded sudo)"
else
    fail "TC-53: install_dep() uses maybe_sudo for apt/dnf/yum" "apt=${apt_uses_maybe:-missing} dnf=${dnf_uses_maybe:-missing} yum=${yum_uses_maybe:-missing}"
fi

# TC-54: maybe_sudo() runs as root (uid 0) without sudo, uses sudo when available,
#        and falls back to direct execution otherwise (code inspection of three branches)
has_uid_zero=$(grep -A2 'maybe_sudo()' "$SETUP_SCRIPT" | grep -c 'id -u.*-eq 0\|eq 0.*id -u' || grep -c '"$(id -u)" -eq 0' "$SETUP_SCRIPT" || true)
has_sudo_branch=$(grep 'command -v sudo' "$SETUP_SCRIPT" | head -1 || true)
if [[ -n "$has_sudo_branch" ]] && grep -q '"$(id -u)" -eq 0' "$SETUP_SCRIPT"; then
    pass "TC-54: maybe_sudo() has root-check and sudo-check branches"
else
    fail "TC-54: maybe_sudo() has root-check and sudo-check branches" "one or more branches missing"
fi

# ── Cleanup & summary ─────────────────────────────────────────────────────────

# Restore a clean working settings.json
setup_clean_env
bash "$SETUP_SCRIPT" > /dev/null 2>&1

echo ""
echo "=============================================="
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "=============================================="
echo ""

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
