# Orbit — Design Language: "Two Rooms"

**Status:** Ratified 2026-07-27 (direction V3, chosen from nine explored candidates A–I plus three composites).
**Governs:** every user-facing surface. Companion to [ORBIT.md](../ORBIT.md) (product) and [DATA-MODEL.md](DATA-MODEL.md) (schema).
**Reference mockups:** [prototype/v3-mockup.html](prototype/v3-mockup.html) — the CSS custom properties in that file are the canonical token values; this document explains them. [prototype/flow-mockup.html](prototype/flow-mockup.html) (capture flow, both rooms) and [prototype/home-search-mockup.html](prototype/home-search-mockup.html) (home & search) are the ratified surface mockups. The nine exploration directions and three composites that led to V3 were removed after ratification (2026-07-28); their rationale survives in this document.

---

## 1. Why it looks the way it does

The visual language is derived from the Product Constitution, not from taste. Four principles are load-bearing:

| Principle | Visual mandate |
| --- | --- |
| **P10 — memory, not administration** | Nothing may read as dashboard, inbox, or queue. No badges, no counters-as-debt, no red. Materials are warm (paper, sky), never clinical. |
| **P7 — small details matter** | The user's remembered words are typographically sacred: they get their own voice (§4) and their own emphasis treatment (§5.5). |
| **§15 — calm under pressure** | The brief is read in ~90 anxious seconds. Fixed skeleton, predictable positions, high glanceability, no motion that demands attention. |
| **P6 — no scores** | Nothing visual may imply ranking of people: no progress rings around avatars, no color-coded relationship health, no sorted-by-anything people lists in chrome. |

Everything below is an implementation of these four.

---

## 2. The core idea: two rooms, one house

Orbit lives in two moods, tied to when it is actually used:

- **Day — The Desk.** Preparing to see someone: papers and kept photographs laid out before a meeting. Material: photo-paper. Warm off-whites, print borders, one tilted sticky note.
- **Night — The Sky.** Capturing after a dinner, thinking about someone late: stepping outside at night. Material: the night sky. Deep indigo, faint star dust, ember light.

**The rule that joins them: bones constant, atmosphere variable.**

Constant across both rooms — never varies:

1. **Geometry.** Layout, grid, section order, radii, spacing, avatar shape.
2. **Typography.** Both voices (§4), all sizes, all weights.
3. **The ember continuum.** One accent hue family in two lights: **sepia by day (`#8A5F36`), amber by night (`#E6B273`)**. These are the *same conceptual color* — ember — under different light. No other accent colors exist.
4. **Copy.** Identical words in both rooms.

Variable — atmosphere only:

1. Surface materials (paper → sky-glass).
2. Decorative physics: things *tilt and cast shadows* by day (paper obeys gravity); things *glow* by night (light replaces shadow). Nothing tilts in the sky; nothing glows in daylight.
3. Star dust (night only, §5.3).

**The translation principle.** When a signature element moves between rooms it must *translate, not disappear*. The canonical example is the portrait (§5.1): a print with a white photo-border by day becomes the same shape ringed in faint ember at night. Every new component must answer: *what is this element's night form?* If the only answer is "gone," redesign it.

Mode follows the system setting. Both rooms are first-class; neither is "premium."

---

## 3. Tokens

Canonical values live in `prototype/v3-mockup.html` as CSS custom properties. Semantic names below; never reference raw hex in implementation.

### 3.1 Surfaces

| Token | Day | Night | Usage |
| --- | --- | --- | --- |
| `room` | `#F2EFE9` | `#101423` | Screen background. The room itself. |
| `room-air` | none | 2–4 star-dust gradients (§5.3) | Atmosphere layer painted on the room, never on cards. |
| `paper` | `#FFFDF9` | `rgba(255,255,255,.042)` | Raised card surface. Night cards are translucent — the sky shows through. |
| `paper-edge` | `#E7DFD2` | `rgba(160,175,215,.15)` | Card borders, dashed separators. |
| `paper-shadow` | `0 1px 5px rgba(50,40,25,.06)` | none | Day only. Shadow is a daylight phenomenon (§2). |
| `note` | `#F8EECB` | `rgba(230,178,115,.09)` | The owe-sticky. Day: sticky-note yellow. Night: faint ember veil. |
| `note-edge` | `#EADCAE` | `rgba(230,178,115,.28)` | Sticky border. |
| `note-tilt` | `rotate(.4deg)` | none | Day only — paper obeys gravity, sky doesn't. |

### 3.2 Ink

| Token | Day | Night | Usage |
| --- | --- | --- | --- |
| `ink` | `#292520` | `#DEE3F0` | Primary text: names, claims, memory items. |
| `ink-muted` | `#6C655A` | `#8F9AB9` | Secondary: subtexts, notes, meta. |
| `ink-faint` | `#989083` | `#68749A` | Tertiary: section tags, counts, chevrons, footnotes. Never for content. |

### 3.3 Ember (the only accent)

| Token | Day | Night | Usage |
| --- | --- | --- | --- |
| `ember` | `#8A5F36` | `#E6B273` | Section-lead tags, links/"more ›", pill text, deck dots, emphasis color, ask-cards. |
| `ember-wash` | `#ECD9B4` | `rgba(230,178,115,.42)` | The 2px emphasis underline (§5.5), highlighter effects. |
| `ember-ink` | `#FFFDF9` | `#201709` | Text/glyphs *on* ember fills — near-white on day's sepia, deep umber on night's amber. Exists because amber demands dark text; never used on any other surface. |

**Rules.** Ember is the *entire* accent budget. It marks: what the system thinks matters (hero tag), what the user can act on (pill, more-links), and what is uncertain (ask cards, unverified renders). It never marks errors (there is no error red — §9), never fills large areas, and never colors more than ~5% of any screen. If a screen feels like it needs a second accent, the screen is overloaded — cut content, don't add color.

### 3.4 Portrait

| Token | Day | Night |
| --- | --- | --- |
| `portrait-bg` | `#DDD3C2` | `#1E2540` |
| `portrait-frame` | `0 0 0 4px #FFFDF9, 0 2px 8px rgba(50,40,25,.14)` — a print's white border + drop shadow | `0 0 0 1px rgba(230,178,115,.4), 0 0 18px rgba(230,178,115,.13)` — a thin ember ring + soft glow |

### 3.5 Geometry constants

| Token | Value | Notes |
| --- | --- | --- |
| `radius-card` | 13px | All tiles, collapse rows, transcript blocks. |
| `radius-portrait` | 12px | Rounded-square. Never a circle (circles read as generic social app), never a sharp rectangle (reads as file attachment). |
| `radius-pill` | 22px (full) | Actions that are modes ("Walk me in"). |
| Screen padding | 24px top, 16px sides | |
| Grid gap | 9px | Desk bento. |
| Tile padding | 13px 14px | |
| Phone-frame reference width | 360px | All px in this doc are at this reference; see §11.2 for device scaling. |

### 3.6 Buttons — three tiers, no more

| Tier | Anatomy | Use |
| --- | --- | --- |
| **Primary** | `ember` fill, `ember-ink` text, 12px radius, 600 weight | The screen's one main action ("Looks right — save this", "Done", "Yes"). At most one full-width primary per screen; proposal cards may repeat small "Yes" primaries because each card is its own decision. |
| **Secondary** | Ghost: transparent fill, 1px `pill-edge` border, `ink-muted` text | Alternatives ("Re-record", "Edit", "No"). |
| **Tertiary** | Underlined text in `ink-faint`, no container | The pressure-free option ("Later") — deliberately the least visually demanding, because deferral must never feel like a downgrade. |

The capture mic and mode-pills ("Walk me in") are not buttons in this system — the mic is the app's one large ember object (§12), pills are mode entries (§3.5 `radius-pill`). No fourth tier may be invented; if a screen seems to need one, it has too many actions.

---

## 4. Typography: the two voices

**The law: remembered content is serif; interface is sans.** This is the single strongest identity element — it survived all nine explored directions — and it is Principle 10 rendered as typography. The serif voice means *"this came from your life."* The sans voice means *"this is the tool talking."*

### 4.1 Faces

| Voice | Web/prototype | iOS | Notes |
| --- | --- | --- | --- |
| **Memory** (serif) | `'Iowan Old Style', Palatino, Georgia, serif` | **Iowan Old Style** (ships with iOS) or SF Serif "New York" | Warm, bookish, high x-height. Never italicized for emphasis (§5.5). |
| **Interface** (sans) | system stack | **SF Pro** | Default for everything not remembered. |

### 4.2 What gets which voice — the decision tree

Serif if and only if the content **originates from Abdoul's life**: names of people, memory items, verbatim quotes, hero-tile claims, sticky-note text, thread titles rendered inside memory contexts, deck card mains, transcripts, event narratives.

Sans for everything the **system** says: section tags, meta lines, buttons, counts, rationales ("she told you at dinner in June"), settings, empty states, review-card categories.

Boundary cases, decided:
- **Screen titles** ("Does this look right?", "Here's what I heard"): **sans, 20/650** — the system talking, always. The serif headers in the pre-ratification Warm Archive prototype violated this law before it was written; the law wins.
- **Thread titles in tiles** ("The Boston move"): sans-bold. They function as labels there; the serif voice returns when the thread's story is read.
- **Hero sub-line**: sans. It is the system explaining *why* it surfaced the hero — commentary, not memory.
- **"Go be present."** (deck end): serif. It's the one place the tool is allowed to speak in the memory voice, deliberately.

### 4.3 Type scale (at 360px reference)

| Role | Voice | Size/weight | Line height | Tracking |
| --- | --- | --- | --- | --- |
| Screen title | Interface | 20 / 650 | 1.25 | −0.015em |
| Person name | Memory | 22 / 600 | 1.2 | −0.01em |
| Hero claim | Memory | 17.5 / 550 | 1.52 | — |
| Deck card main | Memory | 24 / 550 | 1.46 | −0.01em |
| Memory item | Memory | 13.5 / 400 | 1.58 | — |
| Sticky text | Memory | 12.5 / 400 | 1.5 | — |
| Tile heading (`t-item`) | Interface | 12.5 / 600 | 1.4 | — |
| Body/sub/notes | Interface | 12 / 400 | 1.5 | — |
| Meta line | Interface | 12 / 400 | 1.5 | — |
| Pill / actions | Interface | 12.5 / 600 | — | — |
| More-links, counts | Interface | 11 / 600 | — | — |
| Section tag | Interface | 9 / 650 | — | +0.11em, uppercase |
| Screen kicker | Interface | 10 / 400 | — | +0.13em, uppercase |

**iOS mapping** (Dynamic Type anchors; mockup px × ~1.25): name → Title2 serif (28pt), hero → Title3 serif (22pt), memory item → Body serif (17pt), interface body → Subheadline (15pt), meta → Footnote (13pt), tag → Caption2 caps (11pt). All roles must respond to Dynamic Type; the desk grid reflows to one column at accessibility sizes.

---

## 5. The signature moves

Seven small details carry the entire identity. **All seven ship, or the identity evaporates** — this was the explicit, accepted risk of choosing V3 over the more forgiving V2: restraint means no single element is strong enough to carry the brand alone. Treat these as product requirements, not polish.

### 5.1 The portrait translation
Day: photo-print white border (4px) + drop shadow. Night: 1px ember ring + 18px soft glow. Same 12px-radius rounded square in both. This is the flagship demonstration of §2's translation principle. With a real contact photo, day mode masks it into the print; night mode dims it ~15% so the ring reads.

### 5.2 The tilted note
Exactly one element per screen may tilt: the owe-sticky, `rotate(0.4deg)`, **day only**. It exists to break the grid's perfection just enough to feel human. Never more than one tilted element per screen; never tilt at night.

### 5.3 Star dust
Night only. 2–4 pinpricks rendered as radial-gradient dots on `room-air`: 1–1.5px, white at .2–.4 opacity, **exactly one of them ember** at .4. Confined to the top ~10% of the screen. Never on cards, never animated, never parallaxed, never more than 4 — at 5+ it becomes a planetarium. By day, `room-air` is empty (the sky is still there; you just can't see stars in daylight — this is the *same* layer, not a removed one).

### 5.4 The ember continuum
Sepia by day, amber by night, one hue family (§3.3). This is what makes the rooms feel like the same product before layout is even perceived.

### 5.5 The emphasis underline
Emphasis inside memory content is a 2px `ember-wash` underline — evoking highlighter on paper by day, an underline of light by night. **Never bold, never italic, never a background fill** for emphasis within remembered text. Applied to the 1–3 most load-bearing words of an item, chosen at render time from the fact's structure (the entity, the date, the hinge) — not by a model's judgment of importance.

### 5.6 Dashed separators
Items *within* a memory stack separate with 1px dashed `paper-edge` — notebook-ruled, softer than solid. Solid borders are reserved for card edges. Dashes never separate interface elements.

### 5.7 The serif voice
§4's law, listed here because it is also the seventh identity carrier: open any screen and the serif/sans split alone should identify the app.

---

## 6. Structure: The Desk

The always-accessible profile. Ratified synthesis: **Desk as the permanent structure, Deck as an optional mode on top** (§7), collapsible rows opening into mini-pages.

### 6.1 The grid

Two columns, 9px gap. Width semantics: **full-width = editorial** (the system composed this for you), **half-width = factual** (a thing to check). Order and spans are FIXED — same §8 fixed-skeleton rationale as ever: positions must become muscle memory, and "what isn't here" must be answerable.

| # | Tile | Span | Content contract |
| --- | --- | --- | --- |
| 0 | Header | — | Portrait, name, meta line (met-when · through-whom · last-seen). No tile chrome. |
| 1 | "Walk me in" pill | — | Deck entry (§7). Hidden only when the profile has <3 tiles of content. |
| 2 | **If you remember one thing** (hero) | full | Exactly one item — the top of the recall ranking (DATA-MODEL §8), made visible. Serif claim + sans rationale sub-line. |
| 3 | **Open** (threads) | half | Top thread + one-line status; `N more ›` count. |
| 4 | **You owe** (sticky) | half | Top open loop, either direction. Tag flips: "You owe" / "Waiting on you" ↔ "Owed to you". |
| 5 | **Since you last saw her** | full | Changes between last-seen and now, per the change-detection ranking signal. |
| 6 | **Worth having back** | full | 2–3 `last_surfaced_at`-ranked items; `N more ›`. Grows before it truncates — this section is unbounded by ratified decision; era-group when >6. |
| 7 | **Timeline** row | full | Collapsed: count ("14 events since 2023"). Opens mini-page. |
| 8 | **Reach her** row | full | Collapsed: available kinds ("phone · Instagram"). Opens contact mini-page with tap-to-act affordances. |

### 6.2 Collapsible rows and mini-pages

Collapse rows (`crow`) are single-line: title + count + chevron. They open **mini-pages** (pushed full screens, same room), not accordions — accordion expansion inside the bento destroys the fixed spatial map that is the Desk's entire argument. A mini-page inherits all tokens and the section's name as its title.

### 6.3 Empty and sparse states

- A section with no content **collapses to nothing** — no empty tiles, no "no open loops!" celebration chrome. The fixed order of what *does* render preserves scanability.
- A brand-new person (one event) may have only header + hero + one memory tile. That must look composed, not broken: tiles never stretch to fill; the room simply shows more sky/paper below.
- Counts are always real. Never "99+", never rounded up.

### 6.4 Ranking

Per DATA-MODEL §8: every tile runs its own bounded query; there is no global score. The hero tile is the visible output of the "what is he most likely to have forgotten, weighted by cost of forgetting" ranking. `pinned` facts win the hero slot outright; `muted` never appear.

---

## 7. The Deck ("Walk me in")

The optional refresher — ratified as **a mode on top of the Desk, never the primary storage view** (too much history in long relationships to click through; the Desk is the home).

- **Entry:** the pill, always in position #1 on the Desk. Copy: `✦ Walk me in · 60-second refresher`.
- **Anatomy:** progress dots (2px bars, `ember` fill on progress) → tag (ember caps) → serif main (24px) → sans sub. Full-screen card, tap anywhere advances, swipe back returns. No timers, no autoplay — pacing belongs to the walker.
- **Card order = Desk order** (hero → threads → loops → changed → 1–2 forgotten), so the Deck teaches the Desk's map. 5–7 cards maximum; the Deck *selects*, it never paginates the whole profile.
- **The end card is always** `That's everything · Go be present.` — serif, the tool's one sentence in the memory voice. Sub links to the full profile.
- Deck sessions write `last_surfaced_at` on shown items (they count as surfaced).

---

## 8. Motion

Motion vocabulary: **settle, don't bounce.** The product is a calm room, not a springy toy.

| Event | Treatment |
| --- | --- |
| Screen push (mini-pages) | Standard platform push. |
| Deck advance | 180ms crossfade + 6px rise, ease-out. |
| Tile appear (profile load) | 150ms fade, 60ms stagger by grid order, once per screen entry. No slide-ins. |
| Collapse row → mini-page | Row highlights (paper brightens 4%) on touch, then push. |
| Review card settle (accept/skip/defer) | 200ms height collapse + fade to settled line, ease-in-out. |
| Star dust | **Never animates.** |
| Sticky tilt | Static. It does not waggle. Ever. |

All durations 150–250ms; nothing loops; everything respects `prefers-reduced-motion` (reduce to opacity-only, 100ms).

---

## 9. Color semantics and states

- **There is no red.** No destructive-red buttons, no error banners, no badge dots. Errors speak in plain sans ink with an ember-tinted card edge; destructive confirmation is carried by copy ("This deletes the recording — the transcript stays") and a plain button, per the harness of Principle 4/5 flows.
- **Uncertainty is ember — and sits on note material.** Ask-cards (DISAMBIGUATE) render on the `note`/`note-edge` tokens with an ember border: questions share a material family with the owe-sticky, because both are *things to handle by hand*, in both rooms. Unverified secondhand facts and low-confidence transcript spans use the dotted ember underline. Uncertainty is the *one* state allowed to visually call out, because resolving it is the user's job.
- **Hearsay chip:** `↪ Alex told you this` — faint pill, `ink-faint` text, before the claim it qualifies (per DATA-MODEL §7.6).
- **No state colors for relationships.** Orbit tiers, cadence gaps, thread staleness: all rendered as text, never as color coding (P6).

---

## 10. Microcopy

The design is half copy. Rules:

1. **Never debt language.** "Set aside," "no rush," "whenever you want them" — never "N items remaining," "overdue," "pending review."
2. **Hedges survive.** If Abdoul said "probably," the UI says "probably." The system's stated confidence never exceeds the source's ("CS, plus possibly policy").
3. **Attribution is explicit.** "She told you," "Alex told you," "you said you'd" — sourced, always.
4. **The system explains itself in rationale sub-lines** ("She told you at dinner in June, in passing") — Principle 9's context-before-contact, everywhere.
5. **Pronouns:** use the person's known pronouns; **they/them** whenever unknown. Section titles adapt ("Reach her/him/them").
6. **Lexicon (ratified):** `Walk me in` · `If you remember one thing` · `Worth having back` · `Since you last saw —` · `You owe / Owed to you` · `Open` · `Reach —` · `Saved / Skipped / Set aside` · `Done for now` / `Not now` · `Go be present.`

---

## 11. Accessibility

### 11.1 Contrast — audited, with honest flags

| Pair | Day | Night | Verdict |
| --- | --- | --- | --- |
| `ink` on `paper` | ~13:1 | ~12:1 | Pass AAA. |
| `ink-muted` on `paper` | ~6:1 | ~5.5:1 | Pass AA. |
| `ember` on `paper` | ~5.5:1 | ~7:1 (on room) | Pass AA. |
| `ink-faint` on `paper` | **~3.4:1** | **~3.6:1** | **Fails AA for text.** Acceptable only for the 9px caps *labels* under the large-text exemption argument is weak at this size — so at build time: bump tags to ≥11pt and/or darken `ink-faint` one step when rendered as text. Chevrons/decoration exempt. |

Re-verify all pairs against actual rendered values at build; these are computed from token hex, not screenshots.

### 11.2 The rest

- **Dynamic Type** on every role (§4.3); desk reflows to one column at accessibility sizes; the Deck's serif main wraps, never shrinks below Body.
- **Touch targets** ≥44pt: collapse rows, pill, review actions all clear this; the `more ›` links get an invisible 44pt hit area.
- **VoiceOver:** the serif/sans semantic split is invisible to screen readers — so it is announced structurally: memory items are labeled "from your notes:", system rationale "context:". The hero tile announces as "If you remember one thing: …". Star dust and tilt are decorative, hidden from the tree.
- **Reduce motion:** §8. **Reduce transparency:** night `paper` gets an opaque fallback (`#1A2035`).

---

## 12. Applying the language to other surfaces

The brief is the flagship; every other surface inherits:

- **Capture (recording):** follows the system mode like every surface — capture happens after breakfasts and runs as much as after late dinners, so neither room is its default. The mic button is the one large ember object in the app, in both rooms. Waveform in `ink-faint`, timer sans. The capture door also accepts **typed micro-notes** (DATA-MODEL §7.11): typed text is the transcript, everything downstream identical.
- **Transcript review:** transcript body is Memory voice on a `paper` card; low-confidence spans dotted-ember (§9); the edit affordance is a pencil pill matching §3.5. The audio-deletion notice is a plain `note`-token card — informational sticky, not a warning banner.
- **Proposal review:** structure ratified from the original interactive prototype (person-grouped cards, quotes lighting the transcript, settled grey lines, "Later" as the frictionless defer) and rendered in these tokens in `prototype/flow-mockup.html`. Verbatim quotes: Memory voice with left ember-wash rule. Note: the interactive behaviors (tap-quote-to-highlight, undo on settled lines, per-person accept-all) are specified in §6–7 prose and the flow mockup is static — re-verify feel during build.
- **Home — ratified.** The three doors from ORBIT.md §18, and nothing else: an omnisearch pill whose placeholder rotates through real query shapes (a name, a company, a fragment — teaching that they're one box); the capture mic as the room's single large ember object; and **"Today"** — at most two context items, shown only when genuinely timely (a life event in its window, a thread at its expected resolution), each carrying its reason and opening the person's brief. Today collapses entirely when nothing qualifies; the near-empty state says so plainly ("Orbit only speaks here when there's a reason"). Set-asides are a footer text line, never a card. No feed, no stats, no suggestions, no "Lately"-style recents. Mockup: `prototype/home-search-mockup.html`.
- **Search/Discover — ratified.** One field, three query shapes, results as-you-type with no search button (latency bar set by the mid-conversation check): **name** → people anchored by provenance ("met March 2023 through Alex" answers which-Sarah, not surnames); **question** → an *answer*, not matches — count first, firsthand people with time-bounded evidence, then a visually distinct **"And maybe —"** band of known-of people, each citing its source and its ask-for-intro path; **fragment** → "Probably Nikos — here's why," matched facts underlined in ember-wash, the search showing its work. Evidence lines with remembered content use the Memory voice per §4. Same mockup.

---

## 13. Anti-patterns (forbidden)

1. Red, badges, or unread counts anywhere.
2. Progress rings, health bars, streaks, or any per-person score visual (P6).
3. A second accent hue. Ember is alone.
4. Bold/italic emphasis inside memory text (must be ember-wash underline).
5. Tilting anything at night; glowing anything by day.
6. More than 4 stars, stars below the top 10%, or animated stars.
7. Serif in interface chrome or sans in remembered content.
8. Accordion expansion inside the Desk grid (mini-pages only).
9. Empty-state placeholder tiles ("Nothing here yet!").
10. Deck autoplay or timers.
11. Wilting/decay metaphors for relationship maintenance (P8 — the Garden direction was rejected partly for inviting this).
12. Rounded-up or fake counts.

---

## 14. Open items

### Deferred surfaces — designed later, deliberately, not forgotten

These have data-model support and inventoried use cases but no designed screen yet. Each is profile-reached or rare-tier, so deferral costs little now — but every one must eventually exist:

- **Timeline mini-page** — the §6.1 collapse row's destination. Chronological events for one person; the §6 "how this person changed" view lives here.
- **Contact mini-page ("Reach her")** — the other collapse row: contact points with tap-to-act affordances and the §7.8 unverified-until-used rendering for voice-derived handles.
- **Orbit-gardening session** — the occasional deliberate pass over relationship states (§12 ORBIT.md): narratives, orbits, cadences. Explicitly a *session* the user enters, never a prompt.
- **Merge flow** — "these two Sarahs are the same person": candidate surfacing, pointer-merge confirmation, unmerge (DATA-MODEL Decision 6).
- **Set-aside triage** — re-entering deferred proposals at leisure; currently assumed to reuse the review screen, needs its own entry design.
- **Export** — the whole memory out, readable (trust-tier use case).
- **Brokering/hosting** — "who should come to dinner?" / "who should Maria meet?" A multi-person *selection* surface, not a lookup — the one genuinely new interaction pattern in the deferred set. Hold until the core loop is built and the need is felt in practice.
- **Backfill portrait onboarding** — the guided first-run capture of long-standing relationships. Fully specified at the data-model level (DATA-MODEL §7.11: subject-participants, skippable serif prompts, pausable sessions, never queued, episodic/semantic history split); golden exists and is ground truth. Flow design proceeds alongside the build; PIPE-12's accuracy number against the production extractor is the remaining gate.
- **Usage journal** — the owner's private reflection surface (EVALS.md §8): local-only, feature-level never person-level, questions never goals. Periodic, quiet, probably a mini-page under settings — never a dashboard.

### Open questions

- **Real-photo portrait treatment** — masking, night dimming, and what the print border does with low-quality contact photos. Needs real photos to design against.
- **App icon** — candidate: the night portrait ring (ember circle on indigo). Unexplored.
- **Sound** — capture start/stop earcons, if any. Default: silence.
- **`ink-faint` contrast resolution** — decide bump-size vs darken at first build (§11.1).
