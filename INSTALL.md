# Installation Guide

Full per-agent installation instructions for `reasonhub-skills`.

**Quick installs:**

```bash
# skills.sh
npx skills add reason-healthcare/reasonhub-skills

# pi
pi add github:reason-healthcare/reasonhub-skills
```

For all other agents, clone the repo once and follow the agent-specific
steps below.

```bash
git clone https://github.com/reason-healthcare/reasonhub-skills ~/reasonhub-skills
```

---

## Configuration

These skills need two values: the ReasonHub base URL and an access token.
Set them via environment variables or a config file.

### Option A — Environment variables

```bash
export RH_BASE_URL="https://reasonhub.app"
export RH_REGISTRY_TOKEN="your-access-token-here"
```

Add these to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) so they
persist across sessions.

### Option B — Config file

Create either a user-level or project-level config file:

```bash
# User-level (applies to all projects)
mkdir -p ~/.reasonhub
cat > ~/.reasonhub/config.toml << 'EOF'
[reasonhub]
base_url = "https://reasonhub.app"
token    = "your-access-token-here"
EOF

# Project-level (checked into .gitignore, applies to this project only)
mkdir -p .reasonhub
cat > .reasonhub/config.toml << 'EOF'
[reasonhub]
base_url = "https://reasonhub.app"
token    = "your-access-token-here"
EOF
echo '.reasonhub/config.toml' >> .gitignore
```

**Precedence:** environment variables override config file values.
Project-level config (`.reasonhub/config.toml`) takes precedence over
user-level (`~/.reasonhub/config.toml`).

### Endpoints derived from `RH_BASE_URL`

| Purpose | URL |
|---|---|
| MCP server | `$RH_BASE_URL/mcp` |
| Package registry | `$RH_BASE_URL/packages` |
| FHIR API | `$RH_BASE_URL/api/fhir/-/` |

### Get your access token

Sign up at [reasonhub.app](https://reasonhub.app), then copy your token
from **Settings → Access Tokens**.

---

## CLI

The installer puts `reasonhub-skills` in `~/.local/bin/`. This CLI is how
agents call the FHIR API directly when MCP is unavailable — credentials
are resolved inside the script and never exposed to callers.

```bash
# Expand a ValueSet
reasonhub-skills expand < my-valueset.json
echo '{...}' | reasonhub-skills expand
reasonhub-skills expand --count 500 < my-valueset.json

# Print version
reasonhub-skills version
```

**Windows:** the installer also places `reasonhub-skills.cmd` alongside the
Python script. Both delegate to the same Python logic. Ensure `python` is
in your PATH.

**Manual CLI install (without running the full installer):**

```bash
# Unix
curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills \
  -o ~/.local/bin/reasonhub-skills && chmod +x ~/.local/bin/reasonhub-skills

# Windows (PowerShell)
Invoke-WebRequest https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills `
  -OutFile "$env:USERPROFILE\.local\bin\reasonhub-skills"
Invoke-WebRequest https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills.cmd `
  -OutFile "$env:USERPROFILE\.local\bin\reasonhub-skills.cmd"
```

---

## MCP Configuration

All agents need the ReasonHub MCP server configured. Using the values from
your config above:

```json
{
  "mcpServers": {
    "reasonhub": {
      "type": "http",
      "url": "https://reasonhub.app/mcp",
      "headers": {
        "Authorization": "Bearer your-access-token-here"
      }
    }
  }
}
```

---

## Claude Code

Claude Code looks **one level deep** for `SKILL.md` files, so each skill
directory must be a direct child of the skills path. Symlink each skill
individually.

```bash
mkdir -p ~/.claude/skills
ln -s ~/reasonhub-skills/reasonhub-snomed-semantic      ~/.claude/skills/reasonhub-snomed-semantic
ln -s ~/reasonhub-skills/reasonhub-terminology-crossmap ~/.claude/skills/reasonhub-terminology-crossmap
ln -s ~/reasonhub-skills/reasonhub-valueset-properties  ~/.claude/skills/reasonhub-valueset-properties
```

**MCP config:** `~/.claude/mcp.json` (user-level) or `.mcp.json` in your
project root.

**Project-level (team shared):**

```bash
mkdir -p .claude/skills
ln -s ~/reasonhub-skills/reasonhub-snomed-semantic      .claude/skills/reasonhub-snomed-semantic
ln -s ~/reasonhub-skills/reasonhub-terminology-crossmap .claude/skills/reasonhub-terminology-crossmap
ln -s ~/reasonhub-skills/reasonhub-valueset-properties  .claude/skills/reasonhub-valueset-properties
```

---

## Codex CLI

```bash
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.codex/skills/reasonhub-skills
```

**MCP config:** `~/.codex/mcp.json` or per-project `.codex/mcp.json`.

---

## Amp

Amp discovers skills recursively inside toolboxes:

```bash
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.config/amp/tools/reasonhub-skills
```

**MCP config:** Amp workspace settings or `~/.config/amp/mcp.json`.

---

## Droid (Factory)

```bash
# User-level (available in all sessions)
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.factory/skills/reasonhub-skills

# Project-level
git clone https://github.com/reason-healthcare/reasonhub-skills \
  .factory/skills/reasonhub-skills
```

---

## Windsurf

```bash
mkdir -p ~/.codeium/windsurf/skills
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.codeium/windsurf/skills/reasonhub-skills
```

**MCP config:** Windsurf Settings → MCP, or `~/.codeium/windsurf/mcp_config.json`.

---

## GitHub Copilot

Place skill directories directly inside `.github/skills/` in your repository.

```bash
# As a git submodule (recommended for teams — skills stay pinned to a version)
git submodule add https://github.com/reason-healthcare/reasonhub-skills \
  .github/skills/reasonhub

# Or clone once and copy
git clone https://github.com/reason-healthcare/reasonhub-skills /tmp/rh-skills
cp -r /tmp/rh-skills/reasonhub-* .github/skills/
```

**MCP config:** `.github/mcp.json` in your repository, or Copilot workspace
settings under Extensions → GitHub Copilot → MCP Servers.

---

## Cursor

Cursor picks up `.cursor/rules/*.mdc` files. Use the included installer to
generate them from the SKILL.md sources:

```bash
cd ~/reasonhub-skills && ./install.sh --cursor
# Writes .cursor/rules/reasonhub-*.mdc in the current directory
```

Move the generated files into your project:

```bash
mkdir -p .cursor/rules
mv ~/reasonhub-skills/.cursor/rules/reasonhub-*.mdc .cursor/rules/
```

**MCP config:** `.cursor/mcp.json` in your project root, or Cursor Settings
→ MCP.

---

## Git submodule (any project)

Mount the skills repo as a submodule. Any agent that discovers skills from
a `skills/` directory at the project root (including pi) will find them
automatically.

```bash
git submodule add https://github.com/reason-healthcare/reasonhub-skills skills
git submodule update --init skills
```

Add to `.pi/settings.json` if you also want pi to load skills from another
location in the same project:

```json
{ "skills": [".github/skills"] }
```

After cloning a project that uses this submodule:

```bash
git submodule update --init skills
```

---

## Shell script (one-liner)

The installer supports all major harnesses via flags:

```bash
# Interactive prompt
curl -fsSL \
  https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/install.sh \
  | sh

# Non-interactive
curl -fsSL \
  https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/install.sh \
  | sh -s -- --pi        # ~/.agents/skills/
              --copilot   # .github/skills/
              --cursor    # .cursor/rules/
              --agents    # ~/.agents/skills/ (global pi)
              --dir PATH  # custom path
```
