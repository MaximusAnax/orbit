# Aggregate — k10-v10

**10 runs** · model `gpt-5.1` · prompt `v10` · git `ecb7010`  
collected 2026-08-10T21:34:12Z · 921,398 tokens · 1381s model time

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 70% · min 66% · max 71% |
| PIPE-4-class criticals | median 19.0 · min 16 · max 22 |
| round-trip checks passed | median 9.0 · min 8 · max 9 |

Round-trip, run by run: run-01 9 passed, 0 failed, 1 known-flaky · run-02 9 passed, 0 failed, 1 known-flaky · run-03 8 passed, 0 failed, 2 known-flaky · run-04 9 passed, 0 failed, 1 known-flaky · run-05 8 passed, 0 failed, 2 known-flaky · run-06 9 passed, 0 failed, 1 known-flaky · run-07 9 passed, 0 failed, 1 known-flaky · run-08 9 passed, 0 failed, 1 known-flaky · run-09 8 passed, 0 failed, 2 known-flaky · run-10 9 passed, 0 failed, 1 known-flaky

Recall spans **5.6%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **40** always extracted (stable core)
- **11** never extracted (stable miss — a real gap)
- **38** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `dom:assertion:dom/preference/vegan` | 10% | must hedge / DISAMBIGUATE |
| `eliah:hedge:'I think it was actually maybe one'` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:tunde/life_event/mom` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:loop:cook` | 10% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/immigrants` | 20% | must hedge / DISAMBIGUATE |
| `eliah:episode:EP-2` | 20% | must hedge / DISAMBIGUATE |
| `hardship:assertion:maya/concern/parkinson` | 20% | must hedge / DISAMBIGUATE |
| `nikos:assertion:nikos/life_event/startup school` | 20% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/interest/philosophy` | 30% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/trait/social` | 40% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/employment/google` | 40% | must hedge / DISAMBIGUATE |
| `eliah:self:employment/microsoft` | 40% | must hedge / DISAMBIGUATE |
| `futureforce:ambiguity:attendance/lake` | 40% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/life_event/nursing boards` | 40% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/education/tartan` | 50% | must hedge / DISAMBIGUATE |
| `eliah:self:education/tartan` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:person:unknown1` | 50% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/employment/ucsf` | 50% | must hedge / DISAMBIGUATE |
| `nikos:entity:picnic` | 50% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/relation/leon` | 70% | stable-core-ish |
| `eliah:assertion:eliah/trait/same age` | 70% | stable-core-ish |
| `group-ramble:assertion:jen/employment/pottery` | 70% | stable-core-ish |
| `group-ramble:assertion:kevin/goal/woodworking` | 70% | stable-core-ish |
| `group-ramble:thread:woodworking` | 70% | stable-core-ish |
| `dom:assertion:dom/education/computer science` | 80% | stable-core-ish |
| `dom:assertion:dom/education/policy` | 80% | stable-core-ish |
| `eliah:hedge:'I think I got a lot closer'` | 80% | stable-core-ish |
| `eliah:self:trait/all over the place` | 80% | stable-core-ish |
| `group-ramble:hedge:'I want to say'` | 80% | stable-core-ish |
| `homonym:person:sarah_o` | 80% | stable-core-ish |
| `secondhand-chain:assertion:marcus/life_event/shopify` | 80% | stable-core-ish |
| `dom:hedge:'I think, computer science'` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/video games` | 90% | stable-core-ish |
| `eliah:episode:EP-1` | 90% | stable-core-ish |
| `group-ramble:ambiguity:subject/rugby` | 90% | stable-core-ish |
| `hardship:thread:parkinson` | 90% | stable-core-ish |
| `nikos:assertion:nikos/trait/kind` | 90% | stable-core-ish |
| `secondhand-chain:thread:atlanta` | 90% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-11 | 10/10 | stable-fail |
| PIPE-12 | 10/10 | stable-fail |
| PIPE-17 | 10/10 | stable-fail |
| PIPE-5 | 10/10 | stable-fail |
| episode:EP-1 | 1/10 | FLICKER |
| episode:EP-2 | 8/10 | FLICKER |
| forbidden:assertion | 10/10 | stable-fail |
| forbidden:episode | 1/10 | FLICKER |
| forbidden:loop | 10/10 | stable-fail |
| forbidden:person_match | 10/10 | stable-fail |
| person match | 8/10 | FLICKER |
| person status | 5/10 | FLICKER |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
