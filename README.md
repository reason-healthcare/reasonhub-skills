# reasonhub-skills

[![skills.sh](https://skills.sh/b/reason-healthcare/reasonhub-skills)](https://skills.sh/reason-healthcare/reasonhub-skills)

Agent skills for clinical terminology querying — search SNOMED CT's semantic
relationships, crossmap codes across ICD-10, LOINC, and RxNorm, and build
property-filtered ValueSets, all from natural language clinical questions.

Follows the [Agent Skills standard](https://agentskills.io/specification).

## Prerequisites

These skills call tools from the **ReasonHub MCP server**. Before installing:

1. **Sign up** at [reasonhub.app](https://reasonhub.app)
2. **Add the MCP server** to your agent's config:

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
> Find all SNOMED disorders whose causative agent is a bacterium (`409822003`)
> AND whose finding site is the respiratory tract (`321667001`). Useful for
> antibiogram reporting, infection control dashboards, or CDS rules.

**Find all morphologically-defined cardiac conditions**
> Look up a known cardiac disorder to discover its attribute typeIds, then
> filter by `associated morphology = infarct (55641003)` to find all
> infarct-type conditions of the heart — myocardial infarction, papillary
> muscle infarction, right ventricular infarction, and their subtypes.

**Explore the clinical findings of hypertension**
> Hypertension is a primitive concept (`sufficientlyDefined=false`), so
> `associated with` returns sparse results. The skill pivots to finding site
> (`363698007 = 51840005` Systemic circulatory system) to return all
> cardiovascular findings, then narrows with `concept is-a 404684003`
> (Clinical finding).

**Enumerate all subtypes of type 2 diabetes for a quality measure**
> `concept is-a 44054006` (Type 2 diabetes mellitus) returns the full
> descendant hierarchy — essential for building exhaustive denominator
> or numerator criteria in eCQMs.

---

### `reasonhub-terminology-crossmap`

**ICD-10 encounter data → SNOMED → procedure ValueSet**
> A claims dataset has `I25.10` (Atherosclerotic heart disease). Map to
> SNOMED `53741008` (Coronary arteriosclerosis), extract its finding site
> (`181294004` Coronary artery), then build a ValueSet of all SNOMED
> procedures whose procedure site is that artery — PCI, CABG, coronary
> angiography, stent placement.

**RxNorm drug → SNOMED → disorders it causes**
> RxNorm `1191` (Aspirin SCD). Strip to ingredient, map to SNOMED substance
> `387458008`, then filter disorders by `causative agent = 387458008` to
> find conditions attributed to aspirin — GI haemorrhage, Reye syndrome,
> aspirin-exacerbated respiratory disease.

**LOINC panel → SNOMED → related observations**
> LOINC `24323-8` (Comprehensive metabolic panel). Look up the LOINC
> `panel-parent` to get the component codes, crossmap the analyte names
> to SNOMED observable entities, then explore what other observations share
> the same `COMPONENT` or `SYSTEM` Part codes.

---

### `reasonhub-valueset-properties`

**All active orderable quantitative hematology and chemistry LOINC codes**
> `CLASS in CHEM,HEM/BC` + `STATUS=ACTIVE` + `ORDER_OBS in Order,Both`
> + `SCALE_TYP=LP7753-9` (Qn). Suitable for lab order catalog ValueSets
> used in CPOE systems.

**All oral solid generic clinical drugs in RxNorm**
> `TTY=SCD` + `has_doseformgroup=316945` (Oral Solid Dosage Form Group).
> Add `has_ingredient=<RxCUI>` to scope to a specific drug class —
> e.g., all oral metformin formulations for a diabetes formulary.

**A cross-system ValueSet spanning ICD-10 and SNOMED for CDS**
> Include `parent is-a E11` (ICD-10 type 2 DM) alongside
> `concept is-a 44054006` (SNOMED type 2 DM) in a single ValueSet compose.
> Used when a CDS rule must fire on both billing codes and clinical
> terminologies in the same patient record.

**UCUM units appropriate for a glucose concentration observation**
> After expanding a LOINC glucose ValueSet, call `codesystem_lookup` on any
> result to read its `EXAMPLE_UCUM_UNITS` property, then verify composed
> expressions like `mg/dL` and `mmol/L` via `codesystem_verify_code`.

---

## License

[MIT](./LICENSE) — [Reason Healthcare](https://reasonhub.app)
