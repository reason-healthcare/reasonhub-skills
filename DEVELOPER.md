# Developer Guide

How to contribute to `reasonhub-skills` — adding new skills, updating
existing ones, and testing against a live ReasonHub MCP server.

## Prerequisites

- A running ReasonHub MCP server. Sign up at [reasonhub.app](https://reasonhub.app)
  and follow the MCP setup instructions for your agent.
- `pi` installed (`npm i -g @earendil-works/pi-coding-agent`) — for running
  skills interactively during development.

## Repo Structure

```
reasonhub-skills/
├── README.md                    # User-facing install & usage guide
├── DEVELOPER.md                 # This file
├── LICENSE
├── install.sh                   # Multi-harness installer
├── reasonhub-snomed-semantic/
│   └── SKILL.md
├── reasonhub-terminology-crossmap/
│   └── SKILL.md
└── reasonhub-valueset-properties/
    └── SKILL.md
```

Each skill is a directory named after the skill with a single `SKILL.md`
file. Additional assets (scripts, reference docs) can live alongside it.

## Adding a New Skill

1. **Create the directory**

   ```bash
   mkdir my-new-skill
   ```

   The directory name must be lowercase, hyphens only (`[a-z0-9-]`), max 64
   chars, no leading/trailing/consecutive hyphens. It must match the `name`
   field in the frontmatter.

2. **Write `SKILL.md`**

   ```markdown
   ---
   name: my-new-skill
   description: >
     One concise paragraph. What the skill does and — critically — when an
     agent should load it. Trigger phrases go here. Max 1024 chars.
   license: MIT
   compatibility: Requires ReasonHub MCP server (reasonhub.app).
   ---

   # My New Skill

   ## Overview
   ...

   ## Workflow
   ...

   ## Examples
   ...
   ```

   The `description` is what the agent sees in its system prompt to decide
   whether to load the full skill. Be specific about trigger phrases.

3. **Verify it validates**

   ```bash
   pi --list-skills --skill ./my-new-skill
   ```

   Fix any warnings about frontmatter before opening a PR.

## Updating an Existing Skill

- Keep the `name` field stable — renaming breaks installs for existing users.
- If a filter pattern changes (e.g., a new SNOMED attribute type is supported),
  update both the attribute table *and* the relevant worked example.
- When SNOMED modeling constraints are involved, always note them explicitly
  (primitive vs. fully-defined concepts, sparse coverage, fallback strategy).

## Testing

Skills call ReasonHub MCP tools directly. To test a skill:

1. Configure your agent with the ReasonHub MCP server (see README).

2. Open an agent session and explicitly load the skill:

   ```
   /skill:reasonhub-snomed-semantic
   ```

3. Run through the worked examples in the skill's `## Examples` section and
   verify the tool calls and results look correct.

4. For filter patterns, verify the `valueset_expand` call actually returns
   results — empty expansions usually mean a wrong property code, wrong
   version string, or a primitive concept with sparse attributes.

**Key things to check for each skill:**

| Check | How |
|---|---|
| All attribute typeIds in tables are valid | `codesystem_lookup` on the typeId itself |
| Filter patterns return non-empty results | `valueset_expand` with a representative concept |
| Hierarchy filters reach expected concepts | `codesystem_subsumes` |
| Crossmap candidates are reasonable | `search_snomed` + `codesystem_lookup` to confirm |
| Primitive concept caveats are documented | Note `sufficientlyDefined=false` where relevant |

## Skill Writing Guidelines

**Descriptions** — the `description` frontmatter is read on every agent turn.
Keep it under 1024 chars. Lead with what the skill does, then list specific
trigger phrases the agent should recognise.

**Worked examples** — every skill must have at least two end-to-end examples
that include actual concept IDs and the resulting filter JSON. Examples with
concrete IDs are far more useful than abstract patterns.

**Limitations** — always document what *won't* work and why, with a fallback
strategy. Agents that hit an empty expansion with no guidance will hallucinate.

**Attribute tables** — mark curated attribute tables as non-exhaustive.
Always direct the agent to use `codesystem_lookup` on a representative
concept to discover the actual attributes in use for a given clinical domain.

## Submitting to skills.sh

[skills.sh](https://skills.sh) is the Agent Skills directory. Once your
changes are merged to `main`:

1. Visit [skills.sh/submit](https://skills.sh/submit) (or the equivalent
   submission flow on the site).
2. Submit `reason-healthcare/reasonhub-skills` as the source.
3. Individual skills in the repo will be listed at their own pages, e.g.
   `skills.sh/reason-healthcare/reasonhub-skills/reasonhub-snomed-semantic`.

Users can then install via:

```bash
pi add github:reason-healthcare/reasonhub-skills
```

## Pull Request Checklist

- [ ] Directory name matches `name` in frontmatter
- [ ] `description` is under 1024 chars and includes trigger phrases
- [ ] `compatibility` notes the ReasonHub MCP requirement
- [ ] `license: MIT` in frontmatter
- [ ] At least two worked examples with concrete concept IDs
- [ ] SNOMED primitive/fully-defined caveats documented where relevant
- [ ] Tested against a live ReasonHub MCP server
- [ ] `pi --list-skills --skill ./skill-name` produces no errors
