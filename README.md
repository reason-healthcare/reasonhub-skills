# reasonhub-skills

Agent skills for clinical terminology querying using the [ReasonHub](https://reasonhub.com)
MCP terminology server. Query SNOMED CT's semantic relationships, crossmap codes across
clinical terminologies, and build property-filtered ValueSets — all from natural language
clinical questions.

Implements the [Agent Skills standard](https://agentskills.io/specification).

## Skills

| Skill | Description |
|---|---|
| [`snomed-semantic`](./snomed-semantic/SKILL.md) | Query SNOMED CT using attribute relationships (finding site, causative agent, morphology, procedure site) and IS-A hierarchy to answer clinical questions |
| [`terminology-crossmap`](./terminology-crossmap/SKILL.md) | Map a code from ICD-10-CM, LOINC, or RxNorm to its SNOMED CT equivalent to unlock SNOMED's richer semantic model |
| [`valueset-properties`](./valueset-properties/SKILL.md) | Build property-filtered ValueSets for all five code systems (SNOMED, LOINC, RxNorm, ICD-10-CM, UCUM) |

## Requirements

A running ReasonHub MCP server with the following tools available:

- `search_snomed`, `search_loinc`, `search_rxnorm`, `search_icd10`
- `codesystem_lookup`, `codesystem_subsumes`, `codesystem_filter_properties`
- `valueset_expand`, `list_available_codesystem_versions`

## Installation

### pi (recommended)

```bash
pi add github:reason-healthcare/reasonhub-skills
```

### Git submodule

```bash
# Mount at skills/ (auto-discovered by pi as a package skills directory)
git submodule add https://github.com/reason-healthcare/reasonhub-skills skills

# Or mount inside .github/skills/ for GitHub Copilot discovery
git submodule add https://github.com/reason-healthcare/reasonhub-skills .github/skills/reasonhub
```

### Shell script (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/install.sh | sh
```

The installer will prompt for the target location and configure your agent harness.

### Manual

Copy or symlink the skill directories you need into your agent harness's skills
discovery path:

```bash
# pi — project level
cp -r snomed-semantic terminology-crossmap valueset-properties .agents/skills/

# GitHub Copilot
cp -r snomed-semantic terminology-crossmap valueset-properties .github/skills/

# Cursor
# Run install.sh --cursor, or see Cursor section below
```

## Harness Compatibility

| Harness | Discovery path | Notes |
|---|---|---|
| [pi](https://pi.ai) | `skills/`, `.agents/skills/`, `~/.agents/skills/` | Auto-discovered; or `pi add github:reason-healthcare/reasonhub-skills` |
| GitHub Copilot | `.github/skills/` | Place skill directories directly inside |
| Claude Code | `CLAUDE.md` / `AGENTS.md` reference | Reference skill paths or copy to `~/.claude/skills/` |
| Cursor | `.cursor/rules/*.mdc` | Run `install.sh --cursor` to generate rule files |
| Any Agent Skills-compliant harness | Per harness config | SKILL.md format follows the [Agent Skills standard](https://agentskills.io/specification) |

## Usage Examples

### `snomed-semantic`

**All disorders of the kidney:**
```
search_snomed("kidney structure") → 64033007
valueset_expand: 363698007 = 64033007 + concept is-a 64572001
```

**Findings associated with hypertension:**
```
codesystem_lookup("38341003") → finding site = 51840005 (circulatory system)
valueset_expand: 47429007 = 38341003 + is-a 404684003  (try first)
valueset_expand: 363698007 = 51840005 + is-a 404684003  (pivot if sparse)
```

### `terminology-crossmap`

**ICD-10 → SNOMED → related procedures:**
```
codesystem_lookup("I21.9", icd-10) → "Acute myocardial infarction"
search_snomed("acute myocardial infarction disorder") → 22298006
codesystem_lookup("22298006") → finding site = 74281007 (Myocardium)
valueset_expand: 363704007 = 74281007 + is-a 71388002 (Procedure)
```

### `valueset-properties`

**All active orderable quantitative LOINC chemistry codes:**
```json
{ "filter": [
  { "property": "CLASS",     "op": "=",  "value": "CHEM" },
  { "property": "STATUS",    "op": "=",  "value": "ACTIVE" },
  { "property": "ORDER_OBS", "op": "in", "value": "Order,Both" },
  { "property": "SCALE_TYP", "op": "=",  "value": "LP7753-9" }
]}
```

## Contributing

Issues and PRs welcome. When adding or updating skills, please:

1. Follow the [Agent Skills specification](https://agentskills.io/specification) for frontmatter
2. Verify filter patterns against a live ReasonHub MCP server
3. Include at least two worked examples per skill
4. Note any SNOMED modeling limitations (e.g., primitive vs. fully-defined concepts)

## License

[MIT](./LICENSE) — Reason Healthcare
