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

## MCP Configuration

All agents need the ReasonHub MCP server configured. Sign up at
[reasonhub.app](https://reasonhub.app) to get access, then add:

```json
{
  "mcpServers": {
    "reasonhub": {
      "type": "http",
      "url": "https://mcp.reasonhub.app/mcp"
    }
  }
}
```

The config file location varies by agent — see each section below.

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
