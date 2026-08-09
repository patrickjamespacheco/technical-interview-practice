# Technical Interview Practice — Agent Guidelines

## Repo structure

```
python/
  practice_problems/          # problem stubs (read-only during practice)
  practice_problem_answers/   # cw_answer_XX_... files (filled in by Charlie)
  tests/                      # pytest suites
react/
  practice_problems/          # JSX/TSX starter files
  src/App.jsx                 # active problem (overwrite with a stub to work on it)
  src/main.jsx                # Vite entry point (do not modify)
  tests/                      # Playwright e2e specs
  package.json                # Vite + Playwright deps
  playwright.config.js
  vite.config.js
swift/
  Package.swift
  practice_problems/          # Swift starter files
  practice_problem_answers/   # Swift answer files
  Sources/                    # Fixed modules used by tests
  Tests/                      # Swift Testing suites
```

## React / frontend workflow

### One-time setup

```bash
cd react
npm install
```

Playwright browsers only need installing once (Chromium is used):

```bash
npx playwright install chromium
```

### Working on a problem

1. Copy the stub into `src/App.jsx` (this is the file Vite serves):

   ```bash
   cd react
   cp practice_problems/problem_02_incident_dashboard.jsx src/App.jsx
   ```

2. Start the Vite dev server to see your work in the browser:

   ```bash
   npm run dev        # opens http://localhost:5173
   ```

3. Run the Playwright tests for that problem to check your implementation:

   ```bash
   npm run test:02    # runs tests/test_problem_02_incident_dashboard.spec.js
   ```

   Or open interactive Playwright UI mode:

   ```bash
   npm run test:ui
   ```

4. Reset the placeholder when done:

   ```bash
   git restore src/App.jsx
   ```

### Test commands

| Command | What it runs |
|---|---|
| `npm run test:01` | Problem 01 — Activity Feed |
| `npm run test:02` | Problem 02 — Incident Dashboard |
| `npm run test:03` | Problem 03 — Alert Triage Console |
| `npm test` | All 3 spec files |
| `npm run test:ui` | Playwright interactive UI |

Playwright auto-starts the Vite dev server when it isn't already running.
If you already have `npm run dev` running, Playwright reuses that server.

### data-testid contract

Problems 02 and 03 specify required `data-testid` attributes in their
docstrings. The Playwright specs rely on those exact values. Problem 01 uses
role/text selectors instead (it predates this setup).

## Python virtual environment

A `.venv` lives at the repo root. Always activate it before running pytest or
any Python command:

```bash
source .venv/bin/activate
```

If `.venv` doesn't exist yet, create it:

```bash
python3.11 -m venv .venv && .venv/bin/pip install pytest
```

`run_tests.sh` activates `.venv` automatically when it exists.

---

**Workflow per problem:**
1. Problem file has the prompt + empty stubs.
2. User copies the problem file to `practice_problem_answers/cw_answer_XX_<name>.py` and implements it there.
3. He updates the test file's import to point at his answer file.
4. He runs `pytest tests/test_problem_XX_<name>.py -v` from the `python/` directory.

Test files **always** import from `practice_problems.problem_NN_<name>` (the stub).
The `--answer` flag in `python/conftest.py` injects the answer module under that same
module path before test collection, so no manual import changes are ever needed.

---

## Problem design rules

### Don't mention companies by name
You may receive prompts to design problems related to a specific company. In such a case, do
some research on said company, but try to design the problems to be something you'd generically
see in the sector/industry that company is a part of. In particular, don't use specific company
names in the code because we don't want to piss those companies off, or make them feel like 
we're stealing (which we aren't). Instead, reference a specific sector, like health tech, iot, etc..

### Parts must be self-contained
- Tests for Part N must only call methods/functions defined in Parts 1–N.
- Never verify a Part 1 result by calling a Part 2 helper.
- Any introspection method needed to check state in tests (e.g. `get_role_permissions`,
  `get_usage`, `get_all_permissions`) must live in the **earliest Part that requires it**.

### Methods must compose — no parallel implementations
Design the call chain so that Part N methods **call** Part N-1 methods rather than
re-implementing the same logic with a different return type.

**Anti-pattern to avoid:** A Part 1 method returns `bool` (e.g. `is_allowed`), then a
Part 3 method needs to do the same check but also know *why* it failed (e.g. rate-limited
per-minute vs. per-day). Because the Part 1 method only returns `bool`, Part 3 can't use
it — it has to duplicate all the logic. The candidate ends up writing the same thing twice,
which doesn't reflect good real-world design.

**How to avoid it:** Before finalising the return type of a Part N-1 method, ask: "Could
a higher-level method in a later Part use this return value directly, or would it need to
re-run the same check?" If the answer is "re-run", either:
- Make the lower-level method return richer data (an enum, a tuple, a typed dict), OR
- Introduce a private `_helper` in the problem notes that both methods can call (and
  tell the candidate to implement it first).

**Positive pattern:** Each Part should have a natural "use the method from the Part before"
moment. Design the method signatures so this composition is obvious from context — the docstring
wording and the naming of the methods should make the intended call chain clear without needing
explicit hints.

### Include a concrete usage example
Add a short `# Example` block in the problem docstring showing the data in use and
expected return values for 2–3 key operations. Interviewers always have an example;
the problem file should too.

```python
# Example
# pm = PermissionManager()
# pm.create_role("admin", ["users:write", "billing:read"])
# pm.assign_role("alice", "admin")
# pm.has_permission("alice", "billing:read")  # -> True
# pm.has_permission("alice", "posts:read")    # -> False
```

### Journey authoring contract

Journey metadata is generated from stubs, tests, `index.html`, and the small
hint-only guide. Use these exact machine-readable markers in every new stub:

- A part heading is `PART N — Title  (~N min)`. In Python, put it in the
  established separator comment as `# PART N — Title  (~N min)`; in React,
  put `* PART N — Title  (~N min)` in the opening problem comment. Number parts
  consecutively from 1.
- A concrete usage block begins with a line containing exactly `# Example` in
  Python or `* Example` in a React problem comment. Follow it with commented,
  concrete calls and their `# -> result` outcomes. Do not put the example only
  in a test file.

Legacy exceptions are recorded rather than silently rewritten: Python 01
Geofence Alert Engine has four stub parts while its index record says three and
has no usage-example block; React 02 Incident Dashboard has no usage-example
block. The generator preserves these pilots with an explicit `legacy-missing`
example status. New problems receive no exception.

When adding a problem:

1. Use the canonical part headings and concrete example above.
2. Order test classes or describes by Part.
3. Append its catalogue record to `PROBLEMS` in `index.html`.
4. Add `journey/problem_guides.yaml` prompts, concepts, steps, and pitfalls for
   every part, plus symptom/cause/check verification failures.
5. Keep guides to progressive hints: never full solution code, reference
   implementations, test assertion internals, or expected test values.
6. Regenerate with `python3 tools/build_journey_data.py`, then run
   `python3 tools/build_journey_data.py --check` and the generator tests.

The generator also writes one `journey-sources/<language>-<number>.js` file per
catalogue entry. These contain the browser-readable stub and test source and are
loaded on demand under `file://`; never edit or hand-merge them. Regenerate the
whole set after catalogue, stub, test, or generator changes.

### Use string IDs, not auto-incrementing integers
String slugs like `"admin"`, `"viewer"`, `"pk.abc123"` are more readable in tests and
don't require the caller to track state. Auto-increment belongs in DB-backed systems,
not in-memory interview problems. If the problem intentionally models a DB entity,
call it out explicitly in the docstring.

### All mutable state must be instance-level
Include this note in every class-based problem docstring:

  "Store all state in instance variables initialized in `__init__`.
   Class-level variables will bleed between tests and between PermissionManager
   instances — avoid them."

---

## Test writing rules

### Use fixtures — never inline `ClassName()` inside test methods
All tests must receive instances via pytest fixtures, not inline construction:

```python
# BAD — bleeds if implementation uses class-level state
def test_creates_role(self):
    p = PermissionManager()
    p.create_role("mod", ...)

# GOOD
def test_creates_role(self, fresh_pm):
    fresh_pm.create_role("mod", ...)
```

Provide both:
- `pm` — a fixture pre-seeded with a realistic set of roles/data
- `fresh_pm` — a bare, empty instance for tests that need a clean slate

### Use unique identifiers per test method
When multiple test methods create objects with string IDs, give each a distinct ID
(e.g. `"role_creates_test"`, `"role_dup_test"`) rather than a shared generic name
like `"mod"`. This reduces false failures when an implementation accidentally stores
state at the class level.

### The conftest safety net
`python/conftest.py` contains an `autouse` fixture (`_reset_class_level_state`) that
runs after every test and clears class-level `set` attributes and mutable default
`set` arguments on all classes found in imported practice-problem modules. This guards
against two common implementation bugs in class-based problems:

- **Class-level sets used as instance state**: `class Foo: SEEN = set()` — shared
  across all instances, persists between tests.
- **Mutable default arguments**: `def __init__(self, roles=set())` — all instances
  share the same `set` object.

This fixture is a diagnostic aid, not a substitute for fixing the implementation.
If tests only pass because of it, there is a bug to fix. Do not remove this fixture.

### Always copy module-level collections in fixtures

When a test file defines module-level data (e.g. `ALL_READINGS`, `ALL_EVENTS`) and a
fixture passes it to a constructor, **always pass a defensive copy**:

```python
import copy

# BAD — if the implementation appends to the passed list, ALL_READINGS is corrupted
@pytest.fixture
def monitor():
    return BiomarkerMonitor(ALL_READINGS)

# GOOD — for lists of immutable objects (dataclasses, strings, ints)
@pytest.fixture
def monitor():
    return BiomarkerMonitor(list(ALL_READINGS))

# GOOD — for nested/mutable structures (dicts of lists, etc.)
@pytest.fixture
def monitor():
    return BiomarkerMonitor(copy.deepcopy(ALL_DATA))
```

Without the copy, a method like `add_reading` that appends to `self._readings` (where
`self._readings` *is* `ALL_READINGS`) will permanently grow the module-level list,
causing later tests to see extra data they didn't add.

**Which copy to use:**
- `list(DATA)` — sufficient when the top-level collection is a flat list of immutable
  objects (dataclass instances, strings, ints). The list is new but the objects inside
  are shared — fine as long as the implementation doesn't mutate the objects themselves.
- `copy.deepcopy(DATA)` — required when the module-level data is a dict, a list of
  dicts, or any nested mutable structure. A shallow copy of a `dict[str, list]` still
  shares the inner lists, so `append` on an inner list still bleeds.

The conftest safety net does not catch this pattern — it only clears class-level sets
and mutable default args, not module-level collections passed in from the test file.

### Test ordering = implementation ordering
Order test classes to match the Part order. A developer who finishes Part 1 and runs
the full suite should see only Part 1 tests passing, with Part 2/3 failing cleanly
due to `NotImplementedError` — not due to test coupling.

### No cross-part dependencies in assertions
A Part 1 test must not fail simply because Part 2 hasn't been implemented. If
checking a Part 1 result requires a function slated for Part 2, move that function
to Part 1.

---

## Problem style

- Target ~45 min completion for a senior engineer.
- Frame problems around a realistic product context but keep core logic generic
  enough to apply across company types (SaaS, API platform, IoT, dev tools, etc.).
- Don't make problems company-specific unless doing targeted prep for a named role.
- Class-based problems (non-existing data structure): the candidate chooses internal data structures. 
  Say so explicitly: "You choose the internal data structures — the public interface is what
  matters."
- Class-based problems: (existing data structure): the problem should have a predefined data
  structure and the problem is just about creating application logic that modifies/utilizes that data 
- Dict-based problems: provide a `make_<thing>()` factory and a clear schema comment.

---

## Swift problem and test rules

- Preserve the global rules: parts are self-contained; Part N tests use only
  Parts 1…N; later public methods call earlier public behavior or a shared private
  helper. Every stub includes a concrete, compilable usage example and uses
  readable string IDs.
- Prefer domain types over `[String: Any]`: structs for records and snapshots;
  enums, including associated values, for finite states and rich outcomes;
  protocols only at genuine strategy or service seams; and `Result` or typed
  `throws` for expected failures. Use actors only when concurrency is the concept.
- Mutable state belongs to an instance (`struct`, `class`, or `actor`) and is
  initialized in `init`. Never use mutable global or static state; immutable
  `static let` constants are allowed. Tests use a fresh `var` for value types.
- Every `@Test` creates its own subject or calls a fixture factory such as
  `makeFreshManager()` or `makeSeededManager()`. Never share mutable suite
  properties: Swift Testing tests may run concurrently. This is the Swift
  equivalent of the pytest fresh/seeded fixture rule, not a fixture annotation.
- Give records unique IDs in each test even though correct isolation makes reuse
  harmless. This exposes accidental global or static caches.
- Module-level fixture collections must be immutable `let`. Swift arrays,
  dictionaries, and sets stored as values already provide value semantics and
  copy-on-write, so Python's `deepcopy` rule deliberately has no direct Swift
  equivalent. If fixtures contain reference elements, mutable reference graphs,
  actors, or `NSMutable*` values, factory functions must build fresh deep values.
- There is no Swift analogue of the `conftest.py` cleanup safety net. Do not
  reflect over or reset static state: that would hide the bug the test should
  catch. Every target instead includes an isolation test that mutates one
  instance and proves a second is unchanged. Swift 6 strict concurrency also
  rejects much unsafe global mutable state at compile time.
- Label/nest suites in Part order. Part 1 must pass without Part 2 implemented.
  Later stub methods fail explicitly only when invoked. Prefer a throwing
  `notImplemented` case where the signature permits it, so the test reports a
  failure instead of crashing the test worker.
- Tests import only the fixed problem module, never an answer module. The runner
  owns source substitution.
- Avoid timing sleeps. Actor and concurrency tests coordinate with continuations,
  clocks, or deterministic injected time.
- When concurrent operations accept timestamps, give competing tasks the same
  injected instant unless timestamp ordering is the behavior under test. Distinct
  synthetic times can make actor scheduling order change window membership.

## Keeping the problem index up to date

`index.html` at the repo root is a self-contained searchable index of all practice
problems. **Every time you create a new problem, add an entry to the `PROBLEMS` array**
near the top of the `<script>` block in that file (look for the comment that says
`PROBLEM INDEX — add new problems here`).

### Entry format

```javascript
{
  path: "python/practice_problems/problem_NN_<name>.py",  // path to the stub file
  test: "python/tests/test_problem_NN_<name>.py",         // path to the test file (null for React problems without a separate test)
  title: "Short Human-Readable Title",                     // shown as the card heading
  description: "One or two sentences describing what the candidate builds.",
  language: "python",           // "python" | "react"
  industry: "health-tech",      // see valid values below
  tags: ["tag-one", "tag-two"], // 2–5 kebab-case strings
  parts: 3,                     // number of implementation parts
  level: "senior"               // "junior" | "mid-level" | "senior" | "staff"
}
```

### Valid `language` values
`python` | `react` | `swift`

### Valid `level` values (in order)
`junior` | `mid-level` | `senior` | `staff`

### Suggested `industry` values (add new ones as needed, always kebab-case)
`general` | `health-tech` | `iot` | `dev-tools` | `fintech`

Use `"general"` when a problem has no clear real-world industry vertical — e.g. a
rate limiter, a permissions system, or an activity feed. These are generic software
engineering patterns that appear everywhere; tag them with the relevant product
category instead (e.g. `"saas"`, `"api-platform"`).

**Industry = real-world vertical** (healthcare, finance, logistics).
**Tag = product/platform category or algorithmic pattern** (saas, api-platform, rate-limiting).

If you introduce a **new** industry value, also add a matching CSS rule to the
`<style>` block in `index.html` so its badge renders with distinct colours:

```css
.badge-my-new-industry { background: #f0f0f0; color: #333; }
```

### Tag conventions
Kebab-case strings that describe the core algorithmic pattern or domain concept.
Examples: `sliding-window`, `rbac`, `event-driven`, `time-series`,
`consecutive-tracking`, `deadline-tracking`, `optimistic-updates`.
Aim for 2–5 tags per problem.
