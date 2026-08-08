# Aggregate — k10-v6

**10 runs** · model `gpt-5.1` · prompt `v6` · git `6acd2a3`  
collected 2026-08-08T00:47:11Z · 734,301 tokens · 1323s model time

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 67% · min 64% · max 76% |
| PIPE-4-class criticals | median 25.0 · min 15 · max 35 |
| round-trip checks passed | median 9.0 · min 7 · max 10 |

Round-trip, run by run: run-01 9 passed, 1 failed · run-02 8 passed, 2 failed · run-03 8 passed, 2 failed · run-04 7 passed, 3 failed · run-05 10 passed, 0 failed · run-06 9 passed, 1 failed · run-07 10 passed, 0 failed · run-08 9 passed, 1 failed · run-09 8 passed, 2 failed · run-10 9 passed, 1 failed

Recall spans **11.1%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **40** always extracted (stable core)
- **13** never extracted (stable miss — a real gap)
- **36** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `dom:self:education/senior` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:ama/relation/tunde` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:kevin/goal/woodworking` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:thread:woodworking` | 10% | must hedge / DISAMBIGUATE |
| `hardship:assertion:maya/concern/parkinson` | 10% | must hedge / DISAMBIGUATE |
| `secondhand-chain:assertion:leon/goal/atlanta` | 10% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/immigrants` | 20% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/employment/ucsf` | 20% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/life_event/nursing boards` | 20% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:tunde/life_event/mom` | 30% | must hedge / DISAMBIGUATE |
| `nikos:assertion:nikos/life_event/startup school` | 30% | must hedge / DISAMBIGUATE |
| `nikos:entity:picnic` | 30% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/preference/vegan` | 40% | must hedge / DISAMBIGUATE |
| `homonym:person:sarah_o` | 40% | must hedge / DISAMBIGUATE |
| `futureforce:hedge:'I believe'` | 50% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/interest/philosophy` | 60% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/trait/social` | 60% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/employment/google` | 60% | must hedge / DISAMBIGUATE |
| `eliah:self:employment/microsoft` | 60% | must hedge / DISAMBIGUATE |
| `eliah:self:location/167th` | 60% | must hedge / DISAMBIGUATE |
| `secondhand-chain:thread:atlanta` | 60% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/education/tartan` | 70% | stable-core-ish |
| `eliah:self:education/tartan` | 70% | stable-core-ish |
| `group-ramble:ambiguity:subject/rugby` | 70% | stable-core-ish |
| `eliah:assertion:eliah/trait/same age` | 80% | stable-core-ish |
| `eliah:self:trait/all over the place` | 80% | stable-core-ish |
| `group-ramble:loop:cook` | 80% | stable-core-ish |
| `group-ramble:person:unknown1` | 80% | stable-core-ish |
| `nikos:assertion:nikos/trait/kind` | 80% | stable-core-ish |
| `dom:assertion:dom/education/policy` | 90% | stable-core-ish |
| `dom:assertion:dom/relation/leon` | 90% | stable-core-ish |
| `group-ramble:assertion:ama/skill/epidemiology` | 90% | stable-core-ish |
| `group-ramble:assertion:jen/employment/pottery` | 90% | stable-core-ish |
| `group-ramble:hedge:'biotech I think'` | 90% | stable-core-ish |
| `hardship:thread:parkinson` | 90% | stable-core-ish |
| `nikos:assertion:nikos/location/greece` | 90% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-12 | 7/10 | FLICKER |
| PIPE-17 | 9/10 | FLICKER |
| PIPE-5 | 10/10 | stable-fail |
| PIPE-6 | 10/10 | stable-fail |
| PIPE-6/INV-24 | 2/10 | FLICKER |
| episode:EP-2 | 10/10 | stable-fail |
| forbidden:assertion | 10/10 | stable-fail |
| forbidden:episode | 1/10 | FLICKER |
| forbidden:loop | 10/10 | stable-fail |
| forbidden:person_match | 10/10 | stable-fail |
| person match | 4/10 | FLICKER |
| person status | 2/10 | FLICKER |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
