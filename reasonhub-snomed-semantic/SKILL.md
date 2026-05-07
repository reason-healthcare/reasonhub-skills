---
name: reasonhub-snomed-semantic
description: >
  Use SNOMED CT's semantic attribute relationships to answer clinical questions.
  Finds concepts by relationship attribute (finding site, causative agent,
  associated morphology, procedure site), navigates the IS-A hierarchy, and
  composes property-filtered ValueSets. Use when the user asks things like
  "all disorders of the heart", "all procedures on the kidney", "all conditions
  caused by bacteria", "subtypes of hypertension", "symptoms of X",
  "complications of X", or any query that involves clinical relationships
  between concepts rather than simple text search.
license: MIT
compatibility: Requires ReasonHub MCP server. Sign up at reasonhub.app.
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
| `363704007` | Procedure site - Direct | Procedures | Procedure site = Kidney (`64033007`) |
| `405813007` | Procedure site - Indirect | Procedures | Indirect site = Abdominal aorta |
| `370135005` | Pathological process | Disorders | Pathological process = Inflammatory (`441862004`) |
| `47429007`  | Associated with | Findings, disorders | Associated with = Hypertension (`38341003`) |
| `363713009` | Interprets | Findings | Interprets = Blood pressure (`75367002`) |
| `363714003` | Has interpretation | Findings | Has interpretation = Increased (`35105006`) |
| `255234002` | After | Procedures | After = General anaesthesia |

### How the filter works

Relationship filters are **outbound**: they find concepts where a given
attribute *points to* a target concept.

```
concept --[363698007 Finding site]--> 80891009 Heart structure
```

So `filter: property=363698007, op=, value=80891009` returns all concepts
whose "finding site" attribute equals "Heart structure".

> **What you cannot do directly:** reverse lookups ("find all concepts that
> hypertension causes"). SNOMED doesn't have a `has-symptom` attribute.
> Use the IS-A hierarchy or causative-agent filter instead.

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

Pick the best match. Body structures usually have semantic tag `(body structure)`,
organisms have `(organism)`, morphologies have `(morphologic abnormality)`.

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

### All subtypes of a condition (hierarchy)
```json
{ "property": "concept", "op": "is-a", "value": "<parent_concept_id>" }
```

### Strict descendants only (exclude the parent itself)
```json
{ "property": "concept", "op": "descendent-of", "value": "<parent_concept_id>" }
```

### Active concepts only (add to any filter set)
```json
{ "property": "inactive", "op": "=", "value": "false" }
```

---

## Translating Clinical Questions

Natural language clinical questions often don't map cleanly to a single
SNOMED attribute. Use this table to pick the best strategy, with fallbacks
when attribute coverage is thin.

| Clinical question | Best strategy | Coverage | Fallback |
|---|---|---|---|
| "All disorders of [body part]" | `363698007 = <body_structure>` + `is-a 64572001` | ✅ Good — most disorders have finding site | `is-a` on the body-site disorder parent |
| "All conditions caused by [agent]" | `246075003 = <organism/substance>` | ✅ Good — infections well-modelled | `is-a` on infectious disease hierarchy |
| "All procedures on [body part]" | `363704007 = <body_structure>` + `is-a 71388002` | ✅ Good | `is-a` on the procedure hierarchy |
| "Subtypes of [condition]" | `concept is-a <condition>` | ✅ Always works | — |
| "Symptoms / findings associated with [condition]" | `47429007 = <condition>` + `is-a 404684003` | ⚠️ Sparse — only explicitly encoded associations | See note below |
| "Complications of [condition]" | `47429007 = <condition>` + `is-a 64572001` | ⚠️ Sparse | `is-a` on complication subtypes |
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

1. **Subtypes** — the condition's descendants often *are* its more specific
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

### Worked example: "Findings associated with hypertension"

```
# Step 1 — confirm hypertension's attributes
codesystem_lookup("38341003")  →  finding site = 51840005 (Systemic circulatory system)
                                   sufficientlyDefined = false

# Step 2 — try associated with filter (likely sparse)
valueset_expand filter: 47429007 = 38341003 + is-a 404684003

# Step 3 — if sparse, pivot to finding site
valueset_expand filter: 363698007 = 51840005 + is-a 404684003
# → returns all clinical findings of the circulatory system

# Step 4 — or subtypes of hypertension itself
valueset_expand filter: concept is-a 38341003
# → essential HTN, secondary HTN, hypertensive crisis, etc.
```

---

## Worked Examples

### "All cardiac disorders"
1. Search: `search_snomed("heart structure body structure")` → `80891009` Heart structure
2. Filter: `363698007 = 80891009` inside `is-a 64572001` (Disorder)

### "All bacterial infections"
1. Search: `search_snomed("bacteria organism")` → `409822003` Bacterium
2. Filter: `246075003 = 409822003` inside `is-a 40733004` (Infectious disease)

### "All ischemic conditions"
1. Search: `search_snomed("ischemic process pathological")` → `255426005`
2. Filter: `370135005 = 255426005`

### "All renal procedures"
1. Search: `search_snomed("kidney structure body structure")` → `64033007`
2. Filter: `363704007 = 64033007` inside `is-a 71388002` (Procedure)

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

## Important Constraints

- Only **active** relationships are stored. Inactive concept attributes are
  excluded.
- **Primitive concepts** (`sufficientlyDefined = false`) may have no or fewer
  attribute relationships — they're defined only by IS-A.
- Relationship **role groups** are flattened during import. Combined attributes
  within a single role group (e.g., "finding site + associated morphology")
  are not enforced together in filters.
- No `has-symptom` attribute exists in SNOMED. Use the
  [Translating Clinical Questions](#translating-clinical-questions) section
  for the recommended strategies, including `associated with` filters,
  finding-site pivots, and hierarchy traversal.
