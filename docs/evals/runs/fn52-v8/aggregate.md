# Aggregate — fn52-v8

**10 runs** · model `gpt-5.1` · prompt `v8` · git `375d10b`  
collected 2026-08-10T22:45:02Z · 66,217 tokens · 65s model time

⚠️ **100 missing fixture(s)** across 10 run(s), scored as zero recall rather than skipped:
- `run-01`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-02`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-03`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-04`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-05`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-06`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-07`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-08`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-09`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence
- `run-10`: contradiction, correction, dom, eliah, futureforce, group-ramble, hardship, nikos, secondhand-chain, silence

## Distribution, not a point

| Metric | Spread across runs |
| --- | --- |
| PIPE-3 required-item recall | median 2% · min 0% · max 3% |
| PIPE-4-class criticals | median 25.0 · min 25 · max 27 |

Recall spans **3.3%** between the best and worst run of an identical configuration. Any prompt comparison smaller than that band is noise.

## Per-item stability

- **0** always extracted (stable core)
- **87** never extracted (stable miss — a real gap)
- **3** flicker between runs

Only the stable rows can carry a gate. The flickering ones are PIPE-15's actual subject: below the 70% line, the product is supposed to hedge or ask rather than assert.

| Required item | Hit rate | Under PIPE-15 |
| --- | --- | --- |
| `homonym:assertion:sarah_o/life_event/nursing boards` | 40% | must hedge / DISAMBIGUATE |
| `homonym:assertion:sarah_o/employment/ucsf` | 50% | must hedge / DISAMBIGUATE |
| `homonym:person:sarah_o` | 70% | stable-core-ish |

## Check stability

| Check | Runs firing | Classification |
| --- | --- | --- |
| PIPE-10 | 10/10 | stable-fail |
| PIPE-5 | 10/10 | stable-fail |
| collection gap | 10/10 | stable-fail |
| correction:google | 10/10 | stable-fail |
| episode:EP-1 | 10/10 | stable-fail |
| episode:EP-2 | 10/10 | stable-fail |
| episode:EP-3 | 10/10 | stable-fail |
| forbidden:person_match | 1/10 | FLICKER |
| person match | 2/10 | FLICKER |
| person:eliah | 10/10 | stable-fail |
| state:inner, inner, inner circle | 10/10 | stable-fail |

---

*Grading is separate from collection by design: these runs are on disk and can be re-graded for free when the grader improves (MEASUREMENT-REWORK Phase 2). No number here is better than the grader that produced it — PIPE-4 still counts enumerated forbidden items rather than measuring precision, and required-fact matching is still substring plus exact predicate.*
