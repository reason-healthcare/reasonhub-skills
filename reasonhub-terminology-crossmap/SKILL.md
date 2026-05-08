---
name: reasonhub-terminology-crossmap
description: >
  Map a code from any clinical terminology (ICD-10-CM, LOINC, RxNorm) to its
  SNOMED CT equivalent in order to unlock SNOMED's rich semantic attribute
  relationships. Use when the user has a code in a non-SNOMED system and wants
  to explore related concepts, find clinically adjacent codes, understand the
  semantic meaning, or build a SNOMED-based ValueSet from a non-SNOMED starting
  point. Always propose this when a user asks about relationships or "what is
  related to X" and the code is not already in SNOMED.
license: MIT
compatibility: Requires ReasonHub MCP server. Sign up at reasonhub.app.
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
code often maps to multiple SNOMED concepts. Choose the most clinically
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

**Phase 5 — ValueSet output:**
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

Every crossmap delivers two things.

### 1. Crossmap provenance (always)

Show the mapping chain so the user can verify it:

| Step | Code | System | Display |
|---|---|---|---|
| Source | `I25.10` | ICD-10-CM | Atherosclerotic heart disease of native coronary artery without angina pectoris |
| SNOMED match | `53741008` | SNOMED CT | Coronary arteriosclerosis |
| Pivot (finding site) | `41801008` | SNOMED CT | Coronary artery structure |

### 2. FHIR ValueSet JSON + optional expansion

Deliver the complete `ValueSet` resource. Then ask:

> "Would you like me to expand this to preview the matching procedure codes?
> I can show results as a **markdown table** or **CSV**."

Attempt `valueset_expand` **once** if the user says yes. If expansion
succeeds, check the response for a `total` count. The MCP transport layer
truncates returned rows regardless of the `count` parameter, and
`offset`-based paging is unreliable. **If rows returned are fewer than
`total`, label the output and stop:**

> ⚠️ Partial result — {n} of {total} codes shown. The full set is defined
> by the ValueSet JSON above.

Do not retry with different `count` or `offset` values.

**CSV format:**
```csv
code,display
415070008,"Percutaneous coronary intervention"
232717009,"Coronary artery bypass graft"
33367005,"Angiography of coronary artery"
```
