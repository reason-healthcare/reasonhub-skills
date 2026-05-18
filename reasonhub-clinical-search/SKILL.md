---
name: reasonhub-clinical-search
description: >
  Search ICD-10-CM, LOINC, and RxNorm by clinical concept using semantic
  similarity, then build a property-filtered FHIR ValueSet in the target
  system. Use when the user wants to find diagnosis codes, lab observation
  codes, or drug/medication codes from natural language — or when they want
  to build a ValueSet and the right code system is unclear. Automatically
  detects which code system fits the query from context signals; prompts the
  user when ambiguous. For SNOMED CT semantic attribute queries (finding site,
  causative agent, morphology, procedure site) use the `snomed-semantic` skill
  instead.
license: MIT
compatibility: Requires ReasonHub MCP server. Sign up at reasonhub.app.
---

# Clinical Code Search — ICD-10-CM · LOINC · RxNorm

## Overview

SNOMED CT is the richest semantic model, but most clinical data lives in
ICD-10-CM (diagnoses), LOINC (lab and clinical observations), and RxNorm
(drugs). Each system has its own query model:

| System | Strengths | Primary filter mechanism |
|---|---|---|
| **ICD-10-CM** | Clinical diagnosis classification; encounter data; claims | `parent is-a <category>` hierarchy |
| **LOINC** | Lab and clinical observations; multi-axis axes (CLASS, COMPONENT, SYSTEM, SCALE_TYP) | `CLASS`, `COMPONENT`, `panel-parent`, `STATUS` filters |
| **RxNorm** | Drug products; ingredient → product navigation; NDC linkage | `has_ingredient = <IN_RxCUI>` + `TTY` filter |

This skill walks the full workflow for each: detect the right system, run a
semantic search to find the anchor concept, confirm it via lookup, and
compose a `ValueSet` that you can expand or hand to a FHIR server.

---

## Step 0 — Code System Selection

### Signal Detection

Read the user's query for these signals to determine which system to target.
Multiple strong signals → target multiple systems (cross-system ValueSet).

| Signal in query | Target system |
|---|---|
| "diagnosis", "ICD", "condition codes", "encounter", "claims", "billing", "disease codes" | **ICD-10-CM** |
| "lab", "test", "observation", "LOINC", "panel", "orderable", "result", "measurement", "analyte", "assay" | **LOINC** |
| "drug", "medication", "ingredient", "brand name", "RxNorm", "NDC", "prescription", "dose form", "pill", "tablet" | **RxNorm** |
| "procedure", "body structure", "organism", "morphology", "finding", "semantic relationship" | **SNOMED** → use `snomed-semantic` skill |

### Disambiguation Prompt

When signals are absent or conflict, **ask before proceeding**:

> "I can search for this concept in multiple clinical code systems. Which
> do you need?
>
> - **ICD-10-CM** — diagnosis and condition codes (claims/encounters)
> - **LOINC** — lab and clinical observation codes
> - **RxNorm** — drug and medication codes
> - **All three** — cross-system ValueSet
>
> Or tell me your use case (e.g., CDS rule, eCQM, lab order set, formulary)
> and I'll recommend the best fit."

---

## ICD-10-CM Workflow

### When to use ICD-10-CM

- Building condition/diagnosis ValueSets for eCQMs, CDS rules, or claims analytics
- Enumerating all subtypes of a clinical category (e.g., all T2DM codes, all sepsis codes)
- Finding the canonical billing code for a condition

### Step 1 — Semantic search for the category anchor

```
search_icd10(query="<clinical concept>", top_k=5)
```

**Distance interpretation:**

| Distance | Signal |
|---|---|
| < 0.10 | Excellent — high confidence match |
| 0.10–0.20 | Good — review display before using |
| > 0.25 | Weak — refine query or try alternate terms |

Pick the highest-level (shortest code) that covers the clinical domain.
For a complete subtree, prefer a category code (e.g., `E11`) over a
specific leaf code (e.g., `E11.9`).

### Step 2 — Confirm with lookup

```
codesystem_lookup(code="E11", system="http://hl7.org/fhir/sid/icd-10-cm")
```

Check:
- `display` matches intent
- Review `includes`, `inclusionTerm`, `excludes1`, `excludes2` notes
  to understand scope boundaries
- `excludes1` entries are **mutually exclusive** — codes in that note
  cannot coexist with the selected category; be aware when combining

### Step 3 — Build the ValueSet

```json
{
  "resourceType": "ValueSet",
  "name": "Type2DiabetesMellitus",
  "title": "Type 2 Diabetes Mellitus (ICD-10-CM)",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://hl7.org/fhir/sid/icd-10-cm",
      "version": "<from list_available_codesystem_versions>",
      "filter": [
        { "property": "parent", "op": "is-a", "value": "E11" }
      ]
    }]
  }
}
```

> **`is-a` includes the anchor code itself.** Use `descendent-of` to
> exclude it.

### Common ICD-10-CM Patterns

| Clinical goal | Filter |
|---|---|
| All codes in a category | `parent is-a <category>` e.g., `E11` |
| Strict children only | `parent descendent-of <category>` |
| Specific leaf code | Enumerate by `code` directly in `include.concept` |
| Active codes only | ICD-10-CM does not carry an `inactive` boolean at leaf level; the expansion itself only includes valid codes for the version |

**Tip — finding the right category code:**
ICD-10-CM hierarchy levels:
1. **Chapter** — e.g., `E00-E89` Endocrine, nutritional and metabolic diseases
2. **Block** — e.g., `E08-E13` Diabetes mellitus
3. **Category** — e.g., `E11` Type 2 diabetes mellitus ← **preferred** anchor
4. **Subcategory** — e.g., `E11.3` With ophthalmic complications
5. **Code** — e.g., `E11.311` With unspecified retinopathy with macular edema

Use `search_icd10` on the clinical domain name to land at the right level,
then verify with `codesystem_lookup`.

### ICD-10-CM Limitations

- **No semantic attributes.** ICD-10-CM has no "finding site", "causative
  agent", or "associated morphology" equivalents. For cross-organ queries
  (e.g., "all infarct disorders") use SNOMED CT via the `snomed-semantic`
  skill.
- **Tabular hierarchy only.** The parent/child structure mirrors the printed
  tabular list; it is a classification hierarchy, not a clinical ontology.
- **Coarse granularity.** ICD-10 categories are intentionally coarser than SNOMED — a single category can conflate conditions
  that SNOMED distinguishes precisely. For more granular or semantically
  filtered sets, crossmap to SNOMED via `terminology-crossmap`.

---

## LOINC Workflow

### When to use LOINC

- Building lab order sets, result observation ValueSets, or CDS rules on
  lab values
- Finding all LOINC codes for a given analyte across specimen types
- Identifying members of a panel (e.g., CMP, CBC)
- Mapping clinical observations to standard codes for interoperability

### Step 1 — Semantic search for the anchor observation

```
search_loinc(query="<analyte or test name>", top_k=10)
```

LOINC semantic search distances tend to run higher than ICD-10:

| Distance | Signal |
|---|---|
| < 0.15 | Strong match |
| 0.15–0.30 | Reasonable — confirm with lookup |
| > 0.35 | Likely off-domain — refine query |

Pick a representative observation that matches the user's intent. If the
user named a specific analyte (e.g., "glucose"), look for the code with
the best COMPONENT match.

### Step 2 — Confirm and extract axes via lookup

```
codesystem_lookup(code="<LOINC_code>", system="http://loinc.org")
```

The response includes all six LOINC axes and metadata. Extract:

| Property | Use |
|---|---|
| `COMPONENT` | LP code for the analyte — use this for sibling searches |
| `CLASS` | Domain (e.g., `CHEM`, `HEM/BC`, `MICRO`, `RAD`) |
| `CLASSTYPE` | `1`=Lab, `2`=Clinical, `3`=Claims, `4`=Survey |
| `SCALE_TYP` | `LP7753-9`=Quantitative, `LP7751-3`=Ordinal, etc. |
| `ORDER_OBS` | `Order`, `Observation`, `Both` |
| `STATUS` | `ACTIVE`, `DEPRECATED`, `DISCOURAGED`, `TRIAL` |
| `EXAMPLE_UCUM_UNITS` | Recommended UCUM unit for quantitative codes — e.g., `mg/dL` for glucose |
| `panel-parent` | Panel(s) this observation belongs to |

> **UCUM units:** Read `EXAMPLE_UCUM_UNITS` from `codesystem_lookup` for the
> recommended unit on any quantitative LOINC code. To validate a composed
> expression (e.g., `mg/dL`, `mmol/L`) use:
> `codesystem_verify_code(code="mg/dL", system="http://unitsofmeasure.org")`

> **Always read `COMPONENT` from `codesystem_lookup`** — do not guess LP
> codes, do not scrape loinc.org. The LP code is in the response.

### Step 3 — Build the ValueSet

**Pattern A — all observations for a given analyte (COMPONENT filter):**
```json
{
  "resourceType": "ValueSet",
  "name": "GlucoseObservations",
  "title": "Glucose Observations (LOINC)",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://loinc.org",
      "version": "<from list_available_codesystem_versions>",
      "filter": [
        { "property": "COMPONENT", "op": "=", "value": "LP14635-4" },
        { "property": "STATUS",    "op": "=", "value": "ACTIVE" }
      ]
    }]
  }
}
```

**Pattern B — all active orderable lab codes in a CLASS:**
```json
{
  "filter": [
    { "property": "CLASS",     "op": "=",  "value": "CHEM" },
    { "property": "CLASSTYPE", "op": "=",  "value": "1" },
    { "property": "STATUS",    "op": "=",  "value": "ACTIVE" },
    { "property": "ORDER_OBS", "op": "in", "value": "Order,Both" }
  ]
}
```

**Pattern C — panel members:**
```json
{
  "filter": [
    { "property": "panel-parent", "op": "is-a", "value": "24323-8" }
  ]
}
```

### Common LOINC Patterns

| Clinical goal | Key filter |
|---|---|
| All observations for one analyte | `COMPONENT = <LP_code>` + `STATUS = ACTIVE` |
| All active orderable lab tests in a domain | `CLASS = <CLASS>` + `ORDER_OBS in Order,Both` + `STATUS = ACTIVE` |
| All quantitative lab tests in a domain | `CLASS = <CLASS>` + `SCALE_TYP = LP7753-9` |
| Members of a specific panel | `panel-parent is-a <panel_code>` |
| All tests in a hierarchical LOINC group | `parent is-a <LP_or_LOINC_code>` |

**CLASS values for common domains:**

| CLASS | Domain |
|---|---|
| `CHEM` | Chemistry |
| `HEM/BC` | Hematology / Blood count |
| `MICRO` | Microbiology |
| `UA` | Urinalysis |
| `RAD` | Radiology |
| `CARD` | Cardiology |
| `PATH` | Pathology |
| `COAG` | Coagulation |
| `ALLERGY` | Allergy |
| `DRUG/TOX` | Toxicology / Drug levels |

> **⚠️ Do not expand `SYSTEM` LP codes.** For common blood chemistry
> analytes, `SYSTEM = LP7576-4` (Ser/Plas) matches 1000+ unrelated codes.
> `COMPONENT` is the discriminating axis.

### LOINC Limitations

- **No semantic relationships.** LOINC does not have "causative agent" or
  IS-A clinical hierarchies beyond its component/panel structure. For semantic
  reasoning about what a lab result *means* clinically, crossmap to SNOMED.
- **COMPONENT filter is exact.** `COMPONENT = LP14635-4` (Glucose) finds
  codes with that exact LP code. It does not subsume related analytes.
- **`search_loinc` returns semantic proximity, not structural siblings.**
  Use `search_loinc` only for discovery; always follow with a `COMPONENT`
  or `CLASS` filter for a precise, exhaustive set.

---

## RxNorm Workflow

### When to use RxNorm

- Building drug ValueSets for formularies, CDS alerts, eCQM numerators
- Finding all clinical drug products containing a given ingredient
- Enumerating branded drug names for a generic
- Linking to NDC codes via `codesystem_lookup`

### Step 1 — Find the ingredient

```
search_rxnorm(query="<drug name>", top_k=5)
```

Select the result whose `TTY` is `IN` (Ingredient). If no `IN` result
appears, the search returned product-level codes — search again using
only the bare ingredient name stripped of dose, form, and strength
(e.g., `"metformin"` not `"metformin 500 MG oral tablet"`).

### Step 2 — Confirm the ingredient

```
codesystem_lookup(code="<RxCUI>", system="http://www.nlm.nih.gov/research/umls/rxnorm")
```

Verify `TTY` includes `IN` (Ingredient) and `inactive = false`.

The response will list `has_ingredient` properties pointing outward to all
drug products containing this ingredient — useful for previewing scope.

### Step 3 — Build the ValueSet

**Pattern A — all generic clinical drug products for an ingredient:**
```json
{
  "resourceType": "ValueSet",
  "name": "MetforminClinicalDrugs",
  "title": "Metformin Clinical Drug Products (RxNorm)",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://www.nlm.nih.gov/research/umls/rxnorm",
      "version": "<from list_available_codesystem_versions>",
      "filter": [
        { "property": "has_ingredient",  "op": "=",   "value": "6809" },
        { "property": "TTY",             "op": "in",  "value": "SCD,SCDF,SCDG" },
        { "property": "inactive",        "op": "=",   "value": "false" }
      ]
    }]
  }
}
```

**Pattern B — all branded products for an ingredient:**
```json
{
  "filter": [
    { "property": "has_ingredient", "op": "=",  "value": "<IN_RxCUI>" },
    { "property": "TTY",            "op": "in", "value": "SBD,SBDF,SBDG" },
    { "property": "inactive",       "op": "=",  "value": "false" }
  ]
}
```

**Pattern C — all products (generic + branded) for a specific dose form group:**
```json
{
  "filter": [
    { "property": "has_ingredient",    "op": "=",  "value": "<IN_RxCUI>" },
    { "property": "TTY",               "op": "in", "value": "SCD,SBD,SCDF,SBDF" },
    { "property": "has_doseformgroup", "op": "=",  "value": "<DFG_RxCUI>" },
    { "property": "inactive",          "op": "=",  "value": "false" }
  ]
}
```

> Use `search_rxnorm("<dose form> dose form group")` to find the RxCUI
> for any dose form group — do not hard-code these values.

### TTY Selection Guide

| Use case | Include these TTY values |
|---|---|
| Generic clinical drug products | `SCD` |
| Generic + dose form (no strength) | `SCD,SCDF` |
| Generic drug class groups | `SCD,SCDF,SCDG` |
| Branded products | `SBD,SBDF,SBDG` |
| Everything (generic + branded) | `SCD,SCDF,SCDG,SBD,SBDF,SBDG` |
| Ingredient only | `IN` |
| Combination ingredients | `MIN` |

### RxNorm Expand Timeout Handling

RxNorm expansions can time out for popular ingredients (e.g., metformin,
aspirin, lisinopril) that have hundreds of associated products. If
`valueset_expand` returns a timeout error:

1. **Immediately fall back to `reasonhub-skills expand`** — do not retry
   `valueset_expand` with different parameters.
2. The ValueSet JSON is still the primary deliverable; expansion is
   informational only.
3. Narrow the ValueSet (add `has_doseformgroup`, restrict `TTY`) if the
   user needs a smaller set.

### RxNorm Limitations

- **Sparse hierarchy.** RxNorm's `parent is-a` hierarchy via RB relationships
  is thin. Use `has_ingredient` + `TTY` filters rather than hierarchy
  traversal for drug product sets.
- **No therapeutic class in FHIR filters.** RxNorm does not expose ATC
  or NDF-RT drug class hierarchy as a filterable FHIR property. For
  drug-class ValueSets (e.g., "all beta-blockers"), enumerate ingredients
  individually and union them in a multi-include compose, or crossmap to
  SNOMED substance hierarchy.
- **Combination drugs.** A drug with two ingredients has two `has_ingredient`
  entries. A single-ingredient filter will match combination products too
  (e.g., metformin/sitagliptin). Add a second `has_ingredient` exclude or
  restrict `TTY` to limit scope.

---

## Cross-System ValueSets

When the user's use case spans systems (e.g., an eCQM that needs both
diagnosis codes and lab tests), compose a multi-system ValueSet:

```json
{
  "resourceType": "ValueSet",
  "name": "DiabetesManagementBundle",
  "title": "Diabetes — Diagnoses (ICD-10-CM) + Glucose Tests (LOINC)",
  "status": "draft",
  "compose": {
    "include": [
      {
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "version": "<icd10_version>",
        "filter": [{ "property": "parent", "op": "is-a", "value": "E11" }]
      },
      {
        "system": "http://loinc.org",
        "version": "<loinc_version>",
        "filter": [
          { "property": "COMPONENT", "op": "=", "value": "LP14635-4" },
          { "property": "STATUS",    "op": "=", "value": "ACTIVE" }
        ]
      }
    ]
  }
}
```

> Each `include` section must specify `version`. Use
> `list_available_codesystem_versions` to get current versions for all
> systems.

---

## Output

Every query delivers two things.

### 1. Code System Selection Summary

State which system was selected and why (or which options were offered if
disambiguated by the user):

> Selected **ICD-10-CM** — query mentions diagnosis codes for an eCQM.
> Anchor: `E11` Type 2 diabetes mellitus.

### 2. FHIR ValueSet JSON (always deliver this)

Return a complete `ValueSet` resource with `name`, `title`, `status`, and
a populated `compose.include`. This is the primary artifact.

### 3. Expansion (ask the user)

After delivering the ValueSet JSON, ask:

> "Would you like me to expand this and show the matching codes?
> I can format the results as a **markdown table** or **CSV**."

If the user says yes, attempt `valueset_expand` **once**. On failure or
timeout, **immediately run `reasonhub-skills expand`** — do not explain,
do not offer alternatives, just run it.

If expansion returns fewer rows than `total`, label the output as partial
and stop. Do not retry. See [**`reasonhub-expand-mechanics`**](../reasonhub-expand-mechanics/SKILL.md)
for expand failures, CLI fallback, scripting, and debugging.

**Markdown table** (default):
| Code | Display |
|---|---|
| `E11` | Type 2 diabetes mellitus |
| `E11.9` | Type 2 diabetes mellitus without complications |

**CSV** (when user asks to download or import):
```csv
code,display
E11,"Type 2 diabetes mellitus"
E11.9,"Type 2 diabetes mellitus without complications"
```

---

## Worked Examples

### ICD-10-CM: "All T2DM diagnosis codes for an eCQM denominator"

```
search_icd10("type 2 diabetes mellitus", top_k=5)
# → E11.6 (distance 0.063), E11 (distance 0.098)

codesystem_lookup("E11", "http://hl7.org/fhir/sid/icd-10-cm")
# display: "Type 2 diabetes mellitus"
# includes: "diabetes NOS", "insulin resistant diabetes"
# excludes1: type 1 (E10.-), gestational (O24.4-) — scope boundary confirmed
```

```json
{
  "resourceType": "ValueSet",
  "name": "Type2DiabetesMellitusDx",
  "title": "Type 2 Diabetes Mellitus — All ICD-10-CM Codes",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://hl7.org/fhir/sid/icd-10-cm",
      "version": "2026",
      "filter": [{ "property": "parent", "op": "is-a", "value": "E11" }]
    }]
  }
}
```

Result: 65 codes covering all T2DM subtypes.

---

### LOINC: "All active orderable glucose lab tests"

```
search_loinc("glucose blood measurement quantitative", top_k=5)
# → 110939-6 "Glucose [Measurement] in Blood" (distance 0.200)
# → 2345-7  "Glucose, Blood" also in scope

codesystem_lookup("2345-7", "http://loinc.org")
# COMPONENT   = LP14635-4 (Glucose)
# CLASS       = CHEM
# CLASSTYPE   = 1
# ORDER_OBS   = Both
# SCALE_TYP   = LP7753-9 (Quantitative)
# EXAMPLE_UCUM_UNITS = mg/dL
```

```json
{
  "resourceType": "ValueSet",
  "name": "GlucoseLabTests",
  "title": "Glucose Lab Observations — Active Orderable (LOINC)",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://loinc.org",
      "version": "2.81",
      "filter": [
        { "property": "COMPONENT", "op": "=",  "value": "LP14635-4" },
        { "property": "STATUS",    "op": "=",  "value": "ACTIVE" },
        { "property": "ORDER_OBS", "op": "in", "value": "Order,Both" }
      ]
    }]
  }
}
```

---

### RxNorm: "All generic metformin clinical drug products"

```
search_rxnorm("metformin ingredient", top_k=5)
# → 372803 "metformin Oral Tablet" (SCDF, distance 0.040)
# → ingredient is 6809

codesystem_lookup("6809", "http://www.nlm.nih.gov/research/umls/rxnorm")
# display: "Metformin"
# TTY includes: IN   ← confirmed ingredient
# inactive: false
```

```json
{
  "resourceType": "ValueSet",
  "name": "MetforminGenericDrugs",
  "title": "Metformin Generic Clinical Drug Products (RxNorm)",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://www.nlm.nih.gov/research/umls/rxnorm",
      "version": "10062025",
      "filter": [
        { "property": "has_ingredient", "op": "=",  "value": "6809" },
        { "property": "TTY",            "op": "in", "value": "SCD,SCDF,SCDG" },
        { "property": "inactive",       "op": "=",  "value": "false" }
      ]
    }]
  }
}
```

> ⚠️ Metformin is a high-volume ingredient. If `valueset_expand` times out,
> run `reasonhub-skills expand` with the ValueSet JSON above.

---

### Cross-system: "Diabetes eCQM — diagnoses + glucose tests + metformin drugs"

```json
{
  "resourceType": "ValueSet",
  "name": "DiabetesECQMBundle",
  "title": "Diabetes eCQM — ICD-10-CM + LOINC + RxNorm",
  "status": "draft",
  "compose": {
    "include": [
      {
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "version": "2026",
        "filter": [{ "property": "parent", "op": "is-a", "value": "E11" }]
      },
      {
        "system": "http://loinc.org",
        "version": "2.81",
        "filter": [
          { "property": "COMPONENT", "op": "=", "value": "LP14635-4" },
          { "property": "STATUS",    "op": "=", "value": "ACTIVE" }
        ]
      },
      {
        "system": "http://www.nlm.nih.gov/research/umls/rxnorm",
        "version": "10062025",
        "filter": [
          { "property": "has_ingredient", "op": "=",  "value": "6809" },
          { "property": "TTY",            "op": "in", "value": "SCD,SCDF" },
          { "property": "inactive",       "op": "=",  "value": "false" }
        ]
      }
    ]
  }
}
```

---

## When to Escalate to Other Skills

| Situation | Use instead |
|---|---|
| User wants semantic relationships (finding site, causative agent) | `snomed-semantic` skill |
| User has an ICD-10/LOINC/RxNorm code and wants SNOMED equivalents | `terminology-crossmap` skill |
| Expansion fails or you need bulk scripting | load `reasonhub-expand-mechanics` |
| User wants to understand what a SNOMED concept's attributes are | `snomed-semantic` skill |
