# reasonhub-skills

Agent skills for clinical terminology querying — search SNOMED CT's semantic
relationships, crossmap codes across ICD-10, LOINC, and RxNorm, and build
property-filtered ValueSets, all from natural language clinical questions.

Works with pi, Claude Code, Codex CLI, Amp, Droid, GitHub Copilot, and Cursor.
Follows the [Agent Skills standard](https://agentskills.io/specification).

## Prerequisites

These skills require the **ReasonHub MCP server**, which provides the
terminology tools the skills call (`search_snomed`, `codesystem_lookup`,
`valueset_expand`, etc.).

1. **Sign up** at [reasonhub.app](https://reasonhub.app)
2. **Configure your agent** to connect to the ReasonHub MCP server:

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

   Place this in your agent's MCP config file (see harness-specific instructions
   below for where each agent looks for this).

## Skills

| Skill | Description |
|---|---|
| [`snomed-semantic`](./snomed-semantic/SKILL.md) | Query SNOMED CT using attribute relationships (finding site, causative agent, associated morphology, procedure site) and IS-A hierarchy. Includes clinical question translation: symptoms, complications, subtypes. |
| [`terminology-crossmap`](./terminology-crossmap/SKILL.md) | Map a code from ICD-10-CM, LOINC, or RxNorm to its SNOMED CT equivalent to unlock SNOMED's richer semantic model. |
| [`valueset-properties`](./valueset-properties/SKILL.md) | Build property-filtered ValueSets for all five code systems (SNOMED CT, LOINC, RxNorm, ICD-10-CM, UCUM) with clinical examples and a debugging guide. |

## Installation

### pi

```bash
pi add github:reason-healthcare/reasonhub-skills
```

Skills are available immediately in any project. MCP config goes in
`~/.pi/mcp.json` or project-level `.pi/mcp.json`.

### Claude Code

Claude Code looks **one level deep** for `SKILL.md` files, so each skill
directory must be directly under your skills path. Clone the repo and symlink:

```bash
# Clone once
git clone https://github.com/reason-healthcare/reasonhub-skills ~/reasonhub-skills

# Symlink individual skills (user-level)
mkdir -p ~/.claude/skills
ln -s ~/reasonhub-skills/snomed-semantic       ~/.claude/skills/snomed-semantic
ln -s ~/reasonhub-skills/terminology-crossmap  ~/.claude/skills/terminology-crossmap
ln -s ~/reasonhub-skills/valueset-properties   ~/.claude/skills/valueset-properties
```

MCP config goes in `~/.claude/mcp.json` (user-level) or `.mcp.json` in your
project root.

### Codex CLI

```bash
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.codex/skills/reasonhub-skills
```

### Amp

Amp discovers skills recursively in toolboxes:

```bash
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.config/amp/tools/reasonhub-skills
```

### Droid (Factory)

```bash
# User-level
git clone https://github.com/reason-healthcare/reasonhub-skills \
  ~/.factory/skills/reasonhub-skills

# Or project-level
git clone https://github.com/reason-healthcare/reasonhub-skills \
  .factory/skills/reasonhub-skills
```

### GitHub Copilot

Place skill directories inside `.github/skills/` in your repository:

```bash
# As a git submodule (recommended for teams)
git submodule add https://github.com/reason-healthcare/reasonhub-skills \
  .github/skills/reasonhub

# Or clone directly
git clone https://github.com/reason-healthcare/reasonhub-skills \
  .github/skills/reasonhub
```

MCP config goes in `.github/mcp.json` or your Copilot workspace settings.

### Cursor

Generate `.cursor/rules/*.mdc` files using the included installer:

```bash
git clone https://github.com/reason-healthcare/reasonhub-skills /tmp/reasonhub-skills
cd /tmp/reasonhub-skills && ./install.sh --cursor
```

Or clone and point Cursor at the directory in your workspace settings.

### Git submodule (any project)

```bash
# Mount at skills/ — auto-discovered by pi as a package skills directory
git submodule add https://github.com/reason-healthcare/reasonhub-skills skills
git submodule update --init skills
```

### Shell script (one-liner)

```bash
curl -fsSL \
  https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/install.sh \
  | sh
```

The installer prompts for your target harness, or pass a flag directly:

```bash
# Flags: --pi  --copilot  --cursor  --agents  --dir <path>
curl -fsSL .../install.sh | sh -s -- --pi
```

## Quick Examples

**"Find all SNOMED codes for disorders of the kidney"**
> Skill: `snomed-semantic`
> → searches for kidney structure, filters by finding site attribute

**"Map ICD-10 I21.9 to SNOMED and find related procedures"**
> Skill: `terminology-crossmap` → `snomed-semantic`
> → looks up AMI, finds SNOMED equivalent, queries procedure site

**"Give me all active orderable LOINC chemistry codes"**
> Skill: `valueset-properties`
> → `CLASS=CHEM`, `STATUS=ACTIVE`, `ORDER_OBS=Order,Both`

**"What are the clinical findings associated with hypertension?"**
> Skill: `snomed-semantic`
> → tries `associated with` filter, pivots to finding site when sparse

## License

[MIT](./LICENSE) — [Reason Healthcare](https://reasonhub.app)
