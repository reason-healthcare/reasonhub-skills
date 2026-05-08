# reasonhub-skills

Agent skills for clinical terminology querying — search SNOMED CT's semantic
relationships, crossmap codes across ICD-10, LOINC, and RxNorm, and build
property-filtered ValueSets, all from natural language clinical questions.

Follows the [Agent Skills standard](https://agentskills.io/specification).

## Prerequisites

These skills call tools from the **ReasonHub MCP server**. Before installing:

1. **Sign up** at [reasonhub.app](https://reasonhub.app) and copy your token
   from **Settings → Access Tokens**.

2. **Set credentials** — choose env vars or a config file:

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
npx skills add reason-healthcare/reasonhub-skills
```

### pi

```bash
pi add github:reason-healthcare/reasonhub-skills
```

For other agents — Claude Code, Codex CLI, Amp, Droid, Windsurf, Cursor,
GitHub Copilot — see **[INSTALL.md](./INSTALL.md)**.

## Skills

| Skill | Description |
|---|---|
| [`reasonhub-snomed-semantic`](./reasonhub-snomed-semantic/SKILL.md) | Query SNOMED CT using attribute relationships (finding site, causative agent, associated morphology, procedure site) and IS-A hierarchy. Includes clinical question translation: symptoms, complications, subtypes. |
| [`reasonhub-terminology-crossmap`](./reasonhub-terminology-crossmap/SKILL.md) | Map a code from ICD-10-CM, LOINC, or RxNorm to its SNOMED CT equivalent to unlock SNOMED's richer semantic model. |
| [`reasonhub-valueset-properties`](./reasonhub-valueset-properties/SKILL.md) | Build property-filtered ValueSets for all five code systems (SNOMED CT, LOINC, RxNorm, ICD-10-CM, UCUM) with clinical examples and a debugging guide. |

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
dashboard — cellulitis, endocarditis, bacteremia, osteomyelitis, toxic
shock syndrome, pneumonia. Use causative agent Staphylococcus aureus.
```

**Build a multi-organ ischemic infarction ValueSet**

```
I need all infarct-type conditions across every organ for an ischemic
event registry — MI, cerebral infarction, renal, pulmonary, mesenteric.
Use the associated morphology infarct. Does generic stroke/CVA
get included? If not, how do I get ischemic stroke subtypes only?
```

---

### `reasonhub-terminology-crossmap`

**Our claims data uses ICD-10 — how do I get the right SNOMED procedure codes?**

```
We have I25.10 (Atherosclerotic heart disease) in our encounter data and need a
ValueSet of coronary procedures to match against it — PCI, CABG, angiography,
stent placement. Map the ICD-10 code to SNOMED and then pull all procedures on
that artery.
```

**Does aspirin cause GI bleeding? Show me every SNOMED disorder it’s linked to**

```
I want to find all conditions attributed to aspirin in SNOMED — GI
haemorrhage, Reye syndrome, aspirin-exacerbated respiratory disease.
Start from RxNorm 1191 (Aspirin) and work through to SNOMED causative
agent.
```

**I have a LOINC panel code — what SNOMED observations are related to it?**

```
We're using LOINC 24323-8 (Comprehensive metabolic panel) and want to understand
what SNOMED observable entities correspond to its components.  Crossmap the
analytes and show what other observations share the same COMPONENT or SYSTEM.
```

---

### `reasonhub-valueset-properties`

**All active orderable quantitative hematology and chemistry LOINC codes**

```json
{
  "filter": [
    { "property": "CLASS",     "op": "in", "value": "CHEM,HEM/BC" },
    { "property": "STATUS",    "op": "=",  "value": "ACTIVE" },
    { "property": "ORDER_OBS", "op": "in", "value": "Order,Both" },
    { "property": "SCALE_TYP", "op": "=",  "value": "LP7753-9" }
  ]
}
```

**All oral solid generic clinical drugs in RxNorm**

```json
{
  "filter": [
    { "property": "TTY",              "op": "=", "value": "SCD" },
    { "property": "has_doseformgroup", "op": "=", "value": "316945" }
  ]
}
```

**A cross-system ValueSet spanning ICD-10 and SNOMED for CDS**

```json
{
  "compose": {
    "include": [
      {
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "filter": [{ "property": "parent",  "op": "is-a", "value": "E11" }]
      },
      {
        "system": "http://snomed.info/sct",
        "filter": [{ "property": "concept", "op": "is-a", "value": "44054006" }]
      }
    ]
  }
}
```

**UCUM units appropriate for a glucose concentration observation**

```
After expanding a LOINC glucose ValueSet, call codesystem_lookup on any
result to read its EXAMPLE_UCUM_UNITS property, then verify composed
expressions like mg/dL and mmol/L via codesystem_verify_code.
```

---

## License

[MIT](./LICENSE) — [Reason Healthcare](https://reasonhub.app)
