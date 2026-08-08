# Aggregate — k10-v9

**10 runs** · model `gpt-5.1` · prompt `v9` · git `4ec758f`  
collected 2026-08-08T02:37:05Z · 596,541 tokens · 1431s model time

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 66% · min 60% · max 73% |
| PIPE-4-class criticals | median 22.0 · min 17 · max 26 |
| round-trip checks passed | median 7.0 · min 7 · max 9 |

Round-trip, run by run: run-01 8 passed, 1 failed, 1 known-flaky · run-02 7 passed, 1 failed, 2 known-flaky · run-03 7 passed, 1 failed, 2 known-flaky · run-04 7 passed, 1 failed, 2 known-flaky · run-05 9 passed, 0 failed, 1 known-flaky · run-06 8 passed, 1 failed, 1 known-flaky · run-07 7 passed, 2 failed, 1 known-flaky · run-08 7 passed, 1 failed, 2 known-flaky · run-09 7 passed, 1 failed, 2 known-flaky · run-10 9 passed, 0 failed, 1 known-flaky

Recall spans **13.3%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **37** always extracted (stable core)
- **9** never extracted (stable miss — a real gap)
- **43** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `eliah:assertion:eliah/education/213` | 10% | must hedge / DISAMBIGUATE |
| `eliah:hedge:'I think I got a lot closer'` | 10% | must hedge / DISAMBIGUATE |
| `futureforce:ambiguity:attendance/lake` | 10% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:ama/relation/tunde` | 10% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/employment/ucsf` | 10% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/life_event/nursing boards` | 10% | must hedge / DISAMBIGUATE |
| `homonym:person:sarah_o` | 10% | must hedge / DISAMBIGUATE |
| `dom:self:education/senior` | 20% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/employment/google` | 20% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/trait/same age` | 20% | must hedge / DISAMBIGUATE |
| `eliah:hedge:'I think it was actually maybe one'` | 20% | must hedge / DISAMBIGUATE |
| `eliah:self:employment/microsoft` | 20% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:ama/skill/epidemiology` | 20% | must hedge / DISAMBIGUATE |
| `group-ramble:hedge:'I want to say'` | 20% | must hedge / DISAMBIGUATE |
| `nikos:entity:picnic` | 20% | must hedge / DISAMBIGUATE |
| `eliah:hedge:'I want to say'` | 30% | must hedge / DISAMBIGUATE |
| `eliah:assertion:eliah/interest/basketball` | 40% | must hedge / DISAMBIGUATE |
| `group-ramble:ambiguity:subject/rugby` | 40% | must hedge / DISAMBIGUATE |
| `group-ramble:assertion:tunde/life_event/mom` | 40% | must hedge / DISAMBIGUATE |
| `hardship:assertion:maya/concern/parkinson` | 40% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/relation/leon` | 50% | must hedge / DISAMBIGUATE |
| `dom:hedge:'I think, computer science'` | 50% | must hedge / DISAMBIGUATE |
| `nikos:assertion:nikos/life_event/startup school` | 50% | must hedge / DISAMBIGUATE |
| `group-ramble:loop:cook` | 60% | must hedge / DISAMBIGUATE |
| `dom:assertion:dom/preference/vegan` | 70% | stable-core-ish |
| `futureforce:hedge:'I believe'` | 70% | stable-core-ish |
| `group-ramble:assertion:kevin/goal/woodworking` | 70% | stable-core-ish |
| `group-ramble:thread:woodworking` | 70% | stable-core-ish |
| `hardship:thread:parkinson` | 70% | stable-core-ish |
| `futureforce:ambiguity:self_collision/abdul` | 80% | stable-core-ish |
| `group-ramble:person:unknown1` | 80% | stable-core-ish |
| `nikos:assertion:nikos/trait/kind` | 80% | stable-core-ish |
| `secondhand-chain:assertion:marcus/life_event/shopify` | 80% | stable-core-ish |
| `dom:assertion:dom/education/computer science` | 90% | stable-core-ish |
| `dom:assertion:dom/education/policy` | 90% | stable-core-ish |
| `dom:assertion:dom/interest/philosophy` | 90% | stable-core-ish |
| `dom:assertion:dom/trait/social` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/anime` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/sports` | 90% | stable-core-ish |
| `eliah:assertion:eliah/interest/video games` | 90% | stable-core-ish |
| `eliah:self:interest/anime` | 90% | stable-core-ish |
| `group-ramble:hedge:'biotech I think'` | 90% | stable-core-ish |
| `secondhand-chain:hedge:'I think his name is Marcus'` | 90% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| INV-24 | 2/10 | FLICKER |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-12 | 10/10 | stable-fail |
| PIPE-17 | 10/10 | stable-fail |
| PIPE-5 | 10/10 | stable-fail |
| PIPE-7 | 2/10 | FLICKER |
| episode:EP-2 | 10/10 | stable-fail |
| forbidden:assertion | 9/10 | FLICKER |
| forbidden:loop | 7/10 | FLICKER |
| forbidden:person_match | 10/10 | stable-fail |
| forbidden:state_declaration | 5/10 | FLICKER |
| person status | 3/10 | FLICKER |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
