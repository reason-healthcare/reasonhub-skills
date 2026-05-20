# reasonhub-skills — Claude Desktop Instructions

Paste the entire contents of this file into your Claude Desktop
Project's custom instructions (gear icon → Project Instructions).
Requires the ReasonHub MCP server configured in
`claude_desktop_config.json` — see README for the config block.


---


# SNOMED Semantic Query

## Overview

SNOMED CT is unique among clinical terminologies: every fully-defined concept
carries explicit **attribute relationships** encoded as FHIR properties.  These
let you answer questions like "all disorders of the cardiovascular system" or
"all conditions with infarct morphology" using structured queries rather than
keyword search.

This skill walks through the full workflow: find the pivot concept, inspect its
relationships, choose the right attribute type, and build a `valueset_expand`
filter that returns exactly the right set of codes.

---

## Output

Every query produces two deliverables.

### 1. FHIR ValueSet JSON (always deliver this)

Return a complete `ValueSet` resource with `name`, `title`, `status`, and a
populated `compose.include`. This is the primary artifact — useful whether or
not expansion succeeds.

```json
{
  "resourceType": "ValueSet",
  "name": "AllInfarctDisorders",
  "title": "All Infarct Disorders",
  "status": "draft",
  "compose": {
    "include": [
      {
        "system": "http://snomed.info/sct",
        "version": "<from list_available_codesystem_versions>",
        "filter": [
          { "property": "116676008", "op": "=", "value": "55641003" },
          { "property": "inactive",  "op": "=", "value": "false" }
        ]
      }
    ]
  }
}
```

### 2. Expansion (ask the user)

After delivering the ValueSet JSON, ask:

> "Would you like me to expand this and show the matching codes?
> I can format the results as a **markdown table** or **CSV**."

If the user says yes, attempt `valueset_expand` **once**. On failure,
**immediately run `reasonhub-skills expand`** with the same ValueSet JSON
— do not explain, do not offer alternatives, just run it.

If expansion returns fewer rows than `total`, label the output as partial
and stop. Do not retry. See [**`reasonhub-expand-mechanics`**](../reasonhub-expand-mechanics/SKILL.md)
for expand failures, CLI fallback, scripting, and debugging.

If expansion succeeds, use the requested format:

**Markdown table** (default):
| Code | Display |
|---|---|
| `22298006` | Myocardial infarction |
| `432504007` | Cerebral infarction |

**CSV** (when the user asks to download, import, or use in a spreadsheet):
```csv
code,display
22298006,"Myocardial infarction"
432504007,"Cerebral infarction"
```

For SNOMED results, adding `semanticTag` as a third column is useful when
the expansion mixes disorders, findings, and procedures:
```csv
code,display,semanticTag
22298006,"Myocardial infarction",disorder
432504007,"Cerebral infarction",disorder
```

---

## SNOMED's Semantic Model

### Common relationship attributes

This table lists frequently encountered attributes. It is **not exhaustive** —
SNOMED CT defines hundreds of attribute types, and the exact set on any concept
depends on its definition. Always use `codesystem_lookup` on a representative
concept to discover the actual attributes present (see
[Discovering Attributes by Lookup](#discovering-attributes-by-lookup) below).

| Attribute typeId | Name | Applies to | Example |
|---|---|---|---|
| `363698007` | Finding site | Disorders, findings | Finding site = Heart structure (`80891009`) |
| `246075003` | Causative agent | Disorders, infections | Causative agent = Staphylococcus (`65119002`) |
| `116676008` | Associated morphology | Disorders, findings | Associated morphology = Infarct (`55641003`) |
| `363704007` | Procedure site - Direct | Procedures | The structure directly incised/excised. Kidney biopsy uses `405813007` (Indirect) instead — look up first. |
| `405813007` | Procedure site - Indirect | Procedures | Used when the procedure's target is reached via another structure. **Look up a representative procedure before choosing between `363704007` and `405813007`** — both may be present on the same concept; use whichever appears on the procedures you need to capture. |
| `370135005` | Pathological process | Disorders | Pathological process = Inflammatory (`441862004`) |
| `47429007`  | Associated with | Findings, disorders | Associated with = Hypertension (`38341003`) |
| `42752001`  | Due to | Disorders, findings | Due to = Type 2 diabetes mellitus (`44054006`) — links complications to causal condition |
| `363713009` | Interprets | Findings | Interprets = Blood pressure (`75367002`) |
| `363714003` | Has interpretation | Findings | Has interpretation = Increased (`35105006`) |
| `255234002` | After | Procedures | After = General anaesthesia |

### How the filter works

Relationship filters are **outbound**: they find concepts where a given
attribute *points to* a target concept.

```
concept --[363698007 Finding site]--> 80891009 Heart structure
```

So `filter: property=363698007, op==, value=80891009` returns all concepts
whose "finding site" attribute equals "Heart structure".

### ⚠️ `=` is exact match, not subsumption

The `=` operator matches only concepts that store **exactly** the specified
concept ID as their attribute value. It does **not** apply subsumption to the
value side — filtering by `363698007 = 321667001` (respiratory tract) will
**not** automatically include concepts coded to `39607008` (lung structure) or
`113255004` (lung parenchyma), even though both are subtypes of respiratory tract.

SNOMED concepts are coded to specific anatomical sites, not to tidy ancestor
concepts. For example:

| Concept | `363698007` finding site coded to |
|---|---|
| Bacterial pneumonia (`53084003`) | `113255004` Structure of parenchyma of lung |
| Bacterial respiratory infection (`312117008`) | `20139000` Structure of respiratory system |
| Pneumoconiosis (`40122008`) | `39607008` Lung structure |

A query for `363698007 = 321667001` (respiratory tract) matches **none** of
these, because none are coded to that exact concept ID.

**Practical rule:** always call `codesystem_lookup` on a few representative
concepts in your target clinical domain first. Read the actual value stored for
your attribute, then use that concept ID — or its closest common ancestor that
concepts in that domain actually share — as your filter value.

> **What you cannot do directly:** reverse lookups ("find all concepts that
> hypertension causes"). SNOMED doesn't have a `has-symptom` attribute.
> Use the IS-A hierarchy or causative-agent filter instead.

---

## Filter Rules

These rules apply to every filter in this skill. Violating any of them will
produce empty or wrong results.

1. **Only active relationships are stored.** Inactive concept attributes are
   excluded — adding `inactive = false` to a filter is redundant but harmless;
   omitting it does not expose inactive data.
2. **Primitive concepts have sparse or no attributes.** If `sufficientlyDefined
   = false`, the concept may be defined only by IS-A. Look up a fully-defined
   representative concept from the same domain to discover attributes.
3. **`=` is exact match on the value side — not subsumptive.** Filtering by
   `363698007 = 321667001` (respiratory tract) does **not** match concepts
   coded to `39607008` (lung structure) even though lung is a subtype of
   respiratory tract. Always look up a representative target concept to find
   the exact value ID used in your domain.
4. **Role groups are flattened.** Combined attributes within a single role
   group are not co-enforced in filters. Stacked filters apply as independent
   AND conditions across all role groups.
5. **No `has-symptom` attribute exists.** For symptom/association queries
   use the [Translating Clinical Questions](#translating-clinical-questions)
   table.

---

## Workflow

### Step 1 — Identify the pivot concept

The *pivot* is the concept you want to filter **by** (the attribute value).

Use `search_snomed` with a descriptive query:

```
search_snomed(query="heart structure anatomy")
search_snomed(query="infarct morphology")
search_snomed(query="staphylococcus aureus organism")
```

Select the top match whose `semanticTag` aligns with your domain:

| Domain | Expected `semanticTag` |
|---|---|
| Anatomical location | `body structure` |
| Organism / pathogen | `organism` |
| Morphologic change | `morphologic abnormality` |
| Finding / symptom | `finding` |
| Disease / disorder | `disorder` |
| Substance / drug | `substance` |

If the top match has an unexpected tag, call `codesystem_lookup` on it before
using it as a pivot — the display may be correct even if the tag differs.

### Step 2 — Confirm with `codesystem_lookup`

```
codesystem_lookup(code="80891009", system="http://snomed.info/sct")
```

Check:
- `display` matches what you expect
- `semanticTag` confirms the concept type
- `inactive` is `false`

### Step 3 — Discover the attribute type via lookup

Do not rely solely on the table above. **Always look up a representative
concept** in the target domain to see which attribute typeIds are actually
present:

```
codesystem_lookup(code="22298006", system="http://snomed.info/sct")
# Returns properties including:
#   363698007 (Finding site) = 74281007 (Myocardium structure)
#   116676008 (Associated morphology) = 55641003 (Infarct)
```

Properties whose `code` is a bare numeric SNOMED ID are attribute
relationships. Named properties (`parent`, `inactive`, `semanticTag`, etc.)
are metadata, not clinical attributes.

**Example — discovering hypertension's attributes:**
```
codesystem_lookup(code="38341003", system="http://snomed.info/sct")
# Reveals:
#   363698007 (Finding site)      = 51840005 (Systemic circulatory system)
#   363713009 (Interprets)        = 35105006 (Increased)
#   363714003 (Has interpretation)= 75367002 (Blood pressure)
# Note: sufficientlyDefined=false — primitive concept, sparse attributes
```

Hypertension's attributes describe *what it is* (elevated BP in the
circulatory system), not its clinical associations. This is why the
`associated with` filter for "symptoms of hypertension" returns sparse
results — see [Translating Clinical Questions](#translating-clinical-questions).

### Step 4 — Expand with a property filter

```json
{
  "resourceType": "ValueSet",
  "compose": {
    "include": [{
      "system": "http://snomed.info/sct",
      "version": "<use list_available_codesystem_versions>",
      "filter": [
        {
          "property": "363698007",
          "op": "=",
          "value": "80891009"
        }
      ]
    }]
  }
}
```

Pass this to `valueset_expand`.

> **⚠️ Expand failures:** See [**`reasonhub-expand-mechanics`**](../reasonhub-expand-mechanics/SKILL.md)
> for expand failures, `reasonhub-skills expand` CLI fallback,
> and credential guidance.

### Step 5 — Refine with stacked filters

Filters in the same `include` are combined with AND:

```json
"filter": [
  { "property": "concept",   "op": "is-a", "value": "64572001" },
  { "property": "363698007", "op": "=",    "value": "80891009" },
  { "property": "inactive",  "op": "=",    "value": "false"    }
]
```

→ Active disorders (`is-a 64572001`) whose finding site is the heart.

---

## Common Clinical Patterns

### All disorders of a body structure
```json
{ "property": "363698007", "op": "=", "value": "<body_structure_id>" }
```

### All disorders caused by an agent
```json
{ "property": "246075003", "op": "=", "value": "<organism_or_substance_id>" }
```

### All disorders with a morphology
```json
{ "property": "116676008", "op": "=", "value": "<morphology_id>" }
```

### All procedures on a body site
```json
{ "property": "363704007", "op": "=", "value": "<body_structure_id>" }
```
> Check with `codesystem_lookup` whether the procedure uses `363704007` (Direct)
> or `405813007` (Indirect) — kidney biopsy, for example, uses Indirect.

### All subtypes of a condition (hierarchy)
```json
{ "property": "concept", "op": "is-a", "value": "<parent_concept_id>" }
```

> ⚠️ **`is-a` captures clinical subtypes only, NOT complications.**
> Concepts like "retinopathy due to T2DM" are NOT IS-A children of T2DM — they link
> via `42752001` (Due to). Use the two-include compose pattern below for complete eCQM sets.

### Strict descendants only (exclude the parent itself)
```json
{ "property": "concept", "op": "descendent-of", "value": "<parent_concept_id>" }
```

### All disorders caused by / due to a condition
```json
{ "property": "42752001", "op": "=", "value": "<condition_id>" }
```
Captures complication concepts encoded with "Due to" (e.g., retinopathy/neuropathy due to T2DM).

### Complete eCQM ValueSet: condition subtypes + their complications (two-include compose)
```json
{
  "compose": {
    "include": [
      {
        "system": "http://snomed.info/sct",
        "filter": [{ "property": "concept",  "op": "is-a", "value": "<condition_id>" }]
      },
      {
        "system": "http://snomed.info/sct",
        "filter": [{ "property": "42752001", "op": "=",   "value": "<condition_id>" }]
      }
    ]
  }
}
```

### Active concepts only (add to any filter set)
```json
{ "property": "inactive", "op": "=", "value": "false" }
```

---

## Translating Clinical Questions

Natural language clinical questions do not always map to a single
SNOMED attribute. Use this table to select the strategy, with explicit
fallbacks when attribute coverage is thin.

| Clinical question | Best strategy | Coverage | Fallback |
|---|---|---|---|
| "All disorders of [body part]" | `363698007 = <body_structure>` + `is-a 64572001` | ⚠️ `=` is exact match — look up a representative concept first to find the actual concept ID used. See note below. | `is-a` on the body-site disorder parent |
| "All conditions caused by [agent]" | `246075003 = <organism/substance>` | ✅ Good — infections well-modelled | `is-a` on infectious disease hierarchy |
| "All procedures on [body part]" | `363704007 = <body_structure>` + `is-a 71388002` | ⚠️ Look up first — many procedures use `405813007` (Indirect) instead of Direct | `is-a` on the procedure hierarchy |
| "Subtypes of [condition]" | `concept is-a <condition>` | ✅ Always works | — |
| "Symptoms / findings associated with [condition]" | `47429007 = <condition>` + `is-a 404684003` | ⚠️ Sparse — only explicitly encoded associations | See note below |
| "Complications of [condition]" | `42752001 = <condition>` + `is-a 64572001` | ✅ Good — fully-defined complication concepts encode this | `47429007 = <condition>` (broader "associated with") |
| "Risk factors for [condition]" | `47429007 = <condition>` + `is-a 229819007` | ⚠️ Sparse | Semantic search |

### The `associated with` pattern and its limits

The filter for "symptoms/findings associated with X" is:

```json
"filter": [
  { "property": "47429007", "op": "=", "value": "<condition_id>" },
  { "property": "concept",  "op": "is-a", "value": "404684003" }
]
```

This returns **only concepts that explicitly encode the association** as an
outbound attribute. Coverage depends entirely on how well that condition is
modelled in SNOMED:

- **Well-modelled conditions** (many fully-defined descendants): returns
  useful results. Example: specific infectious diseases, metabolic disorders.
- **Primitive conditions** (`sufficientlyDefined = false`, e.g., hypertension):
  the condition itself has few outbound attributes, and few concepts encode
  hypertension as their `associated with` value. The expansion will likely
  be empty or very small.

**When `associated with` returns thin results, use these strategies instead:**

1. **Subtypes** — the condition's descendants are its more specific
   presentations:
   ```json
   { "property": "concept", "op": "is-a", "value": "<condition_id>" }
   ```

2. **Finding site** — find all findings at the same anatomical site:
   ```json
   { "property": "363698007", "op": "=", "value": "<site_from_lookup>" }
   ```
   Use `codesystem_lookup` on the condition first to extract its finding site.

3. **Semantic search** — use `search_snomed` with the condition name plus
   context terms (`"hypertension complication"`, `"elevated blood pressure
   finding"`) to find individual concepts, then build an explicit list.

### Worked example: "All infarct disorders" — discovering associated morphology

This example shows how a single non-hierarchy attribute filter crosses every
organ system to return a clinically precise, exhaustive result set — the
capability that most distinguishes SNOMED from ICD-10 or text search.

```
# Step 1 — look up a known, fully-defined infarct disorder to discover the attribute
codesystem_lookup("22298006")  # Myocardial infarction
  → 116676008 (Associated morphology) = 55641003 (Infarct)
  → 363698007 (Finding site)          = 74281007 (Myocardium structure)
  → sufficientlyDefined = true  ← fully defined, complete attribute set

# Step 2 — confirm the morphology concept is active and correctly typed
codesystem_lookup("55641003")  # Infarct
  → semanticTag = "morphologic abnormality"  ← correct type for 116676008 values
  → inactive = false

# Step 3 — verify the same morphology value appears on a different organ
codesystem_lookup("432504007")  # Cerebral infarction
  → 116676008 (Associated morphology) = 55641003 (Infarct)  ← same value
  → 363698007 (Finding site)          = 83678007 (Cerebrum)  ← different site

# Step 4 — confirm generic stroke uses a DIFFERENT morphology
codesystem_lookup("230690007")  # Cerebrovascular accident (stroke, CVA)
  → 116676008 (Associated morphology) = 37782003 (Damage)  ← NOT Infarct
  # → the filter will correctly exclude hemorrhagic stroke and generic CVA
```

**Step 5 — expand all infarct disorders (cross-organ)**
```json
{
  "filter": [
    { "property": "116676008", "op": "=", "value": "55641003" },
    { "property": "inactive",  "op": "=", "value": "false"    }
  ]
}
```
→ Myocardial infarction, cerebral infarction, renal infarction, pulmonary
  infarction, splenic infarction, mesenteric infarction, bone infarction…
  One filter. Every organ. No text matching.

**Step 6 — narrow to ischemic stroke only (stacked filters)**
```json
{
  "filter": [
    { "property": "116676008", "op": "=", "value": "55641003" },
    { "property": "363698007", "op": "=", "value": "83678007" },
    { "property": "inactive",  "op": "=", "value": "false"    }
  ]
}
```
→ Cerebral infarction and its subtypes (thrombotic, embolic, lacunar,
  pontine) — ischemic stroke only, hemorrhagic stroke excluded by design.

---

## Worked Examples

### "All infarct disorders across every organ"
1. Lookup: `codesystem_lookup("22298006")` → `116676008 = 55641003` (morphology = Infarct)
2. Verify: `codesystem_lookup("432504007")` → same morphology on cerebral infarction
3. Contrast: `codesystem_lookup("230690007")` → CVA has morphology = `37782003` (Damage), not Infarct
4. Filter: `116676008 = 55641003` → MI, cerebral infarction, renal infarction, pulmonary infarction…
5. Stack: add `363698007 = 83678007` (Cerebrum) to narrow to ischemic stroke subtypes only

### "All cardiac disorders"
1. Lookup: `codesystem_lookup("22298006")` → confirms `363698007 = 74281007` (Myocardium) — note this is the myocardium, not heart. Check several concepts to find the broadest commonly-used site.
2. Search: `search_snomed("heart structure body structure")` → `80891009` Heart structure
3. Filter: `363698007 = 80891009` inside `is-a 64572001` (Disorder)
   > `=` is exact match. Concepts coded to `74281007` (Myocardium) or `40527003` (Left ventricle) are missed. Use causative-agent or `is-a` as a broader net if coverage is thin.

### "All bacterial infections"
1. Search: `search_snomed("bacteria organism")` → `409822003` Bacterium
2. Filter: `246075003 = 409822003` inside `is-a 40733004` (Infectious disease)

### "All ischemic conditions"
1. Search: `search_snomed("ischemic process pathological")` → `255426005`
2. Filter: `370135005 = 255426005`

### "All renal procedures"
1. Lookup: `codesystem_lookup("7246002")` (Kidney biopsy) → `405813007 = 64033007` — uses **Indirect** site, not Direct
2. Search: `search_snomed("kidney structure body structure")` → `64033007`
3. Filter: try both `363704007 = 64033007` and `405813007 = 64033007`; use `is-a 71388002` (Procedure) in both

### eCQM denominator/numerator: all T2DM concepts (subtypes + complications)

This is the canonical example for building exhaustive eCQM criteria.

**Step 1 — Verify the root concept**
```
codesystem_lookup("44054006")  →  display = "Type 2 diabetes mellitus"
                                   sufficientlyDefined = false  ← primitive
                                   parent = 73211009 (Diabetes mellitus)
```

**Step 2 — Check which concepts are IS-A children vs. complication-linked**

| Concept | Code | In `is-a 44054006`? | Link |
|---|---|---|---|
| T2DM in obese | `81531005` | ✅ Yes | direct `parent = 44054006` |
| Insulin-treated T2DM | `237599002` | ✅ Yes | direct `parent = 44054006` |
| Retinopathy due to T2DM | `422034002` | ❌ No | `42752001` (Due to) = `44054006` |
| Neuropathy due to T2DM | `368581000119106` | ❌ No | `42752001` (Due to) = `44054006` |
| CAD due to T2DM | `16891151000119103` | ❌ No | `42752001` (Due to) = `44054006` |

> `is-a` alone misses all complication concepts. For a complete eCQM set,
> use a two-include ValueSet that unions both trees.

**Step 3 — Build the complete ValueSet**
```json
{
  "resourceType": "ValueSet",
  "compose": {
    "include": [
      {
        "system": "http://snomed.info/sct",
        "version": "<see list_available_codesystem_versions>",
        "filter": [
          { "property": "concept", "op": "is-a", "value": "44054006" },
          { "property": "inactive", "op": "=",   "value": "false" }
        ]
      },
      {
        "system": "http://snomed.info/sct",
        "version": "<see list_available_codesystem_versions>",
        "filter": [
          { "property": "42752001", "op": "=",   "value": "44054006" },
          { "property": "inactive", "op": "=",   "value": "false" }
        ]
      }
    ]
  }
}
```

- **Include 1** captures the root code `44054006` plus all IS-A subtypes (clinical variants of T2DM)
- **Include 2** captures all complications encoded with "Due to = T2DM" (retinopathy, neuropathy, nephropathy, peripheral vascular disease, etc.)
- Together they form the exhaustive denominator or numerator set most eCQMs require

**Scope note:** use `descendent-of` instead of `is-a` in include 1 if the measure
exclicitly excludes the root code (uncommon but possible in pre-coordinated IGs).

---

## Discovering Attributes by Lookup

The attribute table earlier is a starting point, not a complete list. The
authoritative source is the concept data itself.

**Protocol:**

1. Pick a well-known, fully-defined (`sufficientlyDefined = true`) example
   concept from the target clinical domain.
2. Call `codesystem_lookup` on it.
3. In the response, find `property` entries whose `code` is a bare numeric
   SNOMED concept ID — those are attribute relationships.
4. The `description` field names the attribute (e.g., `"Myocardium structure"`).
   To get the attribute *type* name, call `codesystem_lookup` on the typeId
   itself (e.g., `codesystem_lookup("363698007")` → `"Finding site"`).
5. Use those typeIds in your `valueset_expand` filter.

**Prefer fully-defined concepts for discovery.** Primitive concepts
(`sufficientlyDefined = false`) have fewer or no attribute relationships and
will not reveal the full attribute set used by their clinical class.

```
# Good discovery target: Myocardial infarction (sufficientlyDefined=true)
codesystem_lookup("22298006")  →  363698007, 116676008 present

# Poor discovery target: Hypertensive disorder (sufficientlyDefined=false)
codesystem_lookup("38341003")  →  only 363698007, 363713009, 363714003
                                   (incomplete picture of disorder attributes)
```

---

## Hierarchy Checks

Before building a hierarchy filter, verify the relationship:

```
codesystem_subsumes(
  code_a="64572001",   # Disease
  code_b="22298006",   # Myocardial infarction
  system="http://snomed.info/sct"
)
# Expected: subsumed-by (MI is a subtype of Disease)
```

---

## Getting the Full Property Reference

```
codesystem_filter_properties(system="http://snomed.info/sct")
```

---



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

---


# Terminology Crossmap → SNOMED

## Overview

ICD-10-CM, LOINC, and RxNorm all have strong use cases but limited semantic
depth. SNOMED CT's attribute model (finding site, causative agent, associated
morphology, etc.) is unmatched for answering clinical relationship questions.

This skill bridges the gap: given a code in any system, find its SNOMED
equivalent and then use the `snomed-semantic` skill to query relationships.

> **No formal crossmap table is loaded.** Mapping uses semantic search
> (`search_snomed`) on the source concept's display name. Always verify the
> match before proceeding.

---

## When to Propose a Crossmap

Proactively suggest crossmapping to SNOMED when:

- The user has an **ICD-10-CM** code and asks "what is related to this?"
- The user has a **LOINC** observation code and wants to understand the
  clinical domain semantically
- The user has an **RxNorm** ingredient and wants to find all disorders it
  treats or all procedures that use it
- The user asks about "symptoms of X", "conditions caused by X", or
  "procedures for X" using a non-SNOMED code

---

## Workflow

### Phase 1 — Look up the source code

```
codesystem_lookup(code="<source_code>", system="<source_system>")
```

Extract the `display`. This is the search query for Phase 2.

```
codesystem_lookup("I25.10", "http://hl7.org/fhir/sid/icd-10-cm")
# display: "Atherosclerotic heart disease of native coronary artery
#            without angina pectoris"
```

### Phase 2 — Search SNOMED for the equivalent

Run this **in parallel with Phase 1** if the source display is already known.

```
search_snomed(query="coronary arteriosclerosis disorder", top_k=5)
```

**Selection heuristics:**
- ICD-10 diagnosis → prefer `(disorder)` semantic tag
- LOINC observation → prefer `(observable entity)`
- RxNorm ingredient → prefer `(substance)`
- Prefer `sufficientlyDefined = true` (richer attributes)
- When ambiguous, present 2–3 candidates and ask the user

### Phase 3 — Confirm the match and extract the pivot

```
codesystem_lookup(code="53741008", system="http://snomed.info/sct")
```

Check `inactive = false` and `display` matches. Then **read the finding site
attribute** (`363698007`) directly from the response — this is the body
structure concept ID you will use as the procedure site filter value in
Phase 4.

```
# Coronary arteriosclerosis (53741008)
# 363698007 (Finding site) = 41801008 (Coronary artery structure)  ← pivot
```

> **This pivot step is the bridge between the diagnosis code and the
> procedure ValueSet.** The disorder’s finding site becomes the procedure’s
> site filter value.

### Phase 4 — Discover the procedure site attribute

Before building the filter, look up one known representative procedure from
the target domain to confirm which attribute it uses. Run this **in parallel
with Phase 3** if you already have a candidate procedure in mind.

```
codesystem_lookup("415070008", "http://snomed.info/sct")  # PCI
# 363704007 (Procedure site - Direct)   = 41801008  ← present
# 405813007 (Procedure site - Indirect) = 41801008  ← also present

codesystem_lookup("232717009", "http://snomed.info/sct")  # CABG
# 363704007 (Procedure site - Direct)   = — not present
# 405813007 (Procedure site - Indirect) = 41801008  ← only Indirect
```

**Rule:** use `405813007` (Indirect) when it appears on all representative
concepts. `363704007` (Direct) alone will miss procedures coded only to
Indirect. When unsure, look up two or three known procedures and check.

### Phase 5 — Build the ValueSet filter

Use the confirmed site attribute + pivot concept ID + procedure hierarchy:

```json
{
  "resourceType": "ValueSet",
  "name": "CoronaryArteryProcedures",
  "title": "Procedures on the Coronary Artery",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://snomed.info/sct",
      "version": "<from list_available_codesystem_versions>",
      "filter": [
        { "property": "405813007", "op": "=",   "value": "41801008" },
        { "property": "concept",   "op": "is-a", "value": "71388002" },
        { "property": "inactive",  "op": "=",   "value": "false" }
      ]
    }]
  }
}
```

> `71388002` is the SNOMED root for Procedure. Always include it to avoid
> non-procedure concepts that may also encode a procedure site attribute.

---

## Source System Guidance

### ICD-10-CM → SNOMED

ICD-10-CM codes map well to SNOMED disorders and findings.

| ICD-10 code type | Target SNOMED semantic tag |
|---|---|
| Diagnosis codes (A–Z chapters) | `(disorder)` |
| Symptom codes (R chapter) | `(finding)` |
| External cause codes (V–Y) | `(event)` or `(finding)` |
| Z codes (factors influencing health) | `(situation)` or `(finding)` |

**Tip:** ICD-10 codes are intentionally coarser than SNOMED. A single ICD-10
code can map to multiple SNOMED concepts. Choose the most clinically
appropriate one for the query goal.

**Example crossmap:**
```
ICD-10:  E11.9  "Type 2 diabetes mellitus without complications"
SNOMED:  44054006  "Type 2 diabetes mellitus"  (disorder)
```

Once mapped, SNOMED lets you find:
- All disorders with `causative agent = insulin resistance mechanism`
- All subtypes via `concept is-a 44054006`
- All finding sites affected: `363698007 = <pancreas / various>`

### RxNorm → SNOMED

RxNorm ingredients map to SNOMED substances or products.

| RxNorm TTY | Target SNOMED semantic tag |
|---|---|
| `IN` (Ingredient) | `(substance)` |
| `BN` (Brand Name) | `(product)` |
| `SCD` (Semantic Clinical Drug) | `(product)` |

**Example crossmap:**
```
RxNorm:  1049502  "metformin 500 MG Oral Tablet"
→ Strip to ingredient: metformin
SNOMED:  372567009  "Metformin"  (substance)
```

Once mapped, SNOMED lets you find:
- Disorders where this substance is the causative agent (`246075003`)
- Procedures that use this substance
- Other substances in the same chemical class via hierarchy

**RxNorm ingredient extraction tip:** If the RxNorm code is a `SCD`/`SBD`
(drug + dose form + strength), first extract just the ingredient name using
`codesystem_lookup` then search SNOMED on the ingredient name alone.

### LOINC → SNOMED

LOINC observation codes map to SNOMED observable entities or procedures.

| LOINC CLASS | Target SNOMED semantic tag |
|---|---|
| `CHEM` (Chemistry) | `(observable entity)` — but see caveat below |
| `HEM/BC` (Hematology) | `(observable entity)` — but see caveat below |
| `MICRO` (Microbiology) | `(procedure)` |
| `RAD` (Radiology) | `(procedure)` or `(observable entity)` |

> **⚠️ SNOMED chemistry analyte caveat:** Most common chemistry lab analytes
> (glucose, creatinine, ALT, sodium, calcium, etc.) do **not** have active
> `(observable entity)` concepts in SNOMED CT. The best active pivots are
> almost always `(finding)` with a “level – finding” display, or `(procedure)`
> with a “measurement” display. **Accept the best active match from the first
> `search_snomed` call regardless of semantic tag.** Do not run additional
> search rounds specifically hunting for `(observable entity)` — it rarely
> exists for common chemistry analytes and the search will not find what isn’t there.

**Example crossmap:**
```
LOINC:   2339-0  "Glucose [Mass/volume] in Blood"
SNOMED:  33747003  "Blood glucose measurement"  (procedure)
         or
         434912009  "Blood glucose concentration"  (observable entity)
```

### Getting the COMPONENT LP code for a LOINC observation

The `COMPONENT` LP code (e.g., `LP14635-4` for Glucose) is returned directly
by `codesystem_lookup` on any LOINC observation code. Read it from the
response — do not guess it, do not search loinc.org:

```
codesystem_lookup("2345-7", "http://loinc.org")
# COMPONENT = LP14635-4 (Glucose)   ← use this in COMPONENT filter
# SYSTEM    = LP7576-4  (Ser/Plas)  ← use this in SYSTEM filter
```

### Getting the members of a LOINC panel

`codesystem_lookup` on a panel code returns the panel’s own axes but NOT its
members. To get members, expand with a `panel-parent` filter:

```json
{
  "resourceType": "ValueSet",
  "compose": {
    "include": [{
      "system": "http://loinc.org",
      "version": "<version>",
      "filter": [
        { "property": "panel-parent", "op": "=", "value": "24323-8" }
      ]
    }]
  }
}
```

Expand this with `reasonhub-skills expand` to get the full member list.

The result includes the panel code itself and any nested panel codes — filter
to unique codes before processing. Then call `codesystem_lookup` on each
member to get its `COMPONENT` and `SYSTEM` LP codes. **Do this via the
API — do not fetch individual loinc.org/CODE pages to extract LP codes.**

```
codesystem_lookup("2345-7", "http://loinc.org")
# COMPONENT = LP14635-4  ← use this in COMPONENT filter
# SYSTEM    = LP7576-4   ← note for context only — do NOT expand it (see below)
```

To find sibling observations sharing the same `COMPONENT`, use
`reasonhub-skills expand` with a `COMPONENT = <LP_CODE>` filter —
**not `search_loinc`**. `search_loinc` returns semantically similar
observations, not structurally related ones sharing the same LOINC axis.

> **Do not expand `SYSTEM`.** For CMP-class analytes, `SYSTEM = LP7576-4`
> (`Ser/Plas`) matches `1001` active LOINC codes spanning blood typing
> antibodies, food IgGs, viral loads, and oncology panels — none of them
> related to the analyte in question. Just report the LP code and count.
> `COMPONENT` is the discriminating axis for this query pattern.

```json
{
  "resourceType": "ValueSet",
  "compose": {"include": [{
    "system": "http://loinc.org",
    "version": "<version>",
    "filter": [
      { "property": "COMPONENT", "op": "=", "value": "<LP_CODE_FROM_LOOKUP>" },
      { "property": "STATUS",    "op": "=", "value": "ACTIVE" }
    ]
  }]}
}
```

> **⛔ Do not scrape loinc.org** pages to get panel structure or LP codes.
> Do not use `search_loinc` to find LP codes for analytes — `search_loinc`
> returns semantic proximity matches, not the exact LP code bound to a given
> LOINC observation. The LP code is in the `codesystem_lookup` response.
> Do not use `search_loinc` for sibling finding by COMPONENT or SYSTEM axis.
> All three are available through structured API calls.

---

## Handling Ambiguous Mappings

When `search_snomed` returns multiple plausible matches:

1. Narrow with a more specific query: add the semantic domain
   (`"myocardial infarction disorder"`, `"glucose substance"`)
2. Compare `parent` properties — the right SNOMED concept sits under the
   expected parent hierarchy
3. Use `codesystem_subsumes` to verify the candidate is in the right subtree:
   ```
   codesystem_subsumes(
     code_a="64572001",   # Disease
     code_b="<candidate>",
     system="http://snomed.info/sct"
   )
   ```
4. If still ambiguous, present candidates with their `display`, `semanticTag`,
   and `parent` names. Let the user choose.

---

## Full Example: I25.10 → SNOMED → Coronary Procedure ValueSet

**User request:** "We have I25.10 in our encounter data and need a ValueSet
of coronary procedures — PCI, CABG, angiography, stent placement."

**Phase 1 — Look up ICD-10 display:**
```
codesystem_lookup("I25.10", "http://hl7.org/fhir/sid/icd-10-cm")
# display: "Atherosclerotic heart disease of native coronary artery
#            without angina pectoris"
```

**Phase 2 — Search SNOMED (run in parallel with Phase 1 if display is known):**
```
search_snomed("coronary arteriosclerosis disorder", top_k=5)
# Top match: 53741008 "Coronary arteriosclerosis" (disorder)
```

**Phase 3 — Confirm and extract pivot (run in parallel with a known procedure lookup):**
```
codesystem_lookup("53741008", "http://snomed.info/sct")
# sufficientlyDefined = true
# 363698007 (Finding site) = 41801008 (Coronary artery structure)  ← pivot
```

**Phase 4 — Discover procedure site attribute:**
```
# Run in parallel with Phase 3
codesystem_lookup("415070008", "http://snomed.info/sct")  # PCI
# 363704007 (Direct)   = 41801008  ← present
# 405813007 (Indirect) = 41801008  ← present

codesystem_lookup("232717009", "http://snomed.info/sct")  # CABG
# 363704007 (Direct)   = — not present
# 405813007 (Indirect) = 41801008  ← only Indirect

# → use 405813007 — it covers both PCI and CABG
```

**Phase 5 — ConceptMap + ValueSet output:**

*ConceptMap (source → SNOMED pivot):*
```json
{
  "resourceType": "ConceptMap",
  "name": "I2510ToSNOMED",
  "title": "Atherosclerotic heart disease of native coronary artery without angina pectoris → SNOMED CT",
  "status": "draft",
  "sourceUri": "http://hl7.org/fhir/sid/icd-10-cm",
  "targetUri": "http://snomed.info/sct",
  "group": [{
    "source": "http://hl7.org/fhir/sid/icd-10-cm",
    "target": "http://snomed.info/sct",
    "targetVersion": "http://snomed.info/sct/731000124108/version/20250901",
    "element": [{
      "code": "I25.10",
      "display": "Atherosclerotic heart disease of native coronary artery without angina pectoris",
      "target": [{
        "code": "53741008",
        "display": "Coronary arteriosclerosis",
        "equivalence": "wider",
        "comment": "ICD-10-CM I25.10 specifies absence of angina; SNOMED 53741008 is broader. Verify clinical fit before use."
      }]
    }]
  }]
}
```

*ValueSet (procedures at pivot site):*
```json
{
  "resourceType": "ValueSet",
  "name": "CoronaryArteryProcedures",
  "title": "Procedures on the Coronary Artery (SNOMED CT)",
  "status": "draft",
  "compose": {
    "include": [{
      "system": "http://snomed.info/sct",
      "version": "http://snomed.info/sct/731000124108/version/20250901",
      "filter": [
        { "property": "405813007", "op": "=",   "value": "41801008" },
        { "property": "concept",   "op": "is-a", "value": "71388002" },
        { "property": "inactive",  "op": "=",   "value": "false" }
      ]
    }]
  }
}
```

---

## After Crossmapping

Once you have the SNOMED concept ID, follow the `snomed-semantic` skill for
the full set of relationship query patterns.

---

## Output

Every crossmap delivers **three** things.

### 1. Crossmap provenance (always)

Show the mapping chain so the user can verify it:

| Step | Code | System | Display |
|---|---|---|---|
| Source | `I25.10` | ICD-10-CM | Atherosclerotic heart disease of native coronary artery without angina pectoris |
| SNOMED match | `53741008` | SNOMED CT | Coronary arteriosclerosis |
| Pivot (finding site) | `41801008` | SNOMED CT | Coronary artery structure |

### 2. FHIR ConceptMap JSON (always)

Emit a complete `ConceptMap` resource capturing the source → SNOMED mapping.
This is the machine-readable artifact users can load into a FHIR server or
validation tool to verify the crossmap.

**Equivalence guidance** (R4 `equivalence` codes):

| Situation | Use |
|---|---|
| One-to-one, clinically exact | `equivalent` |
| ICD-10 / LOINC is coarser; SNOMED is more specific | `wider` |
| SNOMED concept covers more than the source code | `narrower` |
| Closest match but semantically imprecise | `inexact` |
| No reasonable match found | `unmatched` |

ICD-10 codes are almost always `wider` or `inexact`; note the reason in
`comment`.

**Template:**
```json
{
  "resourceType": "ConceptMap",
  "name": "<SourceCode>ToSNOMED",
  "title": "<Source display> → SNOMED CT",
  "status": "draft",
  "sourceUri": "<source_system>",
  "targetUri": "http://snomed.info/sct",
  "group": [{
    "source": "<source_system>",
    "sourceVersion": "<source_version>",
    "target": "http://snomed.info/sct",
    "targetVersion": "<snomed_version>",
    "element": [{
      "code": "<source_code>",
      "display": "<source_display>",
      "target": [{
        "code": "<snomed_code>",
        "display": "<snomed_display>",
        "equivalence": "<equivalence_code>",
        "comment": "<reason — e.g. ICD-10 is coarser; verify clinical fit>"
      }]
    }]
  }]
}
```

**Worked example (I25.10 → SNOMED):**
```json
{
  "resourceType": "ConceptMap",
  "name": "I2510ToSNOMED",
  "title": "Atherosclerotic heart disease of native coronary artery without angina pectoris → SNOMED CT",
  "status": "draft",
  "sourceUri": "http://hl7.org/fhir/sid/icd-10-cm",
  "targetUri": "http://snomed.info/sct",
  "group": [{
    "source": "http://hl7.org/fhir/sid/icd-10-cm",
    "target": "http://snomed.info/sct",
    "targetVersion": "http://snomed.info/sct/731000124108/version/20250901",
    "element": [{
      "code": "I25.10",
      "display": "Atherosclerotic heart disease of native coronary artery without angina pectoris",
      "target": [{
        "code": "53741008",
        "display": "Coronary arteriosclerosis",
        "equivalence": "wider",
        "comment": "ICD-10-CM I25.10 specifies absence of angina; SNOMED 53741008 is broader. Verify clinical fit before use."
      }]
    }]
  }]
}
```

> **Always include both `display` values** (source and target) so the
> ConceptMap is human-readable without a terminology server lookup.

### 3. FHIR ValueSet JSON + optional expansion

Deliver the complete `ValueSet` resource. Then ask:

> "Would you like me to expand this to preview the matching procedure codes?
> I can show results as a **markdown table** or **CSV**."

Attempt `valueset_expand` **once** if the user says yes. If expansion
returns fewer rows than `total`, label the output as partial and stop.
Do not retry. See [**`reasonhub-expand-mechanics`**](../reasonhub-expand-mechanics/SKILL.md)
for expand failures, CLI fallback, and debugging.

**CSV format:**
```csv
code,display
415070008,"Percutaneous coronary intervention"
232717009,"Coronary artery bypass graft"
33367005,"Angiography of coronary artery"
```

---


# ValueSet Expansion Mechanics

Shared reference used by `snomed-semantic`, `clinical-search`, and
`terminology-crossmap`. Not triggered directly by user queries.

---

## Before Expanding — Always Include `version`

Every `compose.include` block must specify `"version"`. Call this first if
you don’t already have the version string:

```
list_available_codesystem_versions()
```

Omitting `version` causes the expand to fail silently or use an unexpected
default.

---

## `valueset_expand` Failures — Symptom and Fix

In some agent harnesses the `valueset` parameter — typed as a `$ref` schema
object — is serialised as a plain string before the tool call is dispatched.
The MCP server receives a string instead of an object and responds with:

```
valueset: must be object / must be null / must match a schema in anyOf
```

This is a known issue in **pi** (XML `<parameter>` tag serialisation) and
may surface in other harnesses that do not handle nested JSON objects in
tool parameters. The symptom is the same regardless of harness.

**This error cannot be fixed by:**
- Reformatting the JSON (pretty-print vs compact)
- Removing optional parameters like `count` or `offset`
- Different quoting or escaping
- Retrying the same call

**Do not retry. Do not offer alternatives. Immediately run
`reasonhub-skills expand` instead.**

---

## `reasonhub-skills expand` — Universal CLI Fallback

This is the recommended fallback whenever `valueset_expand` fails or
times out, regardless of which agent harness is in use.

```bash
echo '{ ... paste ValueSet JSON here ... }' | reasonhub-skills expand
```

> **If this fails with `stdin is closed`** or prints help text, the CLI
> is outdated. Upgrade it:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills \
>   -o ~/.local/bin/reasonhub-skills && chmod +x ~/.local/bin/reasonhub-skills
> ```
> If you cannot upgrade immediately, add `--count 100` as a workaround:
> `echo '...' | reasonhub-skills expand --count 100`
>
> **Do not run both the `echo |` form and the `mktemp` form in parallel.**
> They are alternatives. Pick one, run it, use the output.

If the CLI is not installed at all:
```bash
curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills \
  -o ~/.local/bin/reasonhub-skills && chmod +x ~/.local/bin/reasonhub-skills
```

> **⛔ Do not read credentials yourself.** Do not read `~/.reasonhub/config.toml`,
> `.reasonhub/config.toml`, `~/.pi/agent/mcp.json`, or any env var to extract
> a token and hand-roll a curl command. The `reasonhub-skills` CLI handles
> credentials internally. If you find yourself writing
> `curl ... -H "Authorization: Bearer ..."` with a token you read from a
> file, stop and use the CLI instead.

---

## Truncated Expansions

The MCP transport layer truncates returned rows regardless of the `count`
parameter. After a successful expansion, check `total` in the response.
**If rows returned are fewer than `total`, label the output and stop:**

> ⚠️ Partial result — {n} of {total} codes shown. The full set is defined
> by the ValueSet JSON above; run it against any FHIR terminology server
> for the complete expansion.

Do not retry with different `count` or `offset` values — this will not
retrieve additional rows.

---

## Python Scripting — Bulk Expansions

When expanding many ValueSets in a loop, use `subprocess.run` with
`input=`. Do **not** use a heredoc (`<< 'EOF'`) inside a subprocess call
— it closes stdin and causes `write_stdin failed: stdin is closed`.

```python
import json, subprocess

def expand(filter_list, system, version, count=100):
    vs = {
        "resourceType": "ValueSet",
        "compose": {"include": [{
            "system": system,
            "version": version,
            "filter": filter_list
        }]}
    }
    p = subprocess.run(
        ["reasonhub-skills", "expand", f"--count={count}"],
        input=json.dumps(vs),
        text=True, capture_output=True, timeout=60
    )
    return json.loads(p.stdout)
```

Sequential calls are fine for small sets; for 20+ analytes use
`ThreadPoolExecutor`.

**Deduplication:** LOINC expansions can return the same code twice with
different display names (canonical vs. short name). Deduplicate by code
before processing:

```python
seen = {}
for c in result["expansion"].get("contains", []):
    seen.setdefault(c["code"], c["display"])
```

---

## Debugging Checklist

If `valueset_expand` or `reasonhub-skills expand` returns no results or an error:

1. **Check the version** — run `list_available_codesystem_versions()` and
   confirm the version string matches exactly.
2. **Check the property name** — run `codesystem_filter_properties(system=...)`
   to verify the property is spelled correctly for the target system.
3. **Verify the value concept** — run `codesystem_lookup` on the filter value
   to confirm it exists and is active in the right system.
4. **Test a simpler filter first** — remove all but one filter condition to
   isolate which is causing empty results.
5. **For SNOMED attribute filters** — look up a representative concept you
   expect to match and confirm it actually carries the attribute you’re
   filtering on. Primitive concepts (`sufficientlyDefined = false`) may
   have no attributes at all.
