
# Semantic re-grade — required assertions

| | hits | recall |
| --- | --- | --- |
| strict (substring + exact predicate) | 240/390 | **61.5%** |
| semantic (adjudicated) | 270/390 | **69.2%** |

The gap — **7.7%** — is grader measurement error, not model failure: facts the model extracted correctly and the substring-plus-exact-predicate matcher could not see.

## Recovered required facts (30 across 10 runs)

| runs | required fact | matched by | why |
| --- | --- | --- | --- |
| 7 | `eliah/life_event/rooming together` | `CLAIM: relation = roommate [self]   | supporting quo` | Rooming together is captured as being ro |
| 6 | `dom/preference/vegan` | `CLAIM: trait = vegan   | supporting quote (context o` | Candidate 0 explicitly records Dom as ve |
| 4 | `kevin/goal/woodworking` | `CLAIM: employment = None [woodworking]   | supportin` | Leaving job to do woodworking full time  |
| 3 | `eliah/education/tartan` | `CLAIM: life_event = None [Tartan Scholars]   | suppo` | Tartan Scholars implies Tartan as educat |
| 3 | `eliah/education/213` | `CLAIM: education = None [Carnegie Mellon]   | suppor` | Carnegie Mellon maps to numeric educatio |
| 2 | `nikos/life_event/startup school` | `CLAIM: education = attended [Y Combinator]   | suppo` | Attended Y Combinator startup school equ |
| 1 | `nikos/location/greece` | `CLAIM: trait = from Greece   | supporting quote (con` | “from Greece” matches location Greece fo |
| 1 | `ama/skill/epidemiology` | `CLAIM: employment = None [public health]   | support` | Public health employment described speci |
| 1 | `eliah/interest/basketball` | `CLAIM: skill = plays basketball   | supporting quote` | Playing basketball implies an interest i |
| 1 | `leon/goal/atlanta` | `CLAIM: location = move back [Atlanta]   | supporting` | States Leon’s goal is to move back to At |
| 1 | `ama/relation/tunde` | `CLAIM: life_event = attended Tunde's housewarming   ` | Housewarming implies personal relation b |

## Hand validation of the judge's recoveries

*A judge nobody has checked is an opinion with a percentage sign, so every
distinct recovery was reviewed. This is a second opinion, not ground truth —
EVALS §3.5 wants judges audited against Abdoul's rubric, and that has not
happened yet.*

| runs | required fact | matched by | verdict | why |
| --- | --- | --- | --- | --- |
| 7 | `eliah/life_event/rooming together` | `relation = roommate` | **FAIR** | same fact, different category |
| 6 | `dom/preference/vegan` | `trait = vegan` | **FAIR** | preference vs trait; identical claim |
| 4 | `kevin/goal/woodworking` | `employment = [woodworking]` | **UNFAIR** | asserts he works in it; the fact is that he PLANS to |
| 3 | `eliah/education/tartan` | `life_event = [Tartan Scholars]` | **FAIR** | same program, category quibble |
| 3 | `eliah/education/213` | `education = [Carnegie Mellon]` | **UNFAIR** | 213 is a course; CMU is the university. different facts |
| 2 | `nikos/life_event/startup school` | `education = attended [Y Combinator]` | **FAIR** | Startup School is YC's programme |
| 1 | `nikos/location/greece` | `trait = from Greece` | **FAIR** | same claim |
| 1 | `ama/skill/epidemiology` | `employment = [public health]` | **UNFAIR** | public health is broader than the epidemiology skill |
| 1 | `eliah/interest/basketball` | `skill = plays basketball` | **FAIR** | the canonical fair-equivalence case |
| 1 | `leon/goal/atlanta` | `location = move back [Atlanta]` | **FAIR** | object_value 'move back' does carry the goal |
| 1 | `ama/relation/tunde` | `life_event = attended housewarming` | **UNFAIR** | attending an event does not record a relation |

**9 of 30 run-weighted recoveries do not survive review (30% false-positive rate).** Corrected:

| | recall |
| --- | --- |
| strict (substring + exact predicate) | 61.5% |
| judge, unvalidated | 69.2% |
| **judge, hand-validated** | **66.9%** |

So the grader's measurement error on required-fact recall is about **5.4%**, not the 7.7% the judge claimed. Both numbers are far below the ◊ ≥ 90% target; the point of establishing them is that the target was previously being compared against a number carrying several points of instrument error in an unknown direction.
