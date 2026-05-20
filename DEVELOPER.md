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
├── reasonhub-clinical-search/
│   └── SKILL.md
└── reasonhub-expand-mechanics/
    └── SKILL.md
```

Each skill is a directory named after the skill with a single `SKILL.md`
file. Additional assets (scripts, reference docs) can live alongside it.

The repo contains two kinds of `SKILL.md`:

| Kind | Loaded by | Needs trigger phrases | Needs worked examples |
|---|---|---|---|
| **User-triggered skill** | Agent, in response to a user query | Yes | Yes |
| **Shared reference** | Other skills, via explicit cross-reference | No | No |

Current user-triggered skills: `reasonhub-snomed-semantic`,
`reasonhub-clinical-search`, `reasonhub-terminology-crossmap`.

Current shared references: `reasonhub-expand-mechanics`.

## Adding a New Skill or Shared Reference

### User-triggered skill

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

### Shared reference

A shared reference holds mechanics, lookup tables, or rules used by multiple
skills. It is never loaded directly by an agent in response to a user query.

1. Create the directory and `SKILL.md` with the same frontmatter fields.
2. Set `description` to explain what the file contains and state explicitly
   that it is **not user-triggered** — this prevents agents from loading it
   speculatively.
3. Do not include `## Examples` or trigger phrases.
4. Add a cross-reference line in every skill that depends on it:
   > See [**`reasonhub-expand-mechanics`**](../reasonhub-expand-mechanics/SKILL.md)
   > for ...
5. Add it to the **Shared References** table in `README.md`, not the
   **Skills** table.

## Updating an Existing Skill

- Keep the `name` field stable — renaming breaks installs for existing users.
- If a filter pattern changes (e.g., a new SNOMED attribute type is supported),
  update both the attribute table *and* the relevant worked example.
- When SNOMED modeling constraints are involved, always note them explicitly
  (primitive vs. fully-defined concepts, sparse coverage, fallback strategy).

## Local Installation

When developing, install directly from your working copy so edits are
picked up without re-downloading from GitHub.

```bash
# Clone (or use the submodule checkout inside the main repo)
git clone https://github.com/reason-healthcare/reasonhub-skills ~/reasonhub-skills
cd ~/reasonhub-skills

# Install skills + CLI from local files
./install.sh --agents          # ~/.agents/skills/  (pi global)
./install.sh --pi              # .agents/skills/    (pi project-level)
./install.sh --dir ~/.claude/skills  # custom path
```

The installer detects when it is running inside the repo (`skill/SKILL.md`
exists locally) and copies files directly instead of downloading from GitHub.
The `reasonhub-skills` CLI is copied to `~/.local/bin/` in all cases.

**Re-install after edits** — the installer overwrites in place, so just
re-run the same command after changing a `SKILL.md`:

```bash
./install.sh --agents
```

**Install the CLI only** — if you only changed `bin/reasonhub-skills`:

```bash
cp bin/reasonhub-skills ~/.local/bin/reasonhub-skills
chmod +x ~/.local/bin/reasonhub-skills
```

**Verify the CLI resolves credentials:**

```bash
reasonhub-skills version
# reasonhub-skills 0.1.0

echo '{"resourceType":"ValueSet","compose":{"include":[{"system":"http://snomed.info/sct","filter":[{"property":"concept","op":"is-a","value":"44054006"}]}]}}' \
  | reasonhub-skills expand --count 5
```

---

## Testing

Skills call ReasonHub MCP tools directly. To test a skill:

1. Configure your agent with the ReasonHub MCP server (see README).

2. Open an agent session and explicitly load the skill:

   ```
   /skill:reasonhub-snomed-semantic
   ```

   **Claude Desktop:** no `/skill:` command. Open a Project with the skill
   content in its instructions, then start a conversation in that Project.

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

The guidelines below apply to **user-triggered skills**. Shared references
have no worked-example or trigger-phrase requirements.

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

**No ambiguous verbs** — avoid `often`, `usually`, `consider`, `might`,
`could`, `sometimes`. Every instruction the agent reads should resolve to
a deterministic action or an explicit conditional.

## Submitting to skills.sh

[skills.sh](https://skills.sh) is the Agent Skills directory, powered by
`npx skills`. Once your changes are merged to `main`, submit the repo:

```bash
npx skills add reason-healthcare/reasonhub-skills
```

Running this from a project directory registers the source with skills.sh
telemetry. The full collection appears at:
`https://skills.sh/reason-healthcare/reasonhub-skills`

Add the install badge to the README:

```markdown
[![skills.sh](https://skills.sh/b/reason-healthcare/reasonhub-skills)](https://skills.sh/reason-healthcare/reasonhub-skills)
```

## Pull Request Checklist

### User-triggered skill

- [ ] Directory name matches `name` in frontmatter
- [ ] `description` is under 1024 chars and includes trigger phrases
- [ ] `compatibility` notes the ReasonHub MCP requirement
- [ ] `license: MIT` in frontmatter
- [ ] At least two worked examples with concrete concept IDs
- [ ] SNOMED primitive/fully-defined caveats documented where relevant
- [ ] Tested against a live ReasonHub MCP server
- [ ] `pi --list-skills --skill ./skill-name` produces no errors

### Shared reference

- [ ] Directory name matches `name` in frontmatter
- [ ] `description` states it is not user-triggered
- [ ] `compatibility` notes the ReasonHub MCP requirement
- [ ] `license: MIT` in frontmatter
- [ ] Added to **Shared References** table in `README.md`
- [ ] Cross-reference line added in every skill that depends on it
- [ ] No worked examples, no trigger phrases
