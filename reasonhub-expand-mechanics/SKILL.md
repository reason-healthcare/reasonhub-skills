---
name: reasonhub-expand-mechanics
description: >
  Shared reference for ValueSet expansion mechanics used by all reasonhub
  skills. Covers valueset_expand failures and the CLI fallback, bulk
  scripting with Python, truncation handling, and a debugging checklist.
  Not a user-triggered skill — consulted by other skills when they need
  to expand a ValueSet or debug expansion failures.
license: MIT
compatibility: Requires ReasonHub MCP server. Sign up at reasonhub.app.
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
