# PIPE-4 precision — k10-v6

claims emitted            : 979
structurally unsupported  : 106
judged unsupported        : 410
judge unavailable         : 0

**precision = 47.3%**   (EVALS PIPE-4 target ◊ >= 97%)

per-run spread: median 47.0% · min 39.8% · max 52.1%  (n=10 runs)

Judge: gpt-5.1 / prompt j1, adversarial. Same model family as the extractor, so treat this as an upper bound until validated against Abdoul (--sample N).

## Unsupported claims by persistence

| runs | memo | claim | why |
| --- | --- | --- | --- |
| 9 | eliah | `person_1 — trait — Dominican` | verbatim is not a contiguous slice of the transcript |
| 9 | eliah | `person_1 — employment — intern` | Claim lacks employer; transcript specifies Google in |
| 9 | homonym | `person_1 — employment — nurse` | Future job start; claim states current employment as |
| 9 | secondhand-chain | `person_2 — location — residence` | Thinking about moving isn’t the same as current resi |
| 8 | group-ramble | `person_2 — location — residence` | Flying in from Chicago doesn’t imply current residen |
| 7 | eliah | `person_1 — trait — calm and reserved` | verbatim is not a contiguous slice of the transcript |
| 7 | eliah | `self — trait — energetic` | hedge 'i think' in the quote but hedged=false |
| 7 | hardship | `person_maya — employment — designer` | Transcript never explicitly calls Maya a designer |
| 7 | dom | `person_leon — relation — roommate` | Claim omits Sekou; Leon is roommate *of Sekou* |
| 6 | eliah | `person_1 — relation — roommate` | verbatim is not a contiguous slice of the transcript |
| 6 | eliah | `person_1 — trait — funny` | verbatim is not a contiguous slice of the transcript |
| 6 | eliah | `person_1 — trait — super smart` | verbatim is not a contiguous slice of the transcript |
| 6 | secondhand-chain | `person_3 — life_event — entity_1` | verbatim is not a contiguous slice of the transcript |
| 6 | group-ramble | `person_4 — location — residence` | Studio is in Berkeley; claim says Jen resides there |
| 6 | eliah | `person_1 — location — origin` | Mixes two people; doesn’t specify which is person_1 |
| 5 | eliah | `person_2 — location — residence` | verbatim is not a contiguous slice of the transcript |
| 5 | eliah | `person_1 — interest — entity_17` | verbatim is not a contiguous slice of the transcript |
| 5 | eliah | `self — interest — entity_18` | verbatim is not a contiguous slice of the transcript |
| 5 | eliah | `self — location — residence` | Address given; not clearly marked as current residen |
| 5 | eliah | `self — education — entity_3` | Claim omits ‘both’; unclear who ‘entity_3’ is |
| 4 | eliah | `person_1 — interest — entity_19` | verbatim is not a contiguous slice of the transcript |
| 4 | group-ramble | `person_6 — employment — employment` | verbatim is not a contiguous slice of the transcript |
| 4 | secondhand-chain | `person_3 — life_event — sold company` | verbatim is not a contiguous slice of the transcript |
| 4 | eliah | `self — relation — roommate` | verbatim is not a contiguous slice of the transcript |
| 4 | eliah | `person_3 — location — residence` | verbatim is not a contiguous slice of the transcript |
| 4 | futureforce | `self — relation — participant` | hedge 'i think' in the quote but hedged=false |
| 4 | eliah | `self — interest — entity_3` | verbatim is not a contiguous slice of the transcript |
| 4 | eliah | `person_1 — interest — entity_3` | verbatim is not a contiguous slice of the transcript |
| 4 | dom | `person_dom — life_event — attendee` | Being there doesn’t explicitly state he was an atten |
| 4 | dom | `self — life_event — attendee` | Claim type ‘life_event — attendee’ not stated in tra |

25 adjudications written for human review: /Users/Productivity/Documents/projects/orbit/docs/evals/runs/k10-v6/judge-sample.json
A judge nobody has checked is an opinion with a percentage sign.
