build one script that when called it should auto setup all configuration mentioned for claude like settings, configuration skill, context permission .etc

## Requirements

- There should be a configuration file that defines all permissions, settings, and agent behavior
- The setup script must write permissions to the global Claude settings (~/.claude/settings.json), not a project-level subfolder — so permissions apply across all sessions and working directories
- When starting agents (e.g. Claude), it should refer back to this configuration file and grant the necessary permissions at the start of each session
- The following permission must always be auto-granted at session start:
  - "Compound commands with cd and git require approval to prevent bare repository attacks" — this should always be approved/granted without prompting
  - Edit file permission for all files inside subfolders of the current working directory — this should always be auto-granted
- If using GitHub Actions, automatically monitor and poll the workflow status until it reaches a terminal state (success or failure) before handing back to the user
- For any merge event, automatically delete the source branch after merging
- There should be a master permission list that aggregates all permissions, with separate subfiles for different permission purposes (e.g. git operations, file editing, GitHub Actions, etc.); the setup script should load and merge all subfiles into the master list
- The setup script must precheck all required dependencies (e.g. jq) at startup and automatically install any that are missing before proceeding
- A default working directory must be configurable; all file operations, git commands, and agent actions must be scoped to that directory regardless of the directory from which Claude is launched

## Dependencies

The setup script will auto-install missing dependencies where possible. Supported package managers:

| Platform | Package Manager | Auto-install |
|----------|----------------|--------------|
| Windows  | winget         | Yes          |
| macOS    | Homebrew       | Yes          |
| Debian/Ubuntu | apt       | Yes          |
| Fedora   | dnf            | Yes          |
| RHEL/CentOS | dnf / yum  | Yes          |

**Windows (winget):**
```
winget install jqlang.jq
winget install GitHub.cli
```

**macOS (Homebrew):**
```
brew install jq gh
```

**Debian/Ubuntu:**
```
sudo apt-get install jq gh
```

If winget is not available on Windows, install it via the [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) from the Microsoft Store, or install dependencies manually before running `setup.sh`.

## Default Working Directory

Set `default_working_dir` in `claude-config.json` to enforce a fixed root for all operations:

```json
{
  "default_working_dir": "/absolute/path/to/your/workspace"
}
```

When configured, all file edits, git commands, and agent-invoked scripts will resolve paths relative to this directory — even if Claude is started from a different location. This ensures consistent behavior regardless of where `claude` is launched.
