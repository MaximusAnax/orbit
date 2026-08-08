# Aggregate — k10-v8

**10 runs** · model `gpt-5.1` · prompt `v8` · git `b0182a4`  
collected 2026-08-08T02:11:57Z · 839,934 tokens · 1265s model time

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 73% · min 67% · max 80% |
| PIPE-4-class criticals | median 15.0 · min 13 · max 18 |
| round-trip checks passed | median 8.0 · min 8 · max 9 |

Round-trip, run by run: run-01 8 passed, 0 failed, 2 known-flaky · run-02 8 passed, 0 failed, 2 known-flaky · run-03 9 passed, 0 failed, 1 known-flaky · run-04 9 passed, 0 failed, 1 known-flaky · run-05 8 passed, 0 failed, 2 known-flaky · run-06 8 passed, 0 failed, 2 known-flaky · run-07 8 passed, 0 failed, 2 known-flaky · run-08 9 passed, 0 failed, 1 known-flaky · run-09 8 passed, 1 failed, 1 known-flaky · run-10 9 passed, 0 failed, 1 known-flaky

Recall spans **13.3%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **43** always extracted (stable core)
- **5** never extracted (stable miss — a real gap)
- **41** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `eliah:assertion:eliah/interest/basketball` | 10% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/life_event/living separately` | 10% | must hedge / DISAMBIGUATE |
| `eliah:hedge:'I think it was actually maybe one'` | 10% | must hedge / DISAMBIGUATE |
| `futureforce:ambiguity:attendance/lake` | 10% | must hedge / DISAMBIGUATE |
| `futureforce:hedge:'I believe'` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:ama/relation/tunde` | 10% | must hedge / DISAMBIGUATE |
| `hardship:assertion:maya/concern/parkinson` | 10% | must hedge / DISAMBIGUATE |
| `nikos:entity:picnic` | 10% | must hedge / DISAMBIGUATE |
| `dom:self:education/senior` | 20% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/education/213` | 30% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/employment/google` | 30% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/immigrants` | 30% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/same age` | 30% | must hedge / DISAMBIGUATE |
| `eliah:self:employment/microsoft` | 30% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:tunde/life_event/mom` | 30% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/life_event/nursing boards` | 40% | must hedge / DISAMBIGUATE |
| `nikos:assertion:nikos/life_event/startup school` | 40% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/education/tartan` | 50% | must hedge / DISAMBIGUATE |
| `eliah:self:education/tartan` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:kevin/goal/woodworking` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:thread:woodworking` | 50% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/preference/vegan` | 60% | must hedge / DISAMBIGUATE |
| `eliah:episode:EP-2` | 60% | must hedge / DISAMBIGUATE |
| `group-ramble:loop:cook` | 60% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/employment/ucsf` | 60% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/interest/philosophy` | 70% | stable-core-ish |
| `group-ramble:ambiguity:subject/rugby` | 70% | stable-core-ish |
| `homonym:person:sarah_o` | 70% | stable-core-ish |
| `dom:assertion:dom/relation/leon` | 80% | stable-core-ish |
| `hardship:thread:parkinson` | 80% | stable-core-ish |
| `dom:assertion:dom/trait/social` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/sports` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/video games` | 90% | stable-core-ish |
| `eliah:episode:EP-1` | 90% | stable-core-ish |
| `eliah:hedge:'I think I got a lot closer'` | 90% | stable-core-ish |
| `eliah:hedge:'I want to say'` | 90% | stable-core-ish |
| `eliah:self:education/carnegie mellon` | 90% | stable-core-ish |
| `group-ramble:hedge:'I want to say'` | 90% | stable-core-ish |
| `group-ramble:person:unknown1` | 90% | stable-core-ish |
| `nikos:assertion:nikos/location/greece` | 90% | stable-core-ish |
| `secondhand-chain:thread:atlanta` | 90% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| INV-24 | 1/10 | FLICKER |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-11 | 9/10 | FLICKER |
| PIPE-12 | 10/10 | stable-fail |
| PIPE-17 | 7/10 | FLICKER |
| PIPE-5 | 10/10 | stable-fail |
| episode:EP-1 | 1/10 | FLICKER |
| episode:EP-2 | 4/10 | FLICKER |
| forbidden:assertion | 10/10 | stable-fail |
| forbidden:episode | 1/10 | FLICKER |
| forbidden:loop | 9/10 | FLICKER |
| forbidden:person_match | 10/10 | stable-fail |
| person match | 5/10 | FLICKER |
| person status | 5/10 | FLICKER |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
