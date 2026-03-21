#!/usr/bin/env bash
# gh-actions-monitor.sh - PostToolUse hook: monitors GitHub Actions after push/PR operations
#
# Claude Code calls this script after every Bash tool use.
# The script reads the tool context from stdin (JSON), checks whether the command
# triggered a GitHub Actions workflow (git push, gh pr create/merge), and if so
# polls the run until it reaches a terminal state.
#
# Output is fed back into the conversation so Claude can report the final status.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../claude-config.json"

# ── Read hook context from stdin ──────────────────────────────────────────────

hook_input="$(cat)"

# Extract the bash command that was executed
bash_cmd="$(echo "$hook_input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")"

# Only proceed if the command involved a git push or gh pr operation
if ! echo "$bash_cmd" | grep -qE '(git push|gh pr (create|merge|edit))'; then
    exit 0
fi

# ── Load configuration ────────────────────────────────────────────────────────

poll_interval=15
timeout_minutes=30
monitor_enabled=true

if [[ -f "$CONFIG_FILE" ]]; then
    monitor_enabled="$(jq -r '.gh_actions.monitor // true' "$CONFIG_FILE")"
    poll_interval="$(jq -r '.gh_actions.poll_interval_seconds // 15' "$CONFIG_FILE")"
    timeout_minutes="$(jq -r '.gh_actions.timeout_minutes // 30' "$CONFIG_FILE")"
fi

if [[ "$monitor_enabled" != "true" ]]; then
    exit 0
fi

# ── Check gh CLI availability ─────────────────────────────────────────────────

if ! command -v gh >/dev/null 2>&1; then
    echo "[GH Actions Monitor] 'gh' CLI not found — skipping workflow monitoring."
    exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "[GH Actions Monitor] 'gh' CLI not authenticated — skipping workflow monitoring."
    exit 0
fi

# ── Wait briefly for GH Actions to register the run ──────────────────────────

echo ""
echo "[GH Actions Monitor] Push/PR operation detected. Checking for workflow runs..."
sleep 5

# ── Find the most recent workflow run ─────────────────────────────────────────

run_id="$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")"

if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    echo "[GH Actions Monitor] No workflow runs found — nothing to monitor."
    exit 0
fi

run_name="$(gh run list --limit 1 --json name --jq '.[0].name' 2>/dev/null || echo "unknown")"
echo "[GH Actions Monitor] Monitoring workflow run #${run_id} (${run_name})..."

# ── Poll until terminal state or timeout ──────────────────────────────────────

timeout_seconds=$((timeout_minutes * 60))
elapsed=0

while true; do
    run_data="$(gh run view "$run_id" --json status,conclusion,name 2>/dev/null || echo '{}')"
    run_status="$(echo "$run_data" | jq -r '.status // "unknown"')"
    conclusion="$(echo "$run_data"  | jq -r '.conclusion // ""')"

    if [[ "$run_status" == "completed" ]]; then
        echo ""
        case "$conclusion" in
            success)
                echo "[GH Actions Monitor] Workflow completed: SUCCESS" ;;
            failure)
                echo "[GH Actions Monitor] Workflow completed: FAILURE" ;;
            cancelled)
                echo "[GH Actions Monitor] Workflow completed: CANCELLED" ;;
            skipped)
                echo "[GH Actions Monitor] Workflow completed: SKIPPED" ;;
            *)
                echo "[GH Actions Monitor] Workflow completed: ${conclusion}" ;;
        esac
        echo "[GH Actions Monitor] Run URL: $(gh run view "$run_id" --json url --jq '.url' 2>/dev/null || echo 'n/a')"
        exit 0
    fi

    if [[ $elapsed -ge $timeout_seconds ]]; then
        echo ""
        echo "[GH Actions Monitor] Timeout (${timeout_minutes}m) reached. Current status: ${run_status}"
        echo "[GH Actions Monitor] Monitor manually: gh run view ${run_id}"
        exit 0
    fi

    echo "[GH Actions Monitor] Status: ${run_status} — next check in ${poll_interval}s (${elapsed}s elapsed / ${timeout_seconds}s max)"
    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
done
