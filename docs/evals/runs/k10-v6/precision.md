# PIPE-4 precision — k10-v6

claims emitted            : 979
structurally unsupported  : 32
judged unsupported        : 257
judge unavailable         : 0

**precision = 70.5%**   (EVALS PIPE-4 target ◊ >= 97%)

per-run spread: median 70.8% · min 61.4% · max 80.4%  (n=10 runs)

Judge: gpt-5.1 / prompt j4, adversarial. Same model family as the extractor, so treat this as an upper bound until validated against Abdoul (--sample N).

## Unsupported claims by persistence

| runs | memo | claim | why |
| --- | --- | --- | --- |
| 9 | secondhand-chain | `Leon — location — residence [Atlanta]  (stated tentatively` | Thinking about moving back is not current residence |
| 8 | group-ramble | `Ama — location — residence [Chicago]` | Transcript says she flew in from Chicago, not reside |
| 7 | eliah | `Abdoul (the speaker) — trait — energetic` | hedge 'i think' in the quote but hedged=false |
| 7 | hardship | `Maya — employment — designer [Figma]` | Transcript never calls her role a designer explicitl |
| 4 | eliah | `Elia Tapia — trait — funny` | hedge 'i think' in the quote but hedged=false |
| 4 | eliah | `Elia Tapia — trait — super smart` | hedge 'i think' in the quote but hedged=false |
| 4 | eliah | `episode: First meeting through Tartan Scholars pre-orienta` | Year 2022 is not stated or implied in transcript |
| 3 | eliah | `Elia Tapia — relation — roommate [Abdoul (the speaker)]  (` | hedge 'i want to say' in the quote but hedged=false |
| 3 | group-ramble | `Jen — location — residence [Berkeley]` | Only business location mentioned, not where she live |
| 3 | group-ramble | `Jen — location — residence [Berkeley]  (from 2026-07 to op` | Berkeley is where her studio is, not stated as resid |
| 3 | nikos | `episode: YC Startup School picnic and evening with Nikos (` | Transcript gives relative Friday, not explicit 2026- |
| 2 | secondhand-chain | `Leon — relation — roommate [person_3] [Marcus]  (stated te` | quote has no anchor in the transcript, even fuzzily |
| 2 | eliah | `Abdoul (the speaker) — relation — roommate [Elia Tapia]  (` | hedge 'i want to say' in the quote but hedged=false |
| 2 | eliah | `Abdoul (the speaker) — relation — roommates [Elia Tapia]  ` | hedge 'i want to say' in the quote but hedged=false |
| 2 | eliah | `Elia Tapia — relation — roommates [Abdoul (the speaker)]  ` | hedge 'i want to say' in the quote but hedged=false |
| 2 | eliah | `Elia Tapia — life_event — [Japan] [Abdoul (the speaker)]  ` | No dates given; claim adds 2023–open timeframe not s |
| 2 | eliah | `episode: Junior year fall break trip to Colombia (occurred` | Transcript mentions trip but gives no specific 2024- |
| 2 | group-ramble | `Jen — employment — founder [pottery studio]  (from 2026-07` | Transcript says started a studio, not founder or ope |
| 2 | eliah | `Abdoul (the speaker) — relation — roommate [Elia Tapia]  (` | Transcript gives no years or open-ended date range |
| 2 | group-ramble | `Kevin — employment — [woodworking]  (source: secondhand; f` | Plan to leave job; not yet employed in woodworking |
| 2 | dom | `Dominic — education — attended [Y Combinator Startup Schoo` | Transcript shows speaker at YC, not Dominic explicit |
| 2 | eliah | `Elia Tapia — interest — [computer science]` | Transcript says he studies CS, not that it’s an inte |
| 2 | eliah | `Abdoul (the speaker) — employment — intern [Microsoft]  (f` | Transcript has internship but no specific year 2025  |
| 2 | eliah | `Roger — relation — roommate [Philly]  (from 2025 to 2025)` | Transcript says they lived together, not specific ro |
| 2 | eliah | `episode: First meeting through Tartan Scholars before fres` | Transcript gives no year; 2022 is an unsupported add |
| 2 | group-ramble | `Jen — employment — owner [pottery studio]  (from 2026-07 t` | Transcript says she started a studio, not that she o |
| 2 | group-ramble | `Kevin — skill — [woodworking]  (source: secondhand)` | Transcript states future plan, not established skill |
| 2 | futureforce | `Abdoul (the speaker) — relation — participant [Future Forc` | Attended event with participants; doesn’t state he’s |
| 2 | eliah | `episode: Summer in the Pacific Northwest interning (occurr` | Year 2025 is not stated or derivable from transcript |
| 2 | eliah | `episode: Fall break trip to Colombia (occurred 2025)` | Transcript gives no year; 2025 date is unstated |

30 adjudications written for human review: /Users/Productivity/Documents/projects/orbit/docs/evals/runs/k10-v6/judge-sample.json
A judge nobody has checked is an opinion with a percentage sign.
