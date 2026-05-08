---
name: reasonhub-valueset-properties
description: >
  Build clinically meaningful ValueSets using the property filter system of
  each code system: SNOMED CT (attribute relationships + hierarchy), LOINC
  (CLASS/CLASSTYPE/STATUS/ORDER_OBS), RxNorm (TTY + ingredient relationships),
  ICD-10-CM (parent hierarchy), and UCUM (physical quantity). Use when the
  user wants to define a ValueSet by clinical criteria rather than enumerating
  codes manually, or when they ask "give me all X codes" for a code system.
license: MIT
compatibility: Requires ReasonHub MCP server. Sign up at reasonhub.app.
---

# ValueSet from Code System Properties

## Overview

Every code system loaded in ReasonHub exposes filter properties that let you
define ValueSets declaratively — by clinical intent rather than by listing
every code. This skill covers all five systems: what properties are available,
which are most clinically useful, and how to combine them.

For deep SNOMED semantic queries, complement this skill with `snomed-semantic`.
For starting from a non-SNOMED code, use `terminology-crossmap` first.

---

## Before You Start

Always call this first to get the exact version string for your target system:

```
list_available_codesystem_versions()
```

Every `compose.include` block **must** include `"version"`. Omitting it will
cause the expand to fail or use an unexpected default.

To see all supported filter properties for a specific system:

```
codesystem_filter_properties(system="<system_url>")
```

### ⚠️ Calling `valueset_expand` — known pi limitation

The `valueset` parameter is typed as a `$ref` schema object. **In the pi
agent, all `<parameter>` tag contents are serialized as strings**, so the
MCP server always receives `valueset` as a JSON string rather than a JSON
object. This causes the error:

```
valueset: must be object / must be null / must match a schema in anyOf
```

**This error cannot be fixed by:**
- Reformatting the JSON (pretty-print vs compact)
- Removing optional parameters like `count` or `offset`
- Trying different quoting or escaping
- Retrying the same call

All of these will produce the same error. **Do not retry. Do not offer
alternatives. Immediately run `reasonhub-skills expand` instead:**

```bash
echo '{ ... paste ValueSet JSON here ... }' | reasonhub-skills expand
```

> **If `echo '...' | reasonhub-skills expand` fails with `stdin is closed`**
> or prints help text, the installed CLI is outdated. Upgrade it:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills \
>   -o ~/.local/bin/reasonhub-skills && chmod +x ~/.local/bin/reasonhub-skills
> ```
> If you cannot upgrade immediately, add `--count 100` as a workaround:
> `echo '...' | reasonhub-skills expand --count 100`
>
> **Do not run both the `echo |` form and the `mktemp` form in parallel.**
> They are alternatives. Pick one, run it, use the output.

If the CLI is not installed:
```bash
curl -fsSL https://raw.githubusercontent.com/reason-healthcare/reasonhub-skills/main/bin/reasonhub-skills \
  -o ~/.local/bin/reasonhub-skills && chmod +x ~/.local/bin/reasonhub-skills
```
Then re-run the expand command above.

> **⛔ Do not read credentials yourself.** Do not read `~/.reasonhub/config.toml`,
> `.reasonhub/config.toml`, `~/.pi/agent/mcp.json`, or any env var to extract
> a token and hand-roll a curl command. The `reasonhub-skills` CLI handles
> credentials internally. If you find yourself writing `curl ... -H "Authorization:
> Bearer ..."` with a token you read from a file, stop and use the CLI instead.

---

## SNOMED CT — `http://snomed.info/sct`

SNOMED has two complementary filter mechanisms: **hierarchy** (IS-A traversal)
and **attribute equality** (semantic relationship properties). The most
powerful ValueSets combine both.

### Hierarchy filters

| `property` | `op` | Effect |
|---|---|---|
| `concept` | `is-a` | Concept + all descendants |
| `concept` | `descendent-of` | Strict descendants only (excludes named concept) |

### Property equality filters (most useful)

| `property` | Meaning | Tip |
|---|---|---|
| `363698007` | Finding site | Body structure concept ID as value |
| `246075003` | Causative agent | Organism or substance concept ID |
| `116676008` | Associated morphology | Morphologic abnormality concept ID |
| `363704007` | Procedure site - Direct | Body structure concept ID |
| `inactive` | Inactive concept flag | Use `"false"` to exclude retired codes |
| `semanticTag` | Semantic tag from FSN | `"disorder"`, `"finding"`, `"procedure"` |
| `moduleId` | SNOMED module | `731000124108` = US Edition |

### Combining filters (AND logic within one include)

```json
{
  "system": "http://snomed.info/sct",
  "version": "<version>",
  "filter": [
    { "property": "concept",   "op": "is-a", "value": "64572001" },
    { "property": "363698007", "op": "=",    "value": "80891009" },
    { "property": "inactive",  "op": "=",    "value": "false"    }
  ]
}
```
→ Active disorders whose finding site is the heart.

### Multiple include blocks (OR logic between includes)

```json
{
  "compose": {
    "include": [
      {
        "system": "http://snomed.info/sct",
        "version": "<version>",
        "filter": [{ "property": "363698007", "op": "=", "value": "80891009" }]
      },
      {
        "system": "http://snomed.info/sct",
        "version": "<version>",
        "filter": [{ "property": "363698007", "op": "=", "value": "59652004" }]
      }
    ]
  }
}
```
→ Disorders of the heart OR atrium.

### Exclude blocks

```json
{
  "compose": {
    "include": [
      {
        "system": "http://snomed.info/sct",
        "version": "<version>",
        "filter": [{ "property": "concept", "op": "is-a", "value": "64572001" }]
      }
    ],
    "exclude": [
      {
        "system": "http://snomed.info/sct",
        "version": "<version>",
        "filter": [{ "property": "concept", "op": "is-a", "value": "128139000" }]
      }
    ]
  }
}
```
→ All disorders EXCEPT musculoskeletal disorders.

---

## LOINC — `http://loinc.org`

LOINC's most useful filters are flat property equalities on `CLASS`,
`CLASSTYPE`, `STATUS`, and `ORDER_OBS`. Hierarchy (`parent`, `panel-parent`)
is available but less commonly needed.

### Most useful property filters

| `property` | `op` | Key values | Use for |
|---|---|---|---|
| `CLASS` | `=` or `in` | `CHEM`, `HEM/BC`, `MICRO`, `RAD`, `CARD`, `UA`, `COAG` | Discipline/panel type |
| `CLASSTYPE` | `=` | `1`=Lab, `2`=Clinical, `3`=Claims, `4`=Survey | Broad category |
| `STATUS` | `=` | `ACTIVE`, `DEPRECATED`, `DISCOURAGED`, `TRIAL` | Lifecycle |
| `ORDER_OBS` | `=` or `in` | `Order`, `Observation`, `Both` | Ordering vs reporting |
| `SCALE_TYP` | `=` | `LP7753-9`=Qn (quantitative), `LP7751-3`=Ord (ordinal) | Numeric vs categorical |

### Hierarchy filters

| `property` | `op` | `value` | Effect |
|---|---|---|---|
| `parent` | `is-a` | LOINC or LP code | Code + all descendants in component hierarchy |
| `panel-parent` | `=` | LOINC code | All codes that are direct members of that panel |

> **`panel-parent` is exact match (`=`), not `is-a`.** Use `=` to get the
> direct members of a specific panel. `codesystem_lookup` on the panel code
> itself returns the panel’s own axes but NOT its members.

### Getting LP codes for COMPONENT and SYSTEM filters

Always read LP codes from `codesystem_lookup` — never guess them.

```
codesystem_lookup("2345-7", "http://loinc.org")
# → COMPONENT property → LP14635-4 (Glucose)
# → SYSTEM property    → LP7576-4  (Ser/Plas)
```

Using an incorrect LP code returns either 0 results or completely unrelated
codes (a wrong GFR LP code returned Babesia concepts in testing).

### Common patterns

**All active quantitative lab chemistry tests (orderable):**
```json
{
  "system": "http://loinc.org",
  "version": "<version>",
  "filter": [
    { "property": "CLASS",     "op": "=", "value": "CHEM" },
    { "property": "CLASSTYPE", "op": "=", "value": "1" },
    { "property": "STATUS",    "op": "=", "value": "ACTIVE" },
    { "property": "ORDER_OBS", "op": "in","value": "Order,Both" },
    { "property": "SCALE_TYP", "op": "=", "value": "LP7753-9" }
  ]
}
```

**All active hematology and chemistry tests:**
```json
{
  "filter": [
    { "property": "CLASS",  "op": "in", "value": "CHEM,HEM/BC" },
    { "property": "STATUS", "op": "=",  "value": "ACTIVE" }
  ]
}
```

**All radiology observation codes:**
```json
{
  "filter": [
    { "property": "CLASS",     "op": "=", "value": "RAD" },
    { "property": "ORDER_OBS", "op": "=", "value": "Observation" }
  ]
}
```

**Finding UCUM units:** After expanding a LOINC ValueSet, call
`codesystem_lookup` on any result code to get its `EXAMPLE_UCUM_UNITS`
property for the recommended observation unit.

---

## RxNorm — `http://www.nlm.nih.gov/research/umls/rxnorm`

RxNorm's most powerful filter is `TTY` (term type). It defines what *level*
of drug granularity you want. Relationship filters (`has_ingredient`,
`tradename_of`, etc.) let you build ingredient-centric sets.

### TTY filter — choose your granularity

| TTY | Meaning | When to use |
|---|---|---|
| `IN` | Ingredient | Drug class ValueSets, formulary by active substance |
| `SCD` | Semantic Clinical Drug (generic) | Prescribing, order entry (no brand) |
| `SBD` | Semantic Branded Drug | Brand-specific formulary |
| `SCDF` | Semantic Clinical Drug Form | Dose-form-level grouping |
| `BN` | Brand Name | Brand lookups |
| `GPCK` / `BPCK` | Generic/Branded Pack | Package-level |

### Relationship filters (combine with TTY)

| `property` | Meaning | Value type |
|---|---|---|
| `has_ingredient` | Drug contains this ingredient | RxCUI of ingredient |
| `tradename_of` | Brand of this generic | RxCUI of generic SCD |
| `has_dose_form` | Drug has this dose form | RxCUI of dose form |
| `has_doseformgroup` | Drug has this dose form group | RxCUI of DFG |

### Common patterns

**All generic oral solid clinical drugs:**
```json
{
  "filter": [
    { "property": "TTY",           "op": "=",  "value": "SCD" },
    { "property": "has_doseformgroup", "op": "=", "value": "316945" },
    { "property": "inactive",      "op": "=",  "value": "false" }
  ]
}
```
(316945 = Oral Solid Dosage Form Group)

**All clinical drugs containing metformin (RxCUI 6809):**
```json
{
  "filter": [
    { "property": "TTY",           "op": "in", "value": "SCD,SCDF,SBD" },
    { "property": "has_ingredient", "op": "=", "value": "6809" }
  ]
}
```

**All ingredients only (for drug class ValueSet):**
```json
{
  "filter": [
    { "property": "TTY",      "op": "=",   "value": "IN" },
    { "property": "inactive", "op": "=",   "value": "false" }
  ]
}
```

**Tip:** RxNorm hierarchy (via `parent is-a`) is sparse — IS-A traversal rarely
returns what you want. Prefer `TTY` + relationship filters.

---

## ICD-10-CM — `http://hl7.org/fhir/sid/icd-10-cm`

ICD-10-CM's primary filter mechanism is its **tabular hierarchy** via `parent`.
Property equality filters exist but are mostly free-text and not useful for
filtering.

### Hierarchy filters

| `property` | `op` | Effect |
|---|---|---|
| `parent` | `is-a` | Code + all child codes in the tabular classification |
| `parent` | `descendent-of` | Strict children only |

### Common patterns

**All diabetes codes:**
```json
{ "property": "parent", "op": "is-a", "value": "E11" }
```

**All respiratory disease codes:**
```json
{ "property": "parent", "op": "is-a", "value": "J00-J99" }
```

**Multiple chapters (OR, two includes):**
```json
{
  "compose": {
    "include": [
      {
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "version": "<version>",
        "filter": [{ "property": "parent", "op": "is-a", "value": "I00-I99" }]
      },
      {
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "version": "<version>",
        "filter": [{ "property": "parent", "op": "is-a", "value": "J00-J99" }]
      }
    ]
  }
}
```
→ All cardiovascular OR respiratory codes.

**Tip:** ICD-10-CM hierarchy is very shallow compared to SNOMED. For richer
subsetting, crossmap to SNOMED first (see `terminology-crossmap` skill).

---

## UCUM — `http://unitsofmeasure.org`

UCUM is compositional — compound expressions like `mg/dL` are not indexed.
Filters operate only on the ~336 base and derived atom units.

### Most useful filters

| `property` | `op` | Values | Effect |
|---|---|---|---|
| `property` | `=` | Physical quantity name | All units measuring that quantity |
| `CLASS` | `=` | `si`, `clinical`, `cgs`, `intcust`, `dimless` | Units by class |
| `isMetric` | `=` | `yes` / `no` | Metric-prefixable units only |

### Common patterns

**All mass units:**
```json
{ "property": "property", "op": "=", "value": "mass" }
```

**All clinical concentration units:**
```json
{
  "filter": [
    { "property": "CLASS",    "op": "=", "value": "clinical" },
    { "property": "property", "op": "=", "value": "mass concentration" }
  ]
}
```

**Validating a composed expression (mg/dL, mmol/L, etc.):**
```
codesystem_verify_code(code="mg/dL", system="http://unitsofmeasure.org")
```
Use this instead of expand for composed expressions — they won't appear in
an expansion but are valid UCUM codes.

---

## Cross-System ValueSets

ValueSets can mix multiple code systems in one compose:

```json
{
  "compose": {
    "include": [
      {
        "system": "http://snomed.info/sct",
        "version": "<version>",
        "filter": [{ "property": "concept", "op": "is-a", "value": "64572001" }]
      },
      {
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "version": "<version>",
        "filter": [{ "property": "parent", "op": "is-a", "value": "I00-I99" }]
      }
    ]
  }
}
```

---

## Scripting bulk expansions with `reasonhub-skills`

When expanding many ValueSets in a loop (e.g., one per LOINC COMPONENT),
call `reasonhub-skills expand` from Python via `subprocess.run` with
`input=` — do **not** use a heredoc (`<< 'EOF'`) with nested subprocess
calls; that closes stdin and causes `write_stdin failed: stdin is closed`.

```python
import json, subprocess

def expand(filter_list, version="2.81", count=5):
    vs = {
        "resourceType": "ValueSet",
        "compose": {"include": [{
            "system": "http://loinc.org",
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

# Call once per analyte — sequential is fine for small sets;
# for 20+ analytes consider asyncio or ThreadPoolExecutor
result = expand([{"property": "COMPONENT", "op": "=", "value": "LP14635-4"},
                 {"property": "STATUS",    "op": "=", "value": "ACTIVE"}])
print(result["expansion"]["total"])  # 137 active Glucose terms
```

**Deduplication:** LOINC expansions often return the same code twice with
different display names (canonical vs. short name). Deduplicate by code
before processing:
```python
seen = {}
for c in result["expansion"].get("contains", []):
    seen.setdefault(c["code"], c["display"])
```

---

## Decision Guide — Which System to Use

| Clinical goal | Best system | Key filter |
|---|---|---|
| Clinical conditions with rich semantic subsetting | SNOMED CT | Attribute + hierarchy |
| Administrative diagnosis coding (billing) | ICD-10-CM | `parent is-a` |
| Lab observation panels and results | LOINC | `CLASS` + `STATUS` |
| Medication formulary (ordering) | RxNorm | `TTY=SCD` + `has_ingredient` |
| Medication formulary (ingredient class) | RxNorm | `TTY=IN` |
| Observation units | UCUM | `property` or verify composed |
| Rich semantic subsetting from a non-SNOMED starting point | Crossmap to SNOMED | See `terminology-crossmap` |

---

## Debugging Expansions

If `valueset_expand` returns no results or an error:

1. **Check the version** — run `list_available_codesystem_versions()` and
   confirm the version string matches exactly.
2. **Check the property code** — run `codesystem_filter_properties(system=...)`
   to verify the property code is spelled correctly.
3. **Verify the value concept** — run `codesystem_lookup` on the filter value
   to confirm it exists and is active in the right system.
4. **Test a simpler filter first** — remove all but one filter condition to
   isolate which condition is causing empty results.
5. **For SNOMED attribute filters** — look up a representative concept you
   expect to match and confirm it actually has the attribute you're filtering on.

---

## Output

Every query produces two deliverables.

### 1. FHIR ValueSet JSON (always deliver this)

Return a complete `ValueSet` resource with `name`, `title`, `status`, and a
populated `compose.include`. This is always useful regardless of whether
expansion succeeds or fails.

### 2. Expansion (ask the user)

After delivering the ValueSet JSON, ask:

> "Would you like me to expand this and show the matching codes?
> I can format results as a **markdown table** or **CSV**."

Attempt `valueset_expand` **once** if the user says yes. On failure,
**immediately run `reasonhub-skills expand`** with the same ValueSet JSON
— do not explain, do not offer alternatives, just run it.

If expansion succeeds, check the response for a `total` count. The MCP
transport layer truncates returned rows regardless of the `count` parameter,
and `offset`-based paging is unreliable. **If rows returned are fewer than
`total`, label the output explicitly and stop:**

> ⚠️ Partial result — {n} of {total} codes shown. The full set is defined
> by the ValueSet JSON above; run it against any FHIR terminology server
> for the complete expansion.

Do not retry with different `count` or `offset` values — this will not
retrieve additional rows.

**Markdown table** (default):
| Code | Display |
|---|---|
| `44054006` | Type 2 diabetes mellitus |

**CSV** (when the user asks to download, import, or use in a spreadsheet):
```csv
code,display
44054006,"Type 2 diabetes mellitus"
```

For SNOMED, add `semanticTag` as a third column when the expansion mixes
concept types. For LOINC, `EXAMPLE_UCUM_UNITS` is a useful addition for
quantitative observation sets. For RxNorm, `TTY` clarifies whether each
row is an ingredient, clinical drug, or branded product.
