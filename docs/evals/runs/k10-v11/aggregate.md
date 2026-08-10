# Aggregate — k10-v11

**10 runs** · model `gpt-5.1` · prompt `v11` · git `d9c8aaa`  
collected 2026-08-10T22:05:56Z · 993,980 tokens · 1675s model time

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 75% · min 72% · max 79% |
| PIPE-4-class criticals | median 17.5 · min 15 · max 22 |

Recall spans **6.5%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **63** always extracted (stable core)
- **13** never extracted (stable miss — a real gap)
- **30** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `eliah:assertion:eliah/trait/immigrants` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:kevin/goal/woodworking` | 10% | must hedge / DISAMBIGUATE |
| `hardship:assertion:maya/concern/parkinson` | 10% | must hedge / DISAMBIGUATE |
| `homonym:person:sarah_o` | 10% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/employment/google` | 20% | must hedge / DISAMBIGUATE |
| `eliah:episode:EP-2` | 20% | must hedge / DISAMBIGUATE |
| `eliah:self:employment/microsoft` | 20% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/preference/vegan` | 30% | must hedge / DISAMBIGUATE |
| `futureforce:hedge:'I believe'` | 30% | must hedge / DISAMBIGUATE |
| `group-ramble:thread:woodworking` | 30% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/education/tartan` | 40% | must hedge / DISAMBIGUATE |
| `eliah:self:education/tartan` | 40% | must hedge / DISAMBIGUATE |
| `dom:self:education/senior` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:ambiguity:subject/rugby` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:tunde/life_event/mom` | 50% | must hedge / DISAMBIGUATE |
| `eliah:episode:EP-1` | 60% | must hedge / DISAMBIGUATE |
| `nikos:entity:picnic` | 60% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/same age` | 70% | stable-core-ish |
| `group-ramble:loop:cook` | 70% | stable-core-ish |
| `nikos:assertion:nikos/life_event/startup school` | 70% | stable-core-ish |
| `plural-attribution:assertion:rania/education/mechanical` | 70% | stable-core-ish |
| `dom:assertion:dom/relation/leon` | 80% | stable-core-ish |
| `group-ramble:hedge:'I want to say'` | 80% | stable-core-ish |
| `group-ramble:person:unknown1` | 80% | stable-core-ish |
| `eliah:self:interest/anime` | 90% | stable-core-ish |
| `futureforce:entity:future` | 90% | stable-core-ish |
| `group-ramble:assertion:jen/employment/pottery` | 90% | stable-core-ish |
| `nikos:assertion:nikos/location/greece` | 90% | stable-core-ish |
| `nikos:assertion:nikos/trait/kind` | 90% | stable-core-ish |
| `secondhand-chain:thread:atlanta` | 90% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| INV-24 | 1/10 | FLICKER |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-11 | 8/10 | FLICKER |
| PIPE-12 | 10/10 | stable-fail |
| PIPE-17 | 9/10 | FLICKER |
| PIPE-5 | 10/10 | stable-fail |
| PIPE-7 | 1/10 | FLICKER |
| episode:EP-1 | 4/10 | FLICKER |
| episode:EP-2 | 8/10 | FLICKER |
| forbidden:any_text | 10/10 | stable-fail |
| forbidden:assertion | 10/10 | stable-fail |
| forbidden:loop | 10/10 | stable-fail |
| forbidden:person_match | 10/10 | stable-fail |
| forbidden:thread_archetype_for | 2/10 | FLICKER |
| person match | 1/10 | FLICKER |
| person status | 1/10 | FLICKER |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
