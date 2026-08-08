# Aggregate — k10-v7

**10 runs** · model `gpt-5.1` · prompt `v7` · git `87029b2`  
collected 2026-08-08T01:41:12Z · 829,687 tokens · 1365s model time

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 70% · min 68% · max 74% |
| PIPE-4-class criticals | median 15.0 · min 12 · max 17 |
| round-trip checks passed | median 8.0 · min 7 · max 9 |

Round-trip, run by run: run-01 8 passed, 1 failed, 1 known-flaky · run-02 9 passed, 0 failed, 1 known-flaky · run-03 8 passed, 0 failed, 2 known-flaky · run-04 9 passed, 0 failed, 1 known-flaky · run-05 7 passed, 1 failed, 2 known-flaky · run-06 8 passed, 0 failed, 2 known-flaky · run-07 8 passed, 0 failed, 2 known-flaky · run-08 8 passed, 0 failed, 2 known-flaky · run-09 8 passed, 1 failed, 1 known-flaky · run-10 7 passed, 1 failed, 2 known-flaky

Recall spans **6.7%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **42** always extracted (stable core)
- **10** never extracted (stable miss — a real gap)
- **37** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `eliah:assertion:eliah/interest/basketball` | 10% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/immigrants` | 10% | must hedge / DISAMBIGUATE |
| `eliah:self:location/167th` | 10% | must hedge / DISAMBIGUATE |
| `hardship:assertion:maya/concern/parkinson` | 10% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/life_event/nursing boards` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:ama/relation/tunde` | 20% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:tunde/life_event/mom` | 20% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/employment/ucsf` | 20% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/employment/google` | 30% | must hedge / DISAMBIGUATE |
| `eliah:episode:EP-2` | 30% | must hedge / DISAMBIGUATE |
| `eliah:self:employment/microsoft` | 30% | must hedge / DISAMBIGUATE |
| `futureforce:hedge:'I believe'` | 30% | must hedge / DISAMBIGUATE |
| `homonym:person:sarah_o` | 30% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/preference/vegan` | 40% | must hedge / DISAMBIGUATE |
| `dom:self:education/senior` | 40% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/education/tartan` | 50% | must hedge / DISAMBIGUATE |
| `eliah:self:education/tartan` | 50% | must hedge / DISAMBIGUATE |
| `nikos:assertion:nikos/life_event/startup school` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:kevin/goal/woodworking` | 60% | must hedge / DISAMBIGUATE |
| `group-ramble:thread:woodworking` | 60% | must hedge / DISAMBIGUATE |
| `hardship:thread:parkinson` | 60% | must hedge / DISAMBIGUATE |
| `eliah:hedge:'I want to say'` | 70% | stable-core-ish |
| `group-ramble:loop:cook` | 70% | stable-core-ish |
| `secondhand-chain:thread:atlanta` | 70% | stable-core-ish |
| `dom:assertion:dom/interest/philosophy` | 80% | stable-core-ish |
| `dom:assertion:dom/relation/leon` | 80% | stable-core-ish |
| `dom:assertion:dom/trait/social` | 80% | stable-core-ish |
| `eliah:assertion:eliah/trait/same age` | 80% | stable-core-ish |
| `group-ramble:ambiguity:subject/rugby` | 80% | stable-core-ish |
| `group-ramble:person:unknown1` | 80% | stable-core-ish |
| `eliah:assertion:eliah/interest/anime` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/sports` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/video games` | 90% | stable-core-ish |
| `eliah:episode:EP-1` | 90% | stable-core-ish |
| `eliah:hedge:'I think I got a lot closer'` | 90% | stable-core-ish |
| `eliah:self:interest/anime` | 90% | stable-core-ish |
| `secondhand-chain:assertion:marcus/life_event/shopify` | 90% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-11 | 9/10 | FLICKER |
| PIPE-12 | 10/10 | stable-fail |
| PIPE-17 | 9/10 | FLICKER |
| PIPE-5 | 10/10 | stable-fail |
| episode:EP-1 | 1/10 | FLICKER |
| episode:EP-2 | 7/10 | FLICKER |
| forbidden:assertion | 10/10 | stable-fail |
| forbidden:loop | 10/10 | stable-fail |
| forbidden:person_match | 10/10 | stable-fail |
| person match | 1/10 | FLICKER |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
