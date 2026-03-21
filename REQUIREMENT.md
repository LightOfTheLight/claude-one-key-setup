# Project Requirements

## 1. Overview

**Project Name:** claude-one-key-setup
**Project Type:** CLI Setup Script / Configuration Tool
**Target Users:** Developers using Claude Code who want a one-command setup for all Claude permissions, settings, and agent behaviors

### 1.1 Vision

Provide a single script that, when executed, automatically configures Claude Code with all required settings, permissions, skills, and behaviors — eliminating the need for manual setup or repeated permission prompts during sessions.

### 1.2 Core Principles

- **One command, full setup:** A single script invocation should configure everything
- **Declarative configuration:** All permissions and settings are defined in a central config file, not scattered across sessions
- **Non-interactive by design:** Approved permissions should never prompt again after initial setup

---

## 2. Functional Requirements

### 2.1 Setup Script

**Description:** A single executable script that reads the configuration file and applies all Claude Code settings, permissions, and behaviors in one pass.

**Acceptance Criteria:**
- [ ] Script is executable with a single command (e.g., `./setup.sh` or `bash setup.sh`)
- [ ] Script reads from the central configuration file
- [ ] Script applies all settings to the appropriate Claude config location (e.g., `.claude/settings.json` or `~/.claude/settings.json`)
- [ ] Script is idempotent — running it multiple times does not create duplicate entries
- [ ] Script prints a summary of what was configured upon completion
- [ ] Script handles missing config gracefully with a clear error message

### 2.2 Central Configuration File

**Description:** A single source-of-truth file that declares all permissions, settings, and agent behaviors for Claude Code.

**Acceptance Criteria:**
- [ ] Configuration file exists in the repository (e.g., `claude-config.json` or `claude-config.yaml`)
- [ ] Configuration file defines the list of auto-granted permissions
- [ ] Configuration file defines general Claude Code settings (e.g., model, theme, behavior flags)
- [ ] Configuration file is human-readable and well-commented/documented
- [ ] Format is compatible with Claude Code's `settings.json` schema or can be mapped to it

### 2.3 Auto-Grant Permissions at Session Start

**Description:** All permissions defined in the configuration file must be automatically granted when a Claude session starts, without requiring manual approval.

**Acceptance Criteria:**
- [ ] Permissions listed in the config file are written to Claude's `settings.json` under the appropriate `allowedTools` or permissions section
- [ ] Session starts without prompting for any pre-approved permissions
- [ ] New permissions added to the config file are applied on next script run

### 2.4 Always Auto-Grant: Compound cd+git Commands

**Description:** The specific permission for "Compound commands with cd and git require approval to prevent bare repository attacks" must always be auto-approved — no prompt, ever.

**Acceptance Criteria:**
- [ ] The compound cd+git permission is included in the setup configuration
- [ ] After setup, Claude never prompts for approval when running compound `cd` + `git` commands
- [ ] This permission is hardcoded/documented as a required default in the config file

---

## 3. Technical Requirements

### 3.1 Technology Stack

| Component | Technology |
|-----------|------------|
| Setup Script | Bash shell script (`setup.sh`) |
| Configuration File | JSON (compatible with Claude's `settings.json`) |
| Target Config Path | `~/.claude/settings.json` (user-level) or `.claude/settings.json` (project-level) |

### 3.2 Constraints

- Must not require any third-party dependencies beyond standard Unix utilities (bash, jq optional)
- Must work on macOS and Linux
- Must not overwrite existing user settings — should merge/append only
- The compound cd+git permission must always be present after setup

---

## 4. Non-Functional Requirements

### 4.1 Usability
- A developer with no prior Claude Code configuration experience should be able to run the script and be fully set up
- Clear, readable output during setup

### 4.2 Maintainability
- Adding new permissions or settings should only require editing the central config file
- No need to modify the setup script for new permission additions

### 4.3 Safety
- Script must not destructively overwrite existing configurations
- Script must validate the config file before applying changes

---

## 5. Acceptance Criteria

### 5.1 MVP
- [ ] `setup.sh` script exists and is executable
- [ ] Central config file (`claude-config.json`) exists with all permissions defined
- [ ] Running `setup.sh` writes permissions to Claude's settings file
- [ ] After running `setup.sh`, compound cd+git commands are never prompted for approval
- [ ] Script is idempotent (safe to run multiple times)

### 5.2 Future Enhancements
- Support for multiple environment profiles (dev, prod)
- Auto-detect and merge with existing Claude project-level `.claude/settings.json`
- Interactive mode to selectively enable/disable permissions

---

## 6. Permission Reference

### 6.1 Always-Granted Permissions (Required Defaults)

| Permission | Description | Rationale |
|-----------|-------------|-----------|
| `Bash(cd:*)` + `Bash(git:*)` compound | Compound commands with cd and git | Required for standard repo workflows; should never prompt |

### 6.2 Additional Permissions (From Config File)

All other permissions are defined in the central config file and applied by the setup script.

---

*Document maintained by: PO Agent*
*Last updated: 2026-03-21*
