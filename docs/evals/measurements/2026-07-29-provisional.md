# Provisional PIPE measurement — 2026-07-29

Extractor: `claude-fable-5(in-session)` · prompt v1 · corpus: 4 real + 7 synthetic memos.
**Provisional by definition** — the ratified PIPE-12 number awaits the production
extractor (EVALS §9). Deterministic contract matching (structured fields +
containment); no LLM judge in this path.

| Memo | Required hit | Criticals | Misses |
| --- | --- | --- | --- |
| contradiction | 2/2 | 0 | — |
| correction | 2/2 | 0 | — |
| dom | 10/10 | 0 | — |
| eliah | 34/34 | 0 | — |
| futureforce | 8/8 | 0 | — |
| group-ramble | 15/15 | 0 | — |
| hardship | 4/4 | 0 | — |
| homonym | 4/4 | 0 | — |
| nikos | 5/5 | 0 | — |
| secondhand-chain | 5/5 | 0 | — |
| silence | 1/1 | 0 | — |

| Check | Provisional value | EVALS ◊ target |
| --- | --- | --- |
| PIPE-3 extraction recall (required-item) | 100.0% (90/90) | ◊ ≥ 90% |
| PIPE-4-class Criticals (forbidden/invented/misattributed) | 0 | 0 |
| PIPE-5 hedge preservation | 100% | 100% |
| PIPE-6 verbatim fidelity | 100% | 100% |
| PIPE-7 false attributions | 0 | 0 |
| PIPE-9 planted-ambiguity recall | see per-memo required ambiguity rows | ◊ ≥ 90% |
| PIPE-10 unsanctioned threads | 0 | ◊ ≥ 85% precision |
| PIPE-11 archetype accuracy | 3/3 | ◊ ≥ 85% |
| PIPE-12 episode split (Eliah golden) | see eliah row (episodes are Critical-tracked) | ◊ gate |
| PIPE-1b identity fragmentation | 0 | 0 |
| PIPE-13 entity fragmentation (alias-overlap unify) | 0 unresolvable | ◊ ≤ 5% |

No Critical-class findings on this corpus.
