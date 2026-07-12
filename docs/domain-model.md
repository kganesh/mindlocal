# MindLocal — Domain Model (north-star spec)

Status: design north star. The current app should be **aligned toward** this
incrementally — not rewritten. Where today's code differs, the "Current → target"
table below is the map.

---

## 1. Purpose & north star

MindLocal is a **private, on-device second brain that learns you**. It captures
your days, understands them, and — over time — reasons in *your* patterns to help
you decide better and grow.

The three ideas we've discussed are not separate products; they are concentric
layers of the same system:

| Layer | Promise | Role |
|-------|---------|------|
| Decision helper | Decide better by learning from past decisions | A vertical slice — the seed of augmentation |
| Daily diary (episodic + semantic) | Capture and understand your life | The **substrate + habit engine** |
| Second brain | Reason in your patterns; augment you | The **derived layer + proactive behaviors** |

**Wedge (how we lead):** the **daily reflection habit** — the everyday capture
that generates the data flywheel. Decision→outcome learning is the flagship
feature that proves the "it learns you" thesis. Full self-augmentation is the
horizon we grow into as data and trust accumulate.

**Core insight:** *augmentation is the decision→outcome learning loop, generalized
from "decisions" to your whole life.* Everything traces back to your own words, on
your own device.

---

## 2. Organizing principle: episodic vs semantic memory

There is **one** personal knowledge graph, organized in two memory layers plus a
derived layer and a retrieval index.

- **Episodic layer** — time-stamped things that *happened*. Append-only, immutable,
  the raw feed: Moments (journal entries), Decisions, Events, Outcomes,
  EmotionObservations.
- **Semantic layer** — distilled, slowly-changing knowledge: entities
  (Person / Organization / Location / Object) and their **temporal** relationships.
- **Derived layer** — the "you-model": Values, Convictions/Principles, Goals —
  *computed* from the episodic + semantic layers, editable by the user.
- **Retrieval index** — embeddings spanning all layers for relevance-based recall.

Data flows **episodic → extraction → semantic → (aggregation) → derived**. The
system *reasons* over semantic/derived and *grounds every claim* in episodic.

> "Temporal graph" is not a separate graph — it is the semantic graph with
> time-valid edges. "Entity graph" is the semantic sub-layer. "Knowledge graph"
> is the whole thing.

---

## 3. Node taxonomy

**Entities (semantic — POLE+O):**
- `Person`, `Organization`, `Location`, `Object`

**Episodes (episodic, time-stamped):**
- `Moment` — a journal entry / captured experience (the episodic unit)
- `Decision` — a choice the user made, with options + rationale
- `Event` — something scheduled/attended
- `Outcome` — how a decision turned out (the learning signal)
- `EmotionObservation` — a lightweight affective tag on a moment (not a heavy entity)

**Derived (semantic, the you-model):**
- `Value` — an atom the user optimizes for ("autonomy", "financial safety")
- `Conviction` / `Principle` — a derived, editable pattern of how the user thinks/decides
- `Goal` / `Intention` — forward-looking wants (from captured "hopes")

---

## 4. Edge taxonomy (typed + temporal)

Edges are typed; those that can change over time carry `validFrom` / `validTo`.

| Edge | From → To | Temporal? |
|------|-----------|-----------|
| `mentions` | Moment → Entity | no (episodic fact) |
| `relatesTo(type)` | Person → Person/Org/Location | **yes** (spouse, coworker, role…) |
| `locatedAt` | Moment/Event → Location | no |
| `decided` | Decision → (by) Me | no |
| `resultedIn` | Decision → Outcome | no |
| `feltDuring` | EmotionObservation → Moment | no |
| `triggeredBy` | EmotionObservation → Person/Event/Object | no |
| `prioritized` / `tradedOff` | Decision → Value | no |
| `evidences` | Moment/Decision/Outcome → Conviction | no |
| `progresses` | Moment/Outcome → Goal | no |

Temporal edges answer questions like "who was my manager in 2024?" and let the
graph reflect that relationships and roles change.

---

## 5. The learning loop (the augmentation engine)

```
Moment/Decision (episodic)
      │  extract Values prioritized/traded-off
      ▼
Decision ──resultedIn──▶ Outcome        (revisitAt nudge closes the loop)
      │                     │
      └───── evidences ─────┴──▶ Conviction / Principle  (derived, editable)
                                   │
                                   ▼
              Advise + capture decision-support + proactive nudges
```

- Each Decision links to an Outcome (worked out / mixed / regret / too early).
- Aggregating Decisions × Outcomes × Values × context (sleep, mood, stakes)
  yields **Convictions** ("rushed high-stakes calls tend to end in regret").
- Convictions ground Advise and surface at capture ("your history on this"),
  and drive gentle proactive nudges.

This same loop, applied beyond decisions (moments → emotions → triggers →
patterns), is what "improving strengths / reducing weaknesses" actually means —
as a **supportive mirror**, never a grade.

---

## 6. Behaviors: persistence vs domain vs services

SwiftData `@Model` classes are **persistence records**, not rich domain
aggregates. Keep them lean; put reasoning in services.

1. **Persistence** — lean `@Model`s: nodes, edges, episodes.
2. **Domain** — protocols/value types expressing the model: `Node`, `TemporalEdge`,
   `Episode`. The conceptual layer.
3. **Services (behaviors)** — extraction, entity resolution, retrieval, temporal
   queries, conviction inference, nudges.

Only *intrinsic* behavior belongs on models (e.g. `Person.matches`,
`Decision.isStale`). Traversal and cross-entity reasoning live in services.

---

## 7. Current → target mapping

| Today | Target concept | Alignment |
|-------|----------------|-----------|
| `Experience` | `Moment` (episodic) | Keep; treat as the episodic unit. Promote emotion strings → `EmotionObservation`. |
| `Person`, `PersonRelationship` | Entity graph + temporal edges | Add `validFrom`/`validTo`; generalize edges toward any entity type. |
| `Decision`, `Outcome` (`revisitAt`, `outcome`) | Decision + Outcome + learning loop | Wire `revisitAt` nudge; add `Value` refs (`prioritized`/`tradedOff`). |
| `Event` | Event (episodic) | Keep. |
| emotions as strings on `Experience` | `EmotionObservation` (+ trigger edge) | Incremental promotion. |
| hopes (strings) | `Goal` / `Intention` | Promote when needed. |
| — | `Value`, `Conviction`/`Principle` | New derived layer (the you-model). |
| — | `Organization`, `Object` | New entity types (POLE+O completion). |
| `embedding` + `SemanticRetriever` | Retrieval index across layers | Keep; extend to weight recency + importance + graph proximity. |

---

## 8. Alignment roadmap (wedge-first, incremental — no big-bang)

**Phase 0 — Habit engine (the wedge).** Make daily reflection frictionless and
rewarding (capture, nightly ritual, diary pages). This generates the data.

**Phase 1 — Close the decision→outcome loop.** Set `revisitAt` at capture; add a
revisit nudge; one-tap outcome capture. *Smallest change, unlocks all signal.*

**Phase 2 — Derived you-model.** Extract Values at capture; compute deterministic
pattern aggregates; a "How I Decide" screen (editable Convictions + outcome
scoreboard). No heavy AI yet — testable and trustworthy.

**Phase 3 — Augmentation.** AI-synthesized Convictions feed Advise; "your history
on this" at capture; gentle pattern nudges.

**Phase 4 — Graph depth.** Temporal edges; Organization/Location/Object nodes;
EmotionObservations + triggers; retrieval that traverses the graph.

---

## 9. Design principles & guardrails

- **On-device, always.** Privacy is the moat, not a feature. Nothing leaves the phone.
- **Episodic is append-only/immutable; semantic/derived is revisable.** This split
  is what keeps a second brain trustworthy.
- **Ground everything.** Every insight cites the moments/decisions behind it.
- **Editable, forgettable memory.** The user can correct or delete what's remembered.
- **Calibrated humility.** Say "based on only 4 decisions" — never over-claim or
  hallucinate about the user's life.
- **Supportive mirror, not a coach.** Reflect patterns; let the user draw conclusions.
- **Model just enough.** Don't over-ontologize ahead of features that need it.

---

## 10. Non-goals (for now)

- A cloud sync / multi-device brain (revisit later; would change the trust model).
- A generic AI chatbot untethered from the user's own data.
- Clinical / therapeutic claims.
