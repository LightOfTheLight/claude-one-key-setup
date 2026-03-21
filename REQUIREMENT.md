# Project Requirements

## 1. Overview

**Project Name:** claude-one-key-setup
**Project Type:** Developer Tooling / CLI Setup Script
**Target Users:** Developers and teams using Claude Code agents

### 1.1 Vision

Provide a single script that bootstraps all necessary Claude Code configuration in one step — permissions, settings, skills, and agent behavior — so any developer can start a fully-configured Claude session without manual setup.

### 1.2 Core Principles

- **One-command setup:** A single script invocation configures everything
- **Config-driven:** All settings and permissions are declared in a versioned configuration file (not hardcoded in the script)
- **Session-safe:** Permissions are applied at session start automatically, removing repetitive approval prompts for known-safe operations

---

## 2. Functional Requirements

### 2.1 Central Configuration File

**Description:** A single configuration file (e.g., `claude-config.json` or `claude-config.yaml`) that declares all Claude Code settings, permissions, and agent behavior in one place. This file is the single source of truth for setup.

**Acceptance Criteria:**
- [ ] Configuration file exists at a well-known path in the repository
- [ ] File supports declaring permissions (allow-list and deny-list)
- [ ] File supports declaring Claude Code settings (e.g., model, theme, hooks)
- [ ] File supports declaring agent-specific behavior or skill configuration
- [ ] File is human-readable and version-controllable

### 2.2 One-Key Setup Script

**Description:** A shell script (e.g., `setup.sh`) that reads the configuration file and applies all settings to the local Claude Code installation.

**Acceptance Criteria:**
- [ ] Running the script once fully configures Claude Code for the project
- [ ] Script reads from the central configuration file (not hardcoded values)
- [ ] Script creates or updates `.claude/settings.json` (or equivalent) with declared permissions and settings
- [ ] Script is idempotent — running it multiple times produces the same result
- [ ] Script provides clear output indicating what was configured

### 2.3 Auto-Grant Permissions at Session Start

**Description:** Permissions declared in the configuration file are automatically applied when starting a Claude session, eliminating manual approval prompts for pre-approved operations.

**Acceptance Criteria:**
- [ ] Configured permissions are written to `.claude/settings.json` `permissions.allow` list
- [ ] Session starts without prompting for any permission in the allow-list
- [ ] The following permissions are **always** included in the allow-list by default:
  - Compound shell commands combining `cd` and `git` (e.g., `cd <dir> && git <cmd>`) — addresses the "bare repository attack" warning
  - Edit permission for all files inside subdirectories of the current working directory

### 2.4 Compound cd+git Command Auto-Approval

**Description:** The specific permission for compound `cd` + `git` commands must always be auto-granted. This resolves the Claude Code safety warning: *"Compound commands with cd and git require approval to prevent bare repository attacks."*

**Acceptance Criteria:**
- [ ] The allow-list entry `Bash(cd * && git *)` (or equivalent pattern matching compound cd+git commands) is present in `.claude/settings.json`
- [ ] No approval prompt appears for `cd <path> && git <command>` patterns
- [ ] This permission is included by default in the configuration file template

### 2.5 Edit Permission Auto-Approval

**Description:** File edit operations targeting any file within subdirectories of the current working directory must always be auto-granted, eliminating manual approval prompts for routine file edits.

**Acceptance Criteria:**
- [ ] The allow-list entry `Edit(**/*)` (or equivalent pattern) is present in `.claude/settings.json`
- [ ] No approval prompt appears when editing any file inside any subfolder of the working directory
- [ ] This permission is included by default in the configuration file template
- [ ] **TODO: DEV to verify exact Edit permission pattern syntax accepted by Claude Code's allow-list**

### 2.6 GitHub Actions Workflow Monitoring

**Description:** When Claude triggers a GitHub Actions workflow (e.g., by pushing a commit or opening a PR), it must automatically monitor and poll the workflow status until it reaches a terminal state (success or failure) before returning control to the user.

**Acceptance Criteria:**
- [ ] After triggering any GitHub Actions workflow, Claude polls the workflow run status at a regular interval
- [ ] Polling continues until the workflow reaches a terminal state: `success`, `failure`, `cancelled`, or `skipped`
- [ ] Claude reports the final workflow status to the user before handing back
- [ ] If no GitHub Actions workflow is triggered, this behavior is a no-op
- [ ] Polling behavior is configurable (interval, timeout) via the configuration file
- [ ] **TODO: DEV to decide implementation approach — hook-based automation vs. Claude behavior instruction in settings**

### 2.7 Auto-Delete Source Branch on Merge

**Description:** When a pull request is merged, the source (head) branch must be automatically deleted after the merge completes.

**Acceptance Criteria:**
- [ ] After any PR merge event, the source branch is deleted from the remote repository
- [ ] Branch deletion is performed via `gh` CLI or GitHub API
- [ ] If branch deletion fails (e.g., already deleted, protected branch), a warning is shown but execution continues
- [ ] This behavior applies to all merge events (squash merge, rebase merge, regular merge)
- [ ] **TODO: DEV to decide implementation approach — post-merge hook vs. GitHub repository setting (`delete_branch_on_merge`) vs. scripted `gh pr merge --delete-branch`**

---

## 3. Technical Requirements

### 3.1 Technology Stack

| Component | Technology |
|-----------|------------|
| Setup Script | Bash (POSIX-compatible shell script) |
| Configuration File | JSON (`.claude/settings.json` compatible) or YAML with JSON conversion |
| Target Config Location | `.claude/settings.json` in the project root |
| Platform | macOS / Linux |

### 3.2 Claude Code Settings Structure

The Claude Code `settings.json` schema supports:
```json
{
  "permissions": {
    "allow": ["Bash(cd * && git *)", "Edit(**/*)", "..."],
    "deny": []
  },
  "model": "...",
  "hooks": {}
}
```

The setup script must produce output conforming to this schema.

### 3.3 GitHub Actions Integration

- GitHub Actions monitoring requires the `gh` CLI to be authenticated and available in PATH
- Workflow status polling uses `gh run list` / `gh run watch` or equivalent `gh` CLI commands
- Polling interval default: 15 seconds; configurable via config file
- Polling timeout default: 30 minutes; after timeout, report status and return control

### 3.4 Branch Cleanup Integration

- Branch deletion uses `gh pr merge --delete-branch` or `gh api` DELETE branch endpoint
- Only source branches (not `main`, `master`, or protected branches) are deleted
- The setup script should configure the GitHub repository's `delete_branch_on_merge` setting if the user has admin permissions, as a simpler alternative to scripted cleanup

### 3.5 Constraints

- The script must not require elevated (root) privileges
- The script must not overwrite user-specific settings not declared in the config file (merge, don't replace)
- The config file must remain compatible with Claude Code's native `settings.json` format

---

## 4. Non-Functional Requirements

### 4.1 Usability
- New developers should be able to run the setup script with zero prior knowledge of Claude Code's configuration system
- Error messages must be clear and actionable

### 4.2 Maintainability
- Adding or removing a permission requires changing only the configuration file
- The script itself requires no changes when permissions are updated

### 4.3 Security
- The allow-list must be explicit — no wildcard blanket approvals beyond what is declared
- Deny-list entries take precedence over allow-list entries

---

## 5. Acceptance Criteria

### 5.1 MVP
- [ ] `claude-config.json` (or equivalent) exists with default permissions including the cd+git compound command approval and the Edit subdirectory approval
- [ ] `setup.sh` script reads config and writes `.claude/settings.json`
- [ ] After running `setup.sh`, starting a Claude session does not prompt for any pre-approved permission
- [ ] Compound `cd + git` commands never trigger an approval prompt
- [ ] Editing files in any subdirectory never triggers an approval prompt
- [ ] After triggering a GitHub Actions workflow, Claude polls and reports the final status before returning control
- [ ] After merging a PR, the source branch is automatically deleted

### 5.2 Future Enhancements
- Support for environment-specific permission profiles (e.g., dev vs. CI)
- Interactive mode to selectively enable/disable permission groups
- Auto-update mechanism to sync config changes across team members

---

## 6. Assumptions

- Claude Code stores its project-level settings in `.claude/settings.json` relative to the project root
- The permission pattern `Bash(cd * && git *)` (or similar glob syntax) is valid in Claude Code's allow-list — **TODO: DEV to verify exact pattern syntax from Claude Code docs**
- The setup script targets Unix-like systems; Windows support is out of scope for MVP

---

*Document maintained by: PO Agent*
*Last updated: 2026-03-21 (Session 2)*
