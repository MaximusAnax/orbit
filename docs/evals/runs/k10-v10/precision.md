# PIPE-4 precision — k10-v10

claims emitted            : 1058
structurally unsupported  : 25

**precision = 97.6%**   (EVALS PIPE-4 target ◊ >= 97%)

per-run spread: median 98.0% · min 94.9% · max 100.0%  (n=10 runs)

⚠️  Stage A only — a CEILING, not the measurement. 1033 claims passed the structural checks and were never asked the semantic question. Run with --judge.

## Unsupported claims by persistence

| runs | memo | claim | why |
| --- | --- | --- | --- |
| 3 | homonym | `Sarah — life_event — (no object)` | assertion carries no object at all (rule 27) |
| 3 | eliah | `Abdoul (the speaker) — trait — excited and energetic` | hedge 'i think' in the quote but hedged=false |
| 2 | group-ramble | `Kevin — employment — (no object)` | assertion carries no object at all (rule 27) |
| 2 | eliah | `Abdoul (the speaker) — trait — really excited and really e` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — trait — energetic and all over the ` | hedge 'i think' in the quote but hedged=false |
| 1 | group-ramble | `unknown biotech guest — life_event — (no object)  (stated ` | assertion carries no object at all (rule 27) |
| 1 | dom | `Dominic — education — [computer science]` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Elia Tapia — education — [Tartan Scholars]` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — education — [Tartan Scholars]` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — trait — really excited and energeti` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — relation — aligned ambitions and go` | hedge 'i think' in the quote but hedged=false |
| 1 | group-ramble | `Ama — location — residence [Chicago]` | hedge 'i want to say' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — trait — excitable and energetic  (f` | hedge 'i think' in the quote but hedged=false |
| 1 | group-ramble | `Ama — employment — [public health]` | hedge 'i want to say' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — life_event — [Tartan Scholars]` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Elia Tapia — life_event — [Tartan Scholars]` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Abdoul (the speaker) — relation — aligned ambitions and go` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Elia Tapia — relation — aligned ambitions and goals [Abdou` | hedge 'i think' in the quote but hedged=false |
| 1 | eliah | `Elia Tapia — trait — driven and ambitious in similar way [` | hedge 'i think' in the quote but hedged=false |
