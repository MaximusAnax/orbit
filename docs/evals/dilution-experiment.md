# The dilution experiment — pre-registered 2026-08-08, before the result

FN-41 raised a hypothesis the v7 comparison could not test: that the extraction
prompt has grown long enough that **each added rule now trades one item for
another**. v7 improved 21 required items and regressed 20 (sign test p = 1.000),
and degraded `condition_hardship` from 10/10 runs to 6/10 despite touching
nothing to do with hardship.

Written down before the collection finishes, because everything measured in this
project so far has been interpreted after the fact, and four times tonight a
confident reading turned out to be an artifact. A prediction made afterwards is
not a prediction.

## The confound in v7, and why this design avoids it

v7 changed three rules at once. "Rule 35 caused the hardship regression" and "the
prompt got longer" are indistinguishable in that data.

So v9 changes **no requirements at all**. It is v8's content, reorganised by
topic instead of by changelog, with the redundancy collapsed:

| | v8 | v9 |
| --- | --- | --- |
| words | 2,975 | **1,462** (−51%) |
| numbered rules | 37 | 28 |
| requirements | 37 | **37** |

All 37 were probed mechanically for survival before the run. The 28 rules are the
same 37 requirements merged where they overlapped — four separate rules on
episodes became one, four on self-collision became two, three on hedging became
one, three on location became two.

Three kinds of text were removed, none of them instructions:

1. **A stale header.** v8 opens by telling the model *"v3 is the active prompt"*,
   then explains a waiver, then describes what v2 changed. Roughly 250 words of
   changelog addressed to humans, sitting in the system prompt, factually wrong
   about which prompt is running.
2. **Changelog section headers** — "Rules added in v5, from the second live
   measurement" — which organise the prompt by *when we learned something*
   rather than by what the model is being asked to do.
3. **Measurement provenance inside rules.** Rule 35 recites "Leon 9/10, Ama 8/10,
   Jen 6/10, Philly and Roger 4/10 each". That is why the rule exists; it is not
   the rule. It belongs in the field note, which has it.

## Predictions, and what each outcome means

**If v9 ≥ v8** on paired items — *something* about the shorter form is better,
but be careful about which thing. v9 is not a clean length manipulation, and
pretending otherwise would be the same over-claiming this document exists to
avoid. Three things changed together:

1. **Length** — half the words gone.
2. **Organisation** — grouped by topic rather than by the order we learned
   things, so every rule about episodes now sits in one place instead of four.
3. **Emphasis** — the five overriding principles are hoisted to the top, which
   v8 did not do.

Any of those could carry the effect, and (2) is arguably the stronger candidate:
four scattered statements about episodes are not just verbose, they are four
chances to half-apply the rule. So the honest reading of a v9 win is *"the
consolidated form is better"*, and the follow-up that separates length from
organisation is v8 reordered by topic **without** shortening it.

**If v9 < v8** — the removed prose was load-bearing after all. Most likely the
repetition itself was doing work: saying "episodes are portraits-only" in four
places may be worth more than saying it once well. That would be a genuinely
surprising and useful result, and it argues *for* redundancy rather than against
it.

**If neither** (the honest most-likely outcome, given 21-up-20-down last time) —
form is neutral at this scale, and FN-41's hardship regression came from rule
*content*, not from how the prompt is written. The next experiment would then be
v8 minus rule 35 only. This outcome would also be a small, useful licence: if
halving the prompt costs nothing, keep the short one, because it is cheaper per
call and far easier to edit without breaking something.

## What will be measured

Paired against `k10-v8`, same 89 required items, same corpus, sign test over the
items that move — plus the three specific things v7 bought, which must survive:

- `leon/goal/atlanta` at 100%
- the two recovered hedges at 70% and 90%
- residence assertions at ~17 total, with `self location/167th` restored by v8's
  narrowed rule 35

And the FN-41 watch item: `condition_hardship` back toward 10/10, or not.

## A hazard found while setting this up

`latestPromptVersion` resolves from the *bundle at runtime*, so writing a new
prompt file and rebuilding while a collection is running would silently switch
the running job onto the new prompt mid-corpus. The grading stage shells into
`swift run`, which rebuilds on any source change — so an innocuous edit during a
job is enough to do it.

Nothing was corrupted here (checked: the bundle held v8 and every fixture is
stamped `v8`), but it is the same shape as FN-35: a configuration that changes
under you with no error and no way to tell from the output. Recorded as FN-42.
