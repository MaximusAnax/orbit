# Aggregate — k10-v8-newmemos

**10 runs** · model `gpt-5.1` · prompt `v8` · git `d9c8aaa`  
collected 2026-08-10T21:49:03Z · 143,959 tokens · 192s model time

⚠️ **110 missing fixture(s)** across 10 run(s), scored as zero recall rather than skipped:
- `run-01`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-02`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-03`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-04`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-05`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-06`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-07`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-08`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-09`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence
- `run-10`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, homonym, nikos, secondhand-chain, silence

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 15% · min 15% · max 15% |
| PIPE-4-class criticals | median 27.0 · min 27 · max 30 |

Recall spans **0.0%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **15** always extracted (stable core)
- **90** never extracted (stable miss — a real gap)
- **2** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `plural-attribution:assertion:rania/education/mechanical` | 40% | must hedge / DISAMBIGUATE |
| `plural-attribution:assertion:theo/education/None` | 60% | must hedge / DISAMBIGUATE |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| PIPE-17 | 1/10 | FLICKER |
| PIPE-5 | 10/10 | stable-fail |
| collection gap | 10/10 | stable-fail |
| correction:google | 10/10 | stable-fail |
| episode:EP-1 | 10/10 | stable-fail |
| episode:EP-2 | 10/10 | stable-fail |
| episode:EP-3 | 10/10 | stable-fail |
| forbidden:any_text | 10/10 | stable-fail |
| forbidden:object_value_contains_person_name | 1/10 | FLICKER |
| person:eliah | 10/10 | stable-fail |
| state:inner, inner, inner circle | 10/10 | stable-fail |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
