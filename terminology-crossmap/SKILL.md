---
name: terminology-crossmap
description: >
  Map a code from any clinical terminology (ICD-10-CM, LOINC, RxNorm) to its
  SNOMED CT equivalent in order to unlock SNOMED's rich semantic attribute
  relationships. Use when the user has a code in a non-SNOMED system and wants
  to explore related concepts, find clinically adjacent codes, understand the
  semantic meaning, or build a SNOMED-based ValueSet from a non-SNOMED starting
  point. Always propose this when a user asks about relationships or "what is
  related to X" and the code is not already in SNOMED.
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

### Phase 1 — Get the source concept's display

```
codesystem_lookup(code="<source_code>", system="<source_system>")
```

Extract the `display` (preferred term). This is the search query for SNOMED.

**Example:**
```
codesystem_lookup(code="I21.9", system="http://hl7.org/fhir/sid/icd-10-cm")
# display: "Acute myocardial infarction, unspecified"
```

### Phase 2 — Search SNOMED for the equivalent

Use the display term (or a cleaned version of it) as the search query:

```
search_snomed(query="acute myocardial infarction", top_k=10)
```

**Selection heuristics:**
- Prefer concepts whose semantic tag matches the source system's domain:
  - ICD-10 diagnosis → `(disorder)` or `(finding)`
  - LOINC lab test → `(observable entity)` or `(procedure)`
  - RxNorm ingredient → `(substance)` or `(product)`
- Prefer `sufficientlyDefined = true` (richer attributes available)
- Prefer the most specific match (avoid selecting a parent when a child fits)
- When ambiguous, present 2–3 candidates and ask the user to confirm

### Phase 3 — Confirm the match

```
codesystem_lookup(code="<snomed_candidate>", system="http://snomed.info/sct")
```

Check:
- `display` semantically matches the source concept
- `inactive = false`
- `sufficientlyDefined` — note if `false` (primitive concept, fewer attributes)
- Review `parent` properties to confirm it sits in the expected hierarchy

### Phase 4 — Explore via SNOMED relationships

Now apply the `snomed-semantic` skill using the confirmed SNOMED concept ID.

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
| `CHEM` (Chemistry) | `(observable entity)` |
| `HEM/BC` (Hematology) | `(observable entity)` |
| `MICRO` (Microbiology) | `(procedure)` |
| `RAD` (Radiology) | `(procedure)` or `(observable entity)` |

**Example crossmap:**
```
LOINC:   2339-0  "Glucose [Mass/volume] in Blood"
SNOMED:  33747003  "Blood glucose measurement"  (procedure)
         or
         434912009  "Blood glucose concentration"  (observable entity)
```

**LOINC-specific tip:** Use the LOINC `COMPONENT` Part code (e.g., LP14635-4
for Glucose) as an additional search hint. The analyte name is usually the best
SNOMED search term.

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

## Full Example: ICD-10 → SNOMED → Semantic Query

**User request:** "I have ICD-10 code J18.9. Find all related procedures."

**Step 1 — Look up ICD-10 display:**
```
codesystem_lookup("J18.9", "http://hl7.org/fhir/sid/icd-10-cm")
# display: "Pneumonia, unspecified organism"
```

**Step 2 — Find SNOMED equivalent:**
```
search_snomed("pneumonia disorder", top_k=5)
# Top result: 233604007 "Pneumonia" (disorder)
```

**Step 3 — Confirm:**
```
codesystem_lookup("233604007", "http://snomed.info/sct")
# inactive=false, sufficientlyDefined=true
# finding site: 39607008 (Lung structure)
```

**Step 4 — Find related procedures (all procedures on lungs):**
```
valueset_expand({
  compose: { include: [{
    system: "http://snomed.info/sct",
    filter: [
      { property: "363704007", op: "=", value: "39607008" },
      { property: "concept",   op: "is-a", value: "71388002" }
    ]
  }]}
})
```

Returns: bronchoscopy, chest drain, lung biopsy, mechanical ventilation, etc.

---

## After Crossmapping

Once you have the SNOMED concept ID, follow the `snomed-semantic` skill for
the full set of relationship query patterns.
