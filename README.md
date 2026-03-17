# TouchFish Starter

A template repository for setting up your own [TouchFish Agent](https://github.com/LightOfTheLight/touchfish_agent) workflow. Fork this repo, configure one secret, and let AI agents handle your development tasks.

## What is TouchFish Agent?

TouchFish Agent is an AI-powered development workflow that uses Claude Code running in Docker containers, triggered by GitHub Actions. It provides three AI agents:

| Agent | Role | Triggered by |
|-------|------|--------------|
| **PO** | Product Owner - analyzes requirements, maintains REQUIREMENT.md | `@PO` in commit message |
| **DEV** | Developer - implements features and fixes based on requirements | `@DEV` in commit message |
| **TESTER** | QA - creates and runs test cases based on requirements | `@TESTER` in commit message |

## Quick Start

### 1. Fork this repo

Click **"Use this template"** or **"Fork"** to create your own copy.

### 2. Set up the secret

The agents authenticate with Claude using your OAuth token. Here's how to get it:

**Option A — Claude Code CLI (recommended)**

1. Install Claude Code: `npm install -g @anthropic-ai/claude-code`
2. Log in: `claude login`
3. Copy the token from `~/.claude/.credentials.json` → `claudeAiOauth.accessToken`

**Option B — Anthropic API key**

If you have an [Anthropic API key](https://console.anthropic.com/settings/keys), set `ANTHROPIC_API_KEY` instead of `CLAUDE_CODE_OAUTH_TOKEN`.

**Add the secret to your repo:**

Go to **Settings > Secrets and variables > Actions** and add:

| Secret | Description |
|--------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | `accessToken` from `~/.claude/.credentials.json` after `claude login` |

Or via GitHub CLI:
```bash
# Paste the token value when prompted
gh secret set CLAUDE_CODE_OAUTH_TOKEN

# Or pipe it directly
cat ~/.claude/.credentials.json | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" | gh secret set CLAUDE_CODE_OAUTH_TOKEN
```

That's the only secret you need. The agent Docker image is public and requires no authentication to pull.

### 3. Create a working branch

```bash
git checkout -b dev/my-feature
```

Agents only trigger on non-master/main branches.

### 4. Describe your project

Edit `README.md` with your project description and requirements, then commit:

```bash
git add README.md
git commit -m "Describe my project requirements @PO"
git push origin dev/my-feature
```

The `@PO` trigger tells the PO agent to read your README and generate formal requirements in `REQUIREMENT.md`.

### 5. Trigger agents

Include an agent trigger in your commit message:

```bash
# Have the PO analyze requirements
git commit -m "Update project requirements @PO"

# Have the DEV implement a feature
git commit -m "Implement user authentication @DEV"

# Have the TESTER write tests
git commit -m "Write tests for auth module @TESTER"
```

You can also use bracket syntax: `[DEV]`, `[PO]`, `[TESTER]`.

### 6. Review PRs

Each agent session creates a PR with its changes. Review, provide feedback, and merge.

## How It Works

1. You push a commit with an agent trigger (e.g., `@DEV`)
2. GitHub Actions detects the trigger and starts the workflow
3. The pre-built Docker image is pulled from `ghcr.io/lightofthelight/touchfish-agent:latest`
4. Claude Code runs inside the container with the specified agent role
5. The agent reads its instructions, your requirements, and the commit message
6. Changes are pushed to a temporary branch and a PR is created

## Repository Structure

```
.
├── .github/workflows/
│   └── agent-trigger.yml    # GitHub Actions workflow
├── agents/
│   ├── PO/
│   │   ├── PO.md            # PO agent role definition
│   │   └── history.md       # PO session history
│   ├── DEV/
│   │   ├── DEV.md           # DEV agent role definition
│   │   └── history.md       # DEV session history
│   └── TESTER/
│       ├── TESTER.md         # TESTER agent role definition
│       └── history.md        # TESTER session history
├── REQUIREMENT.md            # Project requirements (maintained by PO)
└── README.md                 # Your project description (this file)
```

## Customization

- **Agent behavior**: Edit the agent definition files in `agents/` to customize how each agent works
- **Workflow**: Modify `.github/workflows/agent-trigger.yml` to change triggers or add steps
- **Requirements**: Edit `REQUIREMENT.md` directly or let the PO agent manage it

## Requirements

- A GitHub repository (this one, forked)
- A `CLAUDE_CODE_OAUTH_TOKEN` secret configured in your repo
- Commits pushed to a non-master/main branch with agent triggers

## Links

- [TouchFish Agent](https://github.com/LightOfTheLight/touchfish_agent) - The core agent system
- [Docker Image](https://github.com/LightOfTheLight/touchfish_agent/pkgs/container/touchfish-agent) - Pre-built agent image
