# Courses — Unified Hub Redesign

A first-principles redesign of the Courses experience: collapse Certified and
Community into one personalized hub, and build the progression + mastery
substrate that makes "Recommended Next" actually intelligent.

> **Status:** design record, staged for review. Nothing here is wired in yet.
> Section 10 is a phased implementation plan; Phase 1 is small and shippable.

> **The reframe:** the brief assumes two parallel course systems that just need
> merging. The code says otherwise — they're asymmetric, and the data needed for
> half the requested sections (progress bars, "continue learning", mastery)
> **does not exist yet**. This redesign is as much about building that substrate
> as about layout. That's the honest version of the task.

---

## 0. Ground truth (what actually exists today)

| Thing | Reality in the code |
|---|---|
| **Certified courses** | 6 hardcoded entries in `src/lib/certified-courses.ts`. Marketing-grade metadata + a syllabus *outline*. **No real lessons, no DB row, no enrollment, no progress.** Rendered by `CertifiedCourses.tsx` at `/certified`. |
| **Community courses** | Real DB content: `user_courses` (definition) → `course_modules` → `course_blocks` (text/quiz). Listed at `/courses` from `user_courses` where `status='published'`. Has `cover_image_url`, `level`, `depth`, `enrolled_count`. |
| **Enrollment** | `enrollments` table = `{user_id, course_slug, course_title, enrolled_at}`. Slug-only, works for both systems by coincidence. **No progress, no completion, no current lesson, no time-spent.** |
| **Progress tracking** | **Does not exist.** No `course_progress` or `lesson_progress` table anywhere. |
| **Personalization signal (exists, unused by courses)** | `user_profiles.weak_areas` / `strong_areas`, `learner_profile` (calibration: ability, pace, scaffold, lean, metacognition), `xp`, battle rating, `daily_streak`. Luna already consumes these. |
| **Discovery** | Two separate lists. `/courses` sorts by `enrolled_count`. No search, no filter, no categories, no recommendations on either page. |
| **Navigation** | Navbar LEARN group lists "Certified Courses" and "Community Courses" as two separate destinations — the split is baked into the IA. |

**Implications that drive the whole design:**
1. "Continue Learning" and every progress bar require a **new progress store**
   (Section 10, Phase 0). This is the critical-path dependency.
2. The certified/community distinction is currently a *data-source* difference,
   not a user-meaningful one. Unifying the UI means unifying the **read model**
   (one normalized course shape both sources map into).
3. A real recommendation engine can be built **now** because the signal already
   exists (`weak/strong_areas`, calibration, battle perf) — it just was never
   pointed at courses.

---

## 1. Critique of the Current Courses Experience

1. **The split is the product's, not the user's.** A learner must decide
   "certified or community?" before exploring — a provenance question they have
   no basis to answer and shouldn't care about. Two nav entries, two pages, two
   visual treatments, two mental models. Pure cognitive tax.
2. **Certified is a façade.** The six certified courses look premium but have no
   learnable content. A user who clicks "enroll" hits a dead end. This is the
   single most damaging thing in the current experience and the brief's "remove
   the distinction" instinct is right — but the fix isn't just visual.
3. **No sense of *me*.** Neither page knows who the learner is. No continue,
   no progress, no recommendation, no history. Every visit starts from zero.
4. **No progression.** Courses are an unordered grid sorted by popularity
   (`enrolled_count`) — the exact "popularity-based" anti-pattern the brief
   calls out. Nothing tells a learner what comes *after* Algebra I.
5. **No discovery.** No search, no categories, no filters. With 6 + N courses
   it's survivable; at thousands it collapses.
6. **Off-system styling.** `/courses` still uses `neon-purple`/`neon-cyan`
   labels and a hard-edged `bg-neon-purple` CTA — pre-dates the navy/gold
   refinement (see `docs/brand-system.md`). It reads as a different app than
   the landing.
7. **Dead-end enrollment.** `enrollments` records intent but nothing consumes it
   to resume, remind, or recommend. The data is written and never read back into
   the experience.

Net: two thin catalogs masquerading as a learning library, with no learner
model, no progression, and no path from "I enrolled" to "I'm learning."

---

## 2. Redesigned Information Architecture

**One destination.** Navbar LEARN collapses "Certified Courses" + "Community
Courses" → a single **Courses**. `/certified` and `/courses` both 301 → `/courses`
(the hub); deep links `/courses/$slug` keep working for any course regardless of
source.

```
/courses                     ← the unified hub (this redesign)
  ├─ Continue Learning        (your in-progress courses)
  ├─ Recommended Next         (the personalized graph)
  ├─ Learning Paths           (sequences you're on / could start)
  ├─ Discover (search)        (instant, semantic-ish)
  └─ Browse (categories)      (11 clean subjects)
/courses/$slug               ← course detail (one template, source-agnostic)
/courses/$slug/learn         ← the player (lessons/blocks)
/build-course                ← unchanged entry, surfaced contextually in-hub
```

**Provenance becomes a property, not a place.** A course carries
`source: "official" | "community"` and renders a subtle badge
(`Eclipta Official` / `Community`) on the card and detail page. It's also an
*optional filter*, never a section boundary. The IA never asks the user to pick
a side.

**One normalized course model** both sources map into (Section 6.2), so the hub,
cards, search, and recommendations are written once against a single shape.

---

## 3. Complete Layout of the New Unified Courses Page

Single column, max-width consistent with the rest of the app (`max-w-7xl`,
`px-6`), generous vertical rhythm (96px between major zones, the brand's spacing
scale). Reading order top-to-bottom mirrors intent priority.

```
┌─────────────────────────────────────────────────────────────────┐
│  COURSES                                          [ Search ⌘K ]   │  ← title + persistent search entry
│  One library. Everything you're learning, and what's next.       │
├─────────────────────────────────────────────────────────────────┤
│  ▸ CONTINUE LEARNING                                             │  ← only if user has in-progress courses
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐          │
│  │ ▓▓▓▓▓░░ 64%   │ │ ▓▓░░░░ 22%    │ │ ▓▓▓▓▓▓▓ 90%   │  → rail   │  horizontal rail, snap-scroll
│  │ Calculus I    │ │ Intro Python  │ │ Algebra II    │          │
│  │ Lesson 7 · 12m│ │ Lesson 2 · 40m│ │ Lesson 9 · 5m │          │
│  │ [ Continue → ]│ │ [ Continue → ]│ │ [ Continue → ]│          │
│  └───────────────┘ └───────────────┘ └───────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│  ▸ RECOMMENDED NEXT          why these? ⓘ                        │  ← the heart of the page
│  ┌─────────────────────────┐ ┌─────────────────────────┐         │
│  │ Calculus II             │ │ Linear Algebra          │         │
│  │ Because you finished    │ │ You're 90% ready —      │         │  each card: a course + an
│  │ Calculus I  ·  ████░ 90%│ │ strengthen vectors first│         │  EXPLICIT educational reason
│  │ [ Start ]               │ │ [ Preview ]             │         │
│  └─────────────────────────┘ └─────────────────────────┘         │
├─────────────────────────────────────────────────────────────────┤
│  ▸ YOUR LEARNING PATH                                            │  ← progression spine (Section 8)
│   Algebra I ─●─ Algebra II ─◐─ Precalc ─○─ Calc I ─○─ Calc II    │  you-are-here on a track
│   (done)       (done)         (you)      (next)    (locked)      │
├─────────────────────────────────────────────────────────────────┤
│  ▸ BROWSE                                                       │  ← 11 subject tiles, calm grid
│  [ Mathematics ] [ Science ] [ CS ] [ Engineering ] [ Business ] │
│  [ Humanities ] [ Languages ] [ Test Prep ] [ Arts ] [ Health ]  │
│  [ Personal Finance ]                                            │
└─────────────────────────────────────────────────────────────────┘
```

**First-time user** (no history) sees a different, equally intentional page:
a one-line welcome, **Browse** promoted to the top, a "Take a 2-min placement"
nudge (the existing calibration), and editor's-pick paths instead of
personalized ones. Never an empty state pretending to be personalized.

**Search** is a persistent affordance (header + `⌘K`) that expands into a
full-screen-ish overlay (Section 7) rather than a separate page — no navigation,
no context loss.

---

## 4. UX Reasoning, Section by Section

| Section | Why it exists | Why it's placed here | Progressive disclosure |
|---|---|---|---|
| **Continue Learning** | Resuming is the highest-intent, highest-frequency action for a returning learner. | Top, because a returning user's #1 job is "get back in." Hidden entirely for new users (no empty shelf). | Card shows progress + next lesson + time. Hover reveals last-opened, streak, syllabus peek. |
| **Recommended Next** | Converts a static catalog into a guide. The brief's core ask. | Directly under Continue — once you're caught up, "what next" is the next question. | Card front: course + one-line reason + readiness %. Expand: full reasoning, prereqs met/missing. |
| **Learning Path** | Gives a single course *context* — you're on a journey, not buying isolated items. | After recommendations: zoom out from "next course" to "whole arc." | Collapsed to your active track; tap to see the full graph / switch tracks. |
| **Browse** | The deliberate, self-directed entry. Also the new-user default. | Lower, because browsing is lower-intent than resuming/continuing for known users; promoted to top for new users. | 11 tiles → subject page with filters revealed on demand. |
| **Search** | Fast, intent-driven discovery; the "I know what I want" path. | Persistent (header + ⌘K), not a section — available everywhere, owns no vertical space. | Empty state shows recent + trending; typing reveals instant results, then filters. |

**Cross-cutting:** every section is a horizontal **rail** (snap-scroll) so the
page stays one calm screen-height of *zones* rather than an endless grid. Depth
comes from the brand's elevation scale and `glass-panel`, motion from the
existing easing language — not new flourishes.

---

## 5. AI Recommendation & Progression Engine

The engine answers one question per candidate course: **"should this learner do
this next, and why, in one sentence?"** Reasons are first-class output, not
decoration.

### 5.1 Architecture — a scored graph walk, not a vibe

```
            ┌──────────────────────────────────────────────┐
   inputs   │  Learner Profile (Section 6)                 │
            │  + Course Graph (prereqs, Section 8)          │
            └───────────────────────┬──────────────────────┘
                                    ▼
            ┌──────────────────────────────────────────────┐
   stage 1  │  CANDIDATE GENERATION (cheap, deterministic) │
            │  • successors of completed courses            │
            │  • courses whose prereqs are ≥ met            │
            │  • same-subject neighbors of strengths        │
            │  • remediation for active weak_areas          │
            │  • interest/goal matches                      │
            └───────────────────────┬──────────────────────┘
                                    ▼
            ┌──────────────────────────────────────────────┐
   stage 2  │  SCORING (transparent, weighted)             │
            │  readiness · relevance · goal-fit · freshness │
            │  · difficulty-match · diversity penalty       │
            └───────────────────────┬──────────────────────┘
                                    ▼
            ┌──────────────────────────────────────────────┐
   stage 3  │  REASON GENERATION                            │
            │  template from the winning signal, e.g.       │
            │  "Because you mastered Algebra I" /            │
            │  "You're 90% ready — review functions first"  │
            └──────────────────────────────────────────────┘
```

Stage 1–2 are **deterministic and fast** (runs client-side or in one cheap
query) — no LLM in the hot path, so the page is instant and recommendations are
explainable/testable. The LLM is optional and used only to (a) phrase reasons
more naturally and (b) handle cold-start "interest → subject" mapping. This is
the difference between an *intelligent* engine and a *slow, hand-wavy* one.

### 5.2 Readiness score (the number behind "you're 90% ready")

For course `C` with prerequisite concepts `P`:

```
readiness(C) = Σ_p∈P  weight(p) · mastery(user, p)        // 0–1
```

- `mastery(user, p)` comes from the unified mastery store (Section 6.3):
  completed-course credit, quiz accuracy, battle performance on `p`, minus
  decay.
- A course with all prereqs mastered → readiness ≈ 1 → "ready now."
- Partially met → "You're 72% ready — strengthen X first" with X = the lowest
  weighted prereq. **This is how a struggle in Algebra II surfaces a functions
  refresher *before* Calculus**, exactly as the brief asks.

### 5.3 Scoring weights (tunable, start here)

| Signal | Weight | Meaning |
|---|---|---|
| readiness | 0.35 | Can they actually succeed at it now? |
| goal/career fit | 0.20 | Does it serve a stated goal? |
| interest/subject affinity | 0.15 | Strong/preferred subjects, recent searches |
| progression continuity | 0.15 | Direct successor of a completed course |
| difficulty match | 0.10 | Matches calibrated `ability` ± a stretch |
| freshness/diversity | 0.05 | Don't show the same 3 forever |

Anti-recommendations are explicit: never recommend a course **below** a mastered
prereq (no "Basic Algebra" after "Calculus I"), and down-rank anything already
completed or far above readiness (unless they search for it).

### 5.4 Continuous update from mastery, not completion

Recommendations recompute on: course/lesson completion, quiz results, battle
results touching a tracked concept, a new search, and goal edits. Because
scoring reads the live mastery store, "finished the course" and "actually
understands it" are different inputs — a passed-but-shaky course yields a
*remediation* rec, not the next course. Mastery decays (reuse Luna's memory
half-life model from `docs/luna-redesign.md` §6.4) so stale "strong" fades.

---

## 6. The Learner Profile Model

Most of this **already exists** and is unused by courses. The redesign *reads*
it and adds one new store (mastery).

### 6.1 Reused signals (already in `user_profiles` / calibration)

```
weak_areas[], strong_areas[]         → remediation + affinity
learner_profile { ability, pace,     → difficulty match, pacing, scaffolding
  scaffold, lean, metacognition,
  confidence }
xp, battle rating, daily_streak      → engagement, level framing
luna_notes / luna_auto_notes         → interests, preferred subjects
```

### 6.2 Normalized course shape (the unification)

```ts
interface Course {
  id: string;
  slug: string;
  source: "official" | "community";   // becomes a badge, never a page
  title: string;
  summary: string;
  subject: SubjectFamily;             // one of the 11 Browse categories
  level: "intro" | "intermediate" | "advanced";
  cover_image_url?: string;
  est_minutes: number;
  rating?: number;
  enrolled_count: number;
  prerequisites: string[];            // concept ids (Section 8)
  teaches: string[];                  // concept ids this course confers
}
```
Certified static data and `user_courses` rows both map into this. The hub never
branches on `source`.

### 6.3 New store — `course_progress` + `concept_mastery` (the missing substrate)

```ts
// per enrolled course — powers Continue Learning
interface CourseProgress {
  user_id; course_slug;
  status: "enrolled" | "in_progress" | "paused" | "completed";
  lessons_total; lessons_done;
  current_block_id?: string;          // exact resume point
  percent: number;                    // derived
  last_opened_at: string;
  completed_at?: string;
}

// per concept — powers readiness + recommendations (shared with Luna's memory)
interface ConceptMastery {            // see luna-redesign.md §6 — same table
  user_id; concept; subject;
  state: "struggling" | "developing" | "solid" | "mastered";
  confidence: number;                 // 0–1
  evidence_count; last_seen;          // decay-driven
}
```

This is the keystone: **one mastery store serves both Luna and Courses.** Build
it once (it's already proposed in the Luna redesign) and both systems get
smarter together.

---

## 7. Search & Discovery System

**Goals:** instant, typo-tolerant, semantic-ish, no page navigation.

- **Entry:** persistent in header + global `⌘K`. Opens an overlay over the hub
  (focus trap, Esc to close) — never a route change.
- **v1 (ship first, zero infra):** client-side fuzzy index over the normalized
  course set (title, summary, tags, subject, teaches) using a small matcher
  (e.g. a trigram/`Fuse`-style score). Handles typos and partial matches
  instantly for hundreds of courses. Synonyms via a hand-curated alias map
  ("ML"→"machine learning", "maths"→"mathematics", "SAT"→"Test Prep").
- **v2 (scales to thousands):** precomputed embeddings per course (one batch job
  through the existing AI gateway), pgvector similarity for true semantic search
  ("courses to become a data scientist" → the right set). Query embedding cached;
  falls back to v1 if the vector path is cold.
- **Result anatomy:** course + readiness chip + reason if recommended.
  Zero-results never dead-ends — show closest subjects + "Build this course"
  (the existing `/build-course`), turning a miss into a creation prompt.
- **Filters are progressive:** the overlay shows results first; a single
  "Filters" affordance reveals subject / level / source / duration. Hidden until
  asked for.

---

## 8. Educational Progression Graph Architecture

A directed acyclic graph of **concepts**, with courses attached to the concepts
they teach. Courses don't depend on courses directly (brittle); they depend on
**concepts**, which decouples content from curriculum.

```
concept: "limits" ──┐
concept: "derivatives" ──depends on──> "limits"
concept: "integrals"   ──depends on──> "derivatives"

course "Calculus I"  teaches: [limits, derivatives, integrals]
course "Calculus II" teaches: [series, techniques_of_integration]
                     requires: [integrals]            ← so Calc I unlocks Calc II
```

```ts
interface ConceptNode {
  id: string;                 // "limits"
  subject: SubjectFamily;
  depends_on: string[];       // prerequisite concept ids (the DAG edges)
  label: string;
}
```

- **Why concepts, not courses:** a community course and an official course can
  teach the same concept; readiness and unlocking work uniformly. A learner who
  proves "integrals" via *any* path unlocks Calc II.
- **Path generation:** a "learning path" is a topological walk of the concept
  DAG filtered to a subject/goal, with the best course bound to each step. The
  spine in Section 3 is this walk rendered with you-are-here state.
- **Authoring:** official courses get curated `teaches`/`requires` concept tags.
  Community courses get them auto-suggested at publish time (one AI pass over
  the syllabus) and confirmed by the creator — so the graph grows without manual
  curation of every course.
- **Visualization:** elegant horizontal track (done ● / current ◐ / next ○ /
  locked ◌), not a hairball node-graph. Depth on demand: tap a node to see the
  concept and the course bound to it.

---

## 9. Edge Cases

| Case | Behavior |
|---|---|
| **Brand-new user, no history** | Browse promoted to top; "2-min placement" (existing calibration); editor's-pick paths; no fake personalization, no empty shelves. |
| **Advanced learner** | Recommendations skip mastered prereqs entirely; never shown intro content; readiness gates surface only genuine gaps; can filter to `advanced`. |
| **Returning after a break** | Continue Learning leads with a gentle "Welcome back — pick up at Lesson 7"; decayed mastery may insert a quick refresher rec ("a 5-min recap before you continue"). |
| **Interests change** | Recent searches + goal edits re-weight scoring within a session; a sustained shift (several sessions in a new subject) moves subject affinity. Old track isn't deleted — it's paused and resumable. |
| **Struggling repeatedly (e.g. Algebra II)** | Readiness drops on dependent concepts → engine recommends the specific prerequisite refresher *before* advancing, with the reason "strengthen X first." |
| **Completed everything in a subject** | Surface adjacent subjects via shared concepts ("you've got the math for ML") + community/advanced courses + "build your own." |
| **Enrolled-but-never-started (legacy `enrollments`)** | Migrated to `course_progress.status='enrolled'`; appear in Continue with a "Start" (not "Resume") CTA and 0%. |
| **Course unpublished/removed** | Continue card degrades gracefully ("no longer available"), progress archived, a similar course suggested. |
| **Certified course with no real content (today's reality)** | Until content exists, official courses without blocks are shown as "Coming soon — get notified" rather than a dead-end enroll. Honesty over façade. |

---

## 10. Implementation Plan (frontend + backend)

Phased so value ships early and the risky substrate is isolated.

### Phase 0 — Substrate (backend, unblocks everything)
- **Migration:** `course_progress` table (§6.3); extend/normalize `enrollments`
  into it. Backfill existing `enrollments` rows as `status='enrolled'`.
- **Migration:** `concept_mastery` table (shared with Luna; see luna-redesign
  §6) + `concept_nodes` (DAG) + course `teaches`/`requires` columns.
- **Read model:** a `courses_normalized` view/function mapping static certified
  + `user_courses` into the §6.2 shape (or move certified into the DB — see
  "Recommended" below).
- **Write path:** the lesson player writes progress (`current_block_id`,
  `lessons_done`, `last_opened_at`) on each block completion.

### Phase 1 — The unified hub shell (frontend, shippable on its own)
- New `/courses` hub: header + Browse (11 subjects) + Continue Learning (reads
  `course_progress`). Recommendations stubbed to "popular/editor's pick" until
  Phase 2.
- Merge Navbar LEARN → single **Courses**; `/certified` → redirect.
- Restyle onto the brand system (navy/gold, `glass-panel`, elevation) — retire
  the `neon-*` labels and hard CTA on the old `/courses`.
- One source-agnostic course card + detail template; `source` → subtle badge.

### Phase 2 — Recommendation engine (the heart)
- Implement candidate-gen + scoring (§5) reading the Phase-0 mastery store.
- Reason templates; `readiness` chips. Deterministic first, no LLM in hot path.
- Learning Path spine from the concept DAG (§8).

### Phase 3 — Search
- v1 client-side fuzzy + alias map (⌘K overlay). Ship.
- v2 embeddings + pgvector behind the same UI when catalog grows.

### Phase 4 — Intelligence polish
- Decay job (shared with Luna memory). Continuous re-scoring on quiz/battle/
  completion events. Auto-suggested concept tags at community publish time.

**Recommended sequencing call:** do Phase 0 + 1 first as one milestone — it
*alone* removes the certified/community split, kills the dead-end enroll, and
gives Continue Learning. That's the bulk of the perceived improvement at a
fraction of the total cost. The engine (Phase 2) is where it becomes special.

**One decision for you:** should certified courses **move into the DB** (so they
get real lessons, enrollment, and progress like community ones) or stay a
curated static set shown as "coming soon" until authored? The redesign strongly
recommends moving them into the DB — the static façade is the root of the
dead-end problem.

---

## 11. UI/UX Details That Make It Feel Premium

- **One calm screen of zones, not a wall of cards.** Each section is a
  snap-scroll rail; the page has rhythm (96px zone gaps), not density.
- **Progressive disclosure everywhere.** Cards are quiet by default (cover,
  title, one line); hover/focus reveals progress, reason, syllabus peek. Filters
  hidden until requested.
- **Reasons as a feature.** Every rec carries a human, specific because-line.
  This is the single biggest "feels intelligent" lever and it's cheap.
- **Readiness as a quiet ring**, not a loud number — a thin arc on the card,
  full detail on expand.
- **Motion with intent, reusing the existing easing** (`[0.2,0.7,0.2,1]` from the
  landing): content reveals on scroll-in, a shared-element transition from card →
  detail (the cover image animates into the header) so navigation feels
  continuous, progress bars that *fill* on load. No decorative motion.
- **Depth from the system**, not new shadows: `glass-panel` + the 3-step
  elevation scale; hover lifts one step.
- **`⌘K` search** signals a tool built for people who return daily.
- **Empty states that recruit, not apologize:** zero results → "Build this
  course"; finished a subject → "you've got the math for ML."
- **Skeletons, not spinners** — the hub lays out its zones immediately and fills
  them, so it never feels like it's loading from scratch.
- **Accessibility as polish:** full keyboard path (rails arrow-navigable, ⌘K,
  Esc), reduced-motion collapses reveals to fades, focus-visible rings on the
  gold ring token.

---

## 12. Ideas to Make This Best-in-Class

1. **"Ready to learn" radar.** A small per-subject readiness dial on Browse
   tiles — at a glance, where you're strongest and what's unlocked.
2. **Goal-driven path builder.** "I want to become a data scientist" → the
   engine assembles a multi-course path from the concept DAG with you-are-here
   tracking. Turns Courses into a destination, not a catalog.
3. **Mastery-gated unlocks tied to the Trophy Road.** Completing a concept lights
   it on the existing progression map — Courses and the game loop reinforce each
   other instead of living apart.
4. **Battle-to-course bridge.** Lose a battle on a topic → "Shore this up:
   [course/lesson]" with the exact weak concept. Closes the loop between the
   arena and the library (and reuses `weak_areas`).
5. **Luna as course concierge.** "What should I learn after Calculus I?" answered
   in-context by Luna, reading the same mastery store — recommendations you can
   *converse with*.
6. **Adaptive course length.** Using calibration `pace`/`chunk_size`, show a
   personalized "≈ 6 hrs for you" instead of a static duration.
7. **Spaced-repetition resurfacing.** Decayed concepts trigger a "quick recap"
   card in Continue Learning — the platform's spaced-repetition promise, finally
   real.
8. **Cohort-free social proof.** "312 learners with your background took this
   next" — provenance-neutral, progression-relevant, never just "popular."

---

## Appendix — Visual Design Philosophy (applied)

This redesign inherits, not reinvents, the established system in
`docs/brand-system.md`: midnight-navy ground, warm-ivory ink, single gold
accent; Fraunces display / Inter body / mono labels; the 3-step elevation scale;
`glass-panel`; motion easing `[0.2,0.7,0.2,1]`. "Cinematic, premium, modern" here
means **restraint executed precisely** — generous whitespace, one clear focal
point per zone (Continue → Recommended → Path → Browse), depth from light not
borders, and motion that reinforces continuity (card → detail shared element)
rather than decorating. The test for every element: *does it help the learner
continue, discover, or decide?* If not, it doesn't ship.
