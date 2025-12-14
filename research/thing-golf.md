---
canonical-url: https://gist.githubusercontent.com/subtleGradient/baf6fbf62c39ff434894f6676a1b1e28/raw/88eb4866b3e71692192a8cb037ea791ec1a0d0f0/thing-golf.AGENTS.md
---

# Thing Golf v3.1 – Fear/Pain Aware PR Scoring (TS Monorepos)

Target: future AI/LLM selves with tools (git diff, FS, AST, config parsers).
Domain: TypeScript monorepo PRs.

---

## 0. Core Idea

Don’t measure lines or characters.

Measure **how much more dangerous, heavy, chaotic, betraying, and controlling** the repo becomes when a PR is merged.

- Unit: **ThingBadness**
- Baseline: **0 = neutral**
- **Higher is always worse.** Negative changes are good (they remove badness).

---

## 1. Thing

A **Thing** is one named concept delta in the PR.

Examples (each is a separate Thing):

- New / changed / deleted exported function, const, type, interface, class, enum, component.
- New / removed module that is imported somewhere.
- New / removed workspace package.
- New / removed dependency in `package.json`.
- New / changed / removed HTTP route or RPC handler.
- New / changed / removed CLI command or subcommand.
- New / changed / removed DB migration file.
- New / changed / removed CI workflow, job, or matrix axis.
- New / changed / removed env var usage (`process.env.*` etc).
- New / changed / removed test file or top-level test suite.
- New / changed / removed doc page or major section.

**Granularity rule:** count by **named unit**, not by lines.

Each Thing has:

- `change` ∈ { `NEW`, `MODIFY`, `DELETE` }

---

## 2. Good vs Bad Slices

We slice Things along **monotonic good/bad axes**.

For every slice:

- **Left = good direction** (less fear/pain).
- **Right = bad direction** (more fear/pain).
- Scoring only adds when a Thing leans to the **right** side.

### 2.1 The slices (labels + intuition)

1. **Safety vs Explosiveness**  
   - Left: **Safe** – unlikely to cause surprising breakage.  
   - Right: **Explosive** – likely to blow up prod or create landmines.

2. **Lightness vs Legacy Burden**  
   - Left: **Lighter** – fewer obligations in the future.  
   - Right: **Heavier** – more long-term stuff to maintain.

3. **Clarity vs Chaos**  
   - Left: **Clearer** – easier to understand and reason about.  
   - Right: **Chaotic** – harder to understand; more tangled.

4. **Trustworthy vs Betraying**  
   - Left: **Trustworthy** – increases others’ ability to rely on the system and on you.  
   - Right: **Betraying** – sets people up to be burned or misled.

5. **Freedom vs Control-Freak**  
   - Left: **Freer** – more healthy autonomy and flexibility.  
   - Right: **Control-Freak** – more rigid knobs, micro-config, coupling.

---

## 3. Fear/Pain meaning

Tie each bad side to human needs:

- **Explosive** → attacks **certainty** and **significance**  
  (“If this explodes, I look incompetent and everything is on fire.”)

- **Heavier** → attacks **freedom** and **variety**  
  (“I’ll spend my life servicing this instead of choosing what to work on.”)

- **Chaotic** → attacks **certainty**  
  (“I can’t even tell what this does anymore.”)

- **Betraying** → attacks **connection** and **significance**  
  (“People will stop trusting me / us if this blows up or leaks.”)

- **Control-Freak** → attacks **freedom** and **variety**  
  (“I need a ritual and 7 flags just to touch this.”)

---

## 4. Slice Table (with examples)

All examples are TS monorepo PR deltas.

| Slice label | Left label (good) | Right label (bad) | Left examples (good side) | Right examples (bad side) |
| --- | --- | --- | --- | --- |
| **Safety vs Explosiveness** | **Safe** | **Explosive** | Adding tests for existing behavior; making a dangerous CLI command safer (extra confirmation); adding idempotency to an endpoint; adding runtime guards on inputs | Adding a new public API without tests; adding a destructive CLI subcommand; introducing a breaking DB migration on a critical table; removing validation to “fix” performance |
| **Lightness vs Legacy Burden** | **Lighter** | **Heavier** | Deleting unused modules; removing dead feature flags; removing unused dependencies; replacing 3 overlapping libs with 1 | Adding a new workspace package; adding a new long-term feature flag; introducing another cross-cutting util used everywhere; adding a new persistent queue/topic/cron |
| **Clarity vs Chaos** | **Clearer** | **Chaotic** | Splitting a God-object into well-named focused modules; adding clear docs; adding tests that document edge cases; consistent renames to better names | Adding a “misc.ts” dumping ground; adding `any` casts that bypass types; adding branches without docs or tests; mixing unrelated concerns into one mega-file or mega-util |
| **Trustworthy vs Betraying** | **Trustworthy** | **Betraying** | Fixing flaky tests; making CI more honest (no hiding failures); improving health checks; clarifying error messages | Marking flaky tests `skip` to get green CI; logging PII in plain text; adding a “debug backdoor” endpoint; silently ignoring errors to “keep it running” |
| **Freedom vs Control-Freak** | **Freer** | **Control-Freak** | Simplifying config (one typed config object instead of 12 envs); collapsing redundant feature flags; removing unnecessary CI steps; loosening over-strict rules that block harmless work | Adding yet another boolean env flag; adding per-team, per-region, per-tenant special cases; coupling many modules to one central “manager”; adding blocking approvals for trivial changes |

---

## 5. Scoring Model

For each Thing `T`, we compute **five per-axis contributions**:

- `SafetyBad(T)`       ∈ ℤ (≥ 0)
- `BurdenBad(T)`       ∈ ℤ (can be negative if we remove burden)
- `ChaosBad(T)`        ∈ ℤ (≥ 0, can be negative if we remove chaos)
- `BetrayalBad(T)`     ∈ ℤ (≥ 0)
- `ControlFreakBad(T)` ∈ ℤ (≥ 0, can be negative if we remove control)

### 5.1 Base by change kind (Legacy Burden)

This axis captures **past vs future load**:

- `NEW`      → `BurdenBad += +2`
- `MODIFY`   → `BurdenBad += 0`
- `DELETE`   → `BurdenBad += -2`

All other axes default to `0` unless the Thing has properties that push it rightward.

### 5.2 Heuristic bumps per axis

These are simple, monotonic “badness” rules:

#### Safety vs Explosiveness

- If Thing touches **runtime behavior in prod** (code path that executes in prod, DB schema/data, routing, CLI used in prod):
  - `SafetyBad += 1`
- If Thing is **destructive** (delete/update bulk data, destructive CLI, risky migration):
  - `SafetyBad += 2`
- If Thing **removes safety** (removes validation, removes error handling, bypasses types with `any`):
  - `SafetyBad += 2`
- If Thing **adds explicit safety** (new validation, circuit breaker, idempotency, rollback path):
  - `SafetyBad += -1` (safer)

#### Lightness vs Legacy Burden

Already covered by NEW/MODIFY/DELETE, plus:

- If Thing is a new **public runtime surface** (exported API, route, CLI command, queue/cron):
  - `BurdenBad += 2`
- If Thing is a new **cross-cutting dependency** (kitchen sink util, new global manager, new global config):
  - `BurdenBad += 2`
- If Thing **removes** such a surface or dependency:
  - `BurdenBad += -2`

#### Clarity vs Chaos

- If Thing **adds structure** (more precise types, strict TS, clear module boundaries, better naming, docs/tests that document behavior):
  - `ChaosBad += -1`
- If Thing **punches holes in structure** (casts to `any`, “misc.ts”, dumping unrelated behaviors together, magic strings, ad-hoc conditionals):
  - `ChaosBad += +2`
- If Thing **multiplies branches** without documentation/tests:
  - `ChaosBad += +1`

#### Trustworthy vs Betraying

- If Thing **makes signals more honest** (fix flakiness, make CI reflect truth, better error messages, stronger invariants):
  - `BetrayalBad += -1`
- If Thing **lies or hides failure** (skip tests to get green, swallow errors, ignore results silently):
  - `BetrayalBad += +2`
- If Thing **puts user/team at risk** (PII logging, backdoors, silent data loss):
  - `BetrayalBad += +3`

#### Freedom vs Control-Freak

- If Thing **removes unnecessary knobs** (fewer flags, simpler config, fewer approval gates, less centralization):
  - `ControlFreakBad += -1`
- If Thing **adds knobs and approvals** (new env flags, new mandatory approvals, central manager that everything must go through):
  - `ControlFreakBad += +1` (small), up to `+3` for very heavy centralization.
- If Thing **deeply couples** many modules to one “god” object:
  - `ControlFreakBad += +2`

---

## 6. Per-Thing and PR-Level Scores

For each Thing `T`:

```text
ThingBadness(T) = w_safety      * SafetyBad(T)
                + w_burden      * BurdenBad(T)
                + w_chaos       * ChaosBad(T)
                + w_betrayal    * BetrayalBad(T)
                + w_control     * ControlFreakBad(T)
