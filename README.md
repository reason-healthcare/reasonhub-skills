# reasonhub-skills

Agent skills for clinical terminology querying - search SNOMED CT's semantic
relationships, crossmap codes across ICD-10, LOINC, and RxNorm, and build
property-filtered ValueSets, all from natural language clinical questions.

Follows the [Agent Skills standard](https://agentskills.io/specification).

## Prerequisites

These skills call tools from the **ReasonHub MCP server**. Before installing:

1. **Sign up** at [reasonhub.app](https://reasonhub.app) and copy your token
   from **Settings → Access Tokens**.

2. **Set credentials** - choose env vars or a config file:

   ```bash
   # Option A: environment variables
   export RH_BASE_URL="https://reasonhub.app"
   export RH_REGISTRY_TOKEN="your-access-token-here"
   ```

   ```toml
   # Option B: ~/.reasonhub/config.toml  (or .reasonhub/config.toml in your project)
   [reasonhub]
   base_url = "https://reasonhub.app"
   token    = "your-access-token-here"
   ```

3. **Add the MCP server** to your agent's config:

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

See [INSTALL.md](./INSTALL.md) for per-agent config file paths and full
installation options.

## Installation

### skills.sh

```bash
# Step 1 - install skills
npx skills add reason-healthcare/reasonhub-skills

# Step 2 - install CLI
curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills \
  -o ~/.local/bin/reasonhub-skills && chmod +x ~/.local/bin/reasonhub-skills
```

### pi / install.sh (skills + CLI)

```bash
# pi
pi add github:reason-healthcare/reasonhub-skills

# all other agents
curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/install.sh | sh
```

Installs both `SKILL.md` files and the `reasonhub-skills` CLI to `~/.local/bin/`.

For per-agent config file paths — see **[INSTALL.md](./INSTALL.md)**.

> **Claude Desktop** does not support skill-file discovery. Configure the
> MCP server in `claude_desktop_config.json` and load skill content via
> a Project's custom instructions. See [INSTALL.md → Claude Desktop](./INSTALL.md#claude-desktop).

## Skills

| Skill | Description |
|---|---|
| [`reasonhub-snomed-semantic`](./reasonhub-snomed-semantic/SKILL.md) | Query SNOMED CT using attribute relationships (finding site, causative agent, associated morphology, procedure site) and IS-A hierarchy. Includes clinical question translation: symptoms, complications, subtypes. |
| [`reasonhub-clinical-search`](./reasonhub-clinical-search/SKILL.md) | Search ICD-10-CM, LOINC, and RxNorm by clinical concept using semantic similarity, then build a property-filtered FHIR ValueSet. Automatically detects which code system fits the query; prompts when ambiguous. Covers ICD-10 hierarchy, LOINC multi-axis filters (CLASS, COMPONENT, panel-parent), and RxNorm ingredient → product navigation. |
| [`reasonhub-terminology-crossmap`](./reasonhub-terminology-crossmap/SKILL.md) | Map a code from ICD-10-CM, LOINC, or RxNorm to its SNOMED CT equivalent to unlock SNOMED’s richer semantic model. Outputs a FHIR ConceptMap (source → SNOMED mapping with equivalence), a FHIR ValueSet (attribute-filtered procedure/finding set), and a provenance table. |

## Shared References

These files are not user-triggered skills. They are consulted by the skills
above for shared technical mechanics.

| Reference | Purpose |
|---|---|
| [`reasonhub-expand-mechanics`](./reasonhub-expand-mechanics/SKILL.md) | `valueset_expand` failure diagnosis and universal CLI fallback, bulk Python scripting, truncation handling, and debugging checklist. |

---

## Examples

### `reasonhub-snomed-semantic`

**Build a ValueSet of all bacterial respiratory infections**

```
Find all SNOMED disorders whose causative agent is a bacterium.  I need it for
antibiogram reporting and infection control dashboards.
```

**Find every disorder caused by Staphylococcus aureus**

```
I need all SNOMED disorders attributed to Staph aureus for an HAI
dashboard - cellulitis, endocarditis, bacteremia, osteomyelitis, toxic
shock syndrome, pneumonia. Use causative agent Staphylococcus aureus.
```

**Build a multi-organ ischemic infarction ValueSet**

```
I need all infarct-type conditions across every organ for an ischemic
event registry - MI, cerebral infarction, renal, pulmonary, mesenteric.
Use the associated morphology infarct. Does generic stroke/CVA
get included? If not, how do I get ischemic stroke subtypes only?
```

---

### `reasonhub-clinical-search`

**All T2DM diagnosis codes for an eCQM denominator**

```
I need all ICD-10-CM codes for type 2 diabetes mellitus for an eCQM
denominator - every subtype, complication, and manifestation under E11.
```

**All active orderable glucose lab tests**

```
Build me a LOINC ValueSet of all active orderable glucose observations
for a CDS rule that triggers on blood glucose results.
```

**All generic metformin drug products for a formulary**

```
I need a RxNorm ValueSet of all generic clinical drug products containing
metformin - tablets, extended release, combinations - for a formulary
checklist. No branded names.
```

**Cross-system eCQM bundle**

```
For a diabetes management eCQM I need three ValueSets in one resource:
all T2DM ICD-10 diagnoses, all active glucose LOINC observations, and
all generic metformin RxNorm drugs. Combine into a single cross-system
ValueSet.
```

---

### `reasonhub-terminology-crossmap`

**Our claims data uses ICD-10 - how do I get the right SNOMED procedure codes?**

```
We have I25.10 (Atherosclerotic heart disease) in our encounter data and need a
ValueSet of coronary procedures to match against it - PCI, CABG, angiography,
stent placement. Map the ICD-10 code to SNOMED and then pull all procedures on
that artery.
```

**Does aspirin cause GI bleeding? Show me every SNOMED disorder it's linked to**

```
I want to find all conditions attributed to aspirin in SNOMED - GI
haemorrhage, Reye syndrome, aspirin-exacerbated respiratory disease.
Start from RxNorm 1191 (Aspirin) and work through to SNOMED causative
agent.
```

**I have a LOINC panel code - what SNOMED observations are related to it?**

```
We're using LOINC 24323-8 (Comprehensive metabolic panel) and want to understand
what SNOMED observable entities correspond to its components.  Crossmap the
analytes and show what other observations share the same COMPONENT or SYSTEM.
```

---

## License

[MIT](./LICENSE) - [Reason Healthcare](https://reasonhub.app)
