# ORBIT

**Personal Relationship Memory System**

- **Status:** Concept ratified — data model designed, see [docs/DATA-MODEL.md](docs/DATA-MODEL.md)
- **Primary user:** Abdoul
- **Core idea:** An AI-powered external memory for the people in Abdoul's life.

---

## 1. The Core Idea

Humans care about far more people than they can realistically keep actively in mind.

We forget:

- What someone told us
- What they were excited about
- What they were worried about
- Where they worked at a particular point in time
- What they wanted to do someday
- The small details that make someone feel remembered
- When we last spoke
- What we promised to follow up on

The problem is not necessarily that we stop caring. Often, human memory simply cannot preserve the full context of all our relationships.

Orbit is a personal AI memory system designed to preserve that context. It helps Abdoul remember the people in his life, understand the history of his relationships, maintain the relationships he cares about, and search his network for people and knowledge that may be useful.

The goal is not to turn relationships into a CRM. The goal is to help people feel:

> "I can't believe you remembered that."

---

## 2. The Two Core Pillars

### Pillar One: Perfect Relationship Recall

Before seeing someone Abdoul has not spoken to in months or years, Orbit should be able to quickly bring the relationship back to life.

> "I haven't seen this person in two years."

Orbit should help Abdoul remember:

- Who they are
- How they met
- What they were doing at the time
- What they cared about
- What they were working on
- Important things they mentioned
- Their personal interests
- Their goals
- Their family or life context
- Previous conversations
- Shared experiences
- Unresolved threads
- Things Abdoul said he would follow up on
- Small details that would otherwise have disappeared from memory

The ideal result is not simply a summary. It is a feeling of:

> "Oh right. I remember everything now."

The context was not forgotten.

### Pillar Two: Network Intelligence

Orbit should make Abdoul's network searchable and queryable.

- "Who do I know at Anthropic?"
- "Who can connect me to someone at Goldman Sachs?"
- "Who in my network is interested in videography?"
- "Who knows about low-latency systems?"
- "Who might be interested in helping me build an AI startup?"
- "Who do I know that is interested in AI agents?"
- "Who could introduce me to an engineer who has worked on distributed systems?"

This should not require Abdoul to remember how information was stored. He should be able to ask questions naturally.

Orbit should search across: people, relationships, events, interests, skills, companies, schools, locations, experiences, shared connections, historical context.

The system should ultimately be capable of *reasoning* over the network — not merely returning keyword matches.

---

## 3. The Third Pillar: Memory Fidelity

The product must preserve small details.

A person is not just "Works at Company X." They may also be:

- Someone who wanted to travel to Japan
- Someone whose sister was getting married
- Someone who was nervous about an interview
- Someone who used to work at a particular company
- Someone who once wanted to learn videography
- Someone who mentioned an obscure hobby once over dinner

These details matter. They are often what makes a relationship feel personal.

Orbit should preserve historical context rather than continuously overwriting the past.

---

## 4. The Core Data Model

The fundamental unit is a **Person** — but a person is not just a contact record.

A Person is connected to:

1. Contact Points
2. Events
3. Threads — ongoing situations in their life
4. Relationship State
5. Historical Facts
6. Memories
7. Tasks and Follow-ups
8. Other People
9. Groups — shared social units
10. Organizations and Entities

---

## 5. Person

A Person represents an individual in Abdoul's life.

### Identity

- Name
- Preferred name
- Profile photo
- Pronunciation, if relevant

### Contact Points

Contact points are kept separate from the person's identity. Possible contact points include:

- Phone number
- Email address
- Instagram
- LinkedIn
- X
- Personal website
- Other social profiles
- Messaging platforms

Where possible, contact points should be actionable: tap to call, tap to text, open Instagram, open LinkedIn, send an email.

The system should also support connecting a person to an existing phone contact rather than requiring duplicate manual entry.

---

## 6. Historical Information Must Never Be Lost

Orbit should preserve the evolution of a person over time.

If someone changes jobs, moves cities, changes schools, develops new interests, loses old interests, changes goals, or enters a new stage of life — the old information should remain available as historical context.

```
2024  Worked at Company A.
2025  Joined Company B.
2026  Started a company.
```

The profile should not simply replace Company A with Company B. Instead, the system should preserve the timeline.

This allows questions such as:

- "Where did Sarah used to work?"
- "When did James join his current company?"
- "What was Maria interested in before she started working in AI?"

Historical information is part of the relationship.

---

## 7. Events

An Event represents something that happened: dinner, coffee, phone call, text conversation, conference, party, meeting, introduction, encounter, shared experience.

An event should preserve:

- Date
- Location, where relevant
- People involved
- What happened
- Topics discussed
- New facts learned
- Emotional context
- Commitments made
- Potential follow-ups
- Source of the information

The event is a historical record. Once finalized, it should be treated as **immutable**.

**An event must involve at least one person** — though they need not have been *present*. An event records a moment when something entered Abdoul's memory: usually an interaction, but sometimes a fact remembered in the shower, or a sitting-down to describe an old friend from scratch. In those cases the person is the event's *subject* rather than a participant. What remains forbidden is an event about nobody — that is a diary entry, and Orbit is not a diary. Things that feel like person-less events (a conference, a venue, a recurring dinner) are *contexts* that events attach to, not events themselves.

Records made *about* someone never count as *contact with* them — remembering Sarah is not seeing Sarah, and the system must never confuse the two.

### Threads

Events record moments. **Threads** record the ongoing situations that span them: her job search, his sister's wedding, the startup he is considering, her visa application.

A thread is what turns three unrelated facts — *"nervous about the interview"* (March), *"got the offer"* (April), *"started at Stripe"* (June) — into one story. People remember stories. Isolated facts are the debris stories leave behind, and a system that only stores debris can only hand back debris.

Threads are distinct from follow-ups. A follow-up is an **obligation** — something Abdoul owes, or is owed. A thread is a **situation** — nobody owes anything for someone's interview to have gone well.

A thread must have a plausible resolution. *"She likes sushi"* is a fact. *"She is deciding whether to move to Boston"* is a thread. If you cannot imagine the sentence that closes it, it is not one.

**Threads never close on their own.** A thread that goes quiet stops generating suggestions but stays permanently available as context. Nothing is auto-resolved, and Orbit never asks Abdoul to triage a backlog of stale threads — that is administration, not memory.

**Some threads should be remembered and never raised.** An illness, a grief, a divorce, a parent being cared for. Orbit holds these permanently and never proactively suggests bringing them up. Being nudged to cheerfully ask about someone's hardest year is a worse failure than forgetting.

---

## 8. Event Capture

The primary interaction should be natural voice input. After an interaction, Abdoul should be able to speak freely.

> "I had dinner with Sarah tonight. She works at Stripe now, but she used to be at Google. She's thinking about moving to Boston next year. She mentioned that she really wants to learn videography, and we talked about AI agents for a while. She also told me her brother is visiting next month. I said I'd send her that paper we discussed."

The system should extract: the event, the people involved, new information, historical information, topics, interests, commitments, potential follow-ups.

The goal is to speak naturally — not to fill out forms.

**Recording and transcription run entirely on-device, and audio never leaves the device. Ever.** The recording is the most sensitive artifact this system can hold — another person's actual voice, captured without their knowledge — and no quality argument justifies shipping it elsewhere.

**Audio is deleted once its transcript is confirmed.** The transcript becomes the permanent record; the recording is not kept. This makes transcript review genuinely consequential rather than a formality — the transcript is fully editable before confirmation, and misheard names especially should be easy to catch, because once confirmed, the audio is gone.

**Structuring the transcript may use an AI service, under strict conditions.** Turning natural speech into structured memory is a hard language task, and doing it well currently requires models too large to run on a phone. So transcripts — never audio — may be sent for extraction, only to an endpoint with zero data retention and no training on the content, with no third-party analytics attached, and stated plainly in the product rather than buried in a policy. This is a real tradeoff, made consciously: the transcript still describes people who never consented to being described. The extraction seam is built to be swappable, so when on-device models become good enough, the API becomes an implementation detail that ages out — the promise should tighten over time, never loosen.

---

## 9. Events and Profiles Are Separate

A critical design principle: **an event is not the same thing as a profile.**

The event records what happened. The profile represents the accumulated understanding of the person.

A voice note should not immediately and silently rewrite the profile. Instead:

1. Abdoul records an event.
2. Orbit transcribes and structures the event.
3. The event is presented for review.
4. Abdoul confirms or edits the event.
5. The event is saved.
6. Orbit may propose changes to the relevant profile.
7. Abdoul can approve, reject, or defer those changes.

---

## 10. Profile Synchronization Must Be Explicit

No profile changes should be finalized without Abdoul's confirmation.

After an event is saved, Orbit may propose:

**Proposed profile updates**

- Sarah now works at Stripe.
- Sarah previously worked at Google.
- Sarah is interested in learning videography.
- Sarah may move to Boston next year.
- Sarah's brother is visiting next month.
- Follow up with Sarah about the AI paper.

Abdoul can: accept all, accept individually, edit, reject, or defer.

If Abdoul does not have time to review the proposed changes, the event can remain unsynced. The system should remember: *this event exists, but it has not yet been incorporated into the person's profile.* Later, Abdoul can choose **Sync this event with profile** and review the proposed updates.

This creates four meaningful states — though they are not four settings of one switch:

| State | Meaning |
| --- | --- |
| **Captured** | The event has been recorded. |
| **Confirmed** | The event itself has been reviewed and accepted. |
| **Synchronized** | The event has been used to propose changes to the person's living profile. |
| **Finalized** | Every proposed change has been explicitly resolved by Abdoul. |

**Captured** and **Confirmed** describe the *event*. **Synchronized** and **Finalized** describe the *proposals it generated* — and since Abdoul may accept some, reject others, and defer the rest, an event is frequently *partly* resolved. That is a normal state, not a broken one. An event may sit half-reviewed indefinitely at no cost.

---

## 11. Group Events

Group events are a first-class concept.

> "I went to this event and met Alex, Sarah, James, and Maria. Alex introduced me to Sarah. James is working on AI infrastructure. Maria is a videographer. Sarah is interested in startups…"

The system should allow Abdoul to speak freely about the entire event. The event can contain multiple people. Orbit should then create proposed person-specific updates:

- **Alex** — attended the event; introduced Abdoul to Sarah
- **Sarah** — met at the event; introduced by Alex; interested in startups
- **James** — met at the event; works on AI infrastructure
- **Maria** — met at the event; works in videography

The system should not silently guess when attribution is uncertain. If unsure who a fact belongs to, it should flag the ambiguity:

> "You mentioned that someone at the event works in AI infrastructure. Was this James?"

Accuracy is more important than aggressive automation.

Orbit should also distinguish what Abdoul **witnessed** from what he was **told**. *"Sarah told me she is engaged"* and *"Alex told me Sarah is engaged"* are not the same claim — one is testimony, the other is hearsay — and recording them identically manufactures confidence that was never earned. Facts learned secondhand should carry who they came from.

---

## 12. Relationship State

The historical event timeline is **objective**. The relationship state is **subjective**. These should be separate.

Abdoul should be able to describe his relationship with someone in his own words:

> "We're close friends. We don't talk every week, but we have a strong relationship and usually reconnect easily."

> "He's someone I want to become closer with professionally."

> "She's an old friend. We don't need frequent maintenance, but I want to stay connected."

Relationship state may include:

- How Abdoul feels about the relationship
- How close the relationship is
- How much effort Abdoul wants to invest
- What Abdoul wants from the relationship
- What he believes the relationship currently is
- What direction he wants it to move in
- How often he ideally wants to interact

The AI may help organize and summarize this information. But Abdoul remains the authority.

---

## 13. Orbits

Orbit is also the conceptual model for relationship proximity. People can occupy different relational orbits.

- **Inner Orbit** — immediate family; closest friends; people with deep emotional importance
- **Close Orbit** — strong friends; important mentors; significant collaborators
- **Active Orbit** — people Abdoul wants to maintain a meaningful relationship with
- **Extended Orbit** — acquaintances; professional contacts; people Abdoul may want to reconnect with
- **Outer Orbit** — people worth remembering; weak ties; historical contacts; people who may become relevant again

The orbit is not necessarily a measure of how much someone matters. A close family member may require little maintenance because the relationship is naturally resilient. A professional contact may require more deliberate maintenance despite being less emotionally close.

Therefore, **orbit and maintenance should be modeled separately.**

### Groups and Lists

Orbits describe how close each person is. **Groups** describe something orthogonal: the social units people form together — the roommates, the Sunday soccer crew, the cohort that became friends.

A group is a **social fact**: its members would recognize it by name. That test separates it from a **list**, which is a lens — "everyone I met through startup school," "people interested in AI." The two work completely differently:

- **Groups are created by Abdoul, and only by Abdoul.** Orbit never proposes one, even when the same five people keep appearing at events together. Naming a social unit is an act of the person inside it; a system that notices friend groups before their members name them has crossed from copilot to surveillance. Membership changes over time, and past membership is history — "was part of the climbing group in 2024" is preserved, not deleted.
- **Lists are never curated.** They are saved questions, answered fresh from the record every time — always current, requiring no maintenance. A hand-tended list rots; a question cannot.

What groups are for: speaking naturally ("had dinner with the book club"), and relational context in recall ("you always see Dom around Leon"). What lists are for: everything organizational — grouping by origin, interest, place, or era costs nothing and stays true by construction.

**Whether two people know each other is derived, never asserted.** Orbit answers from evidence — a stated relationship, an introduction, shared presence at a small event — and cites it: *"they were both at the Futureforce dinner."* It never silently concludes friendship from co-attendance.

---

## 14. Relationship Maintenance

The system should not assume: *"You haven't talked to this person recently, therefore the relationship is neglected."*

Different relationships have different natural rhythms. Instead, Orbit should consider:

- Relationship type
- Desired closeness
- Natural communication cadence
- Recent interactions
- Abdoul's stated intentions
- Open loops
- Important life events
- Whether a relationship is naturally resilient

The system should help answer *"Who might I want to reach out to right now, and why?"* — not merely *"Who has gone the longest without contact?"*

**Threads are what make this possible.** An unresolved situation with an expected outcome is a reason to reach out that has nothing to do with frequency. *"Her interview was two weeks ago"* is context. *"It has been ninety days"* is nagging.

Orbit may notice patterns in how often Abdoul actually sees someone, and may **state what it sees** — *"you have seen Sarah eight times this year, more than any year before."* It should never convert that into a recommendation, never attach a score, and never rank one relationship against another. Closeness and contact frequency are only loosely related and are sometimes inverted: a demanding colleague seen weekly is not an inner-orbit relationship, and a brother spoken to twice a year may be.

---

## 15. The Pre-Meeting Experience

One of the defining product experiences is preparing for an interaction.

Before lunch with someone Abdoul has not seen in two years, he should be able to open their profile and quickly regain context. The system should surface:

- How they met
- The last time they spoke
- Previous interactions
- Major life changes
- Current work
- Past work
- Interests
- Goals
- Important personal details
- Previous topics of conversation
- Unresolved threads
- Things Abdoul promised to do
- Things the person was waiting for
- Potential conversation starters

The goal is not to provide a generic AI summary. The goal is: **"Everything comes back."**

In practice this means a consistent shape, so Abdoul learns where to look and can absorb it in the ninety seconds before walking in:

1. **Who** — how they met, when they last spoke
2. **Open threads** — what is unresolved in their life
3. **Loops** — what he owes, and what he is owed
4. **What has changed** — since he last knew
5. **Things he would have forgotten** — details that have not surfaced in a long time
6. **Timeline** — the full history, on scroll

**Section five is the heart of it.** The ranking question is not *what is most important about this person* — the important things are the ones Abdoul already remembers without help. It is **what is he most likely to have forgotten**. That inversion is what produces *"I can't believe you remembered that,"* and it is the same thing the north star asks for.

That section has no fixed size. Some relationships will surface two things, others forty, and both should feel composed rather than sparse or overwhelming.

---

## 16. Relationship Memory Should Be Searchable

Orbit should support natural-language queries:

- "What was the name of the person who wanted to travel to Japan?"
- "Who did I meet at that conference who works in AI infrastructure?"
- "Who has talked to me about videography?"
- "Who do I know that is interested in startups?"
- "Who have I met through Alex?"
- "Who was working at Google before joining Stripe?"
- "Who have I not seen in two years?"

The system should search across events, profiles, historical facts, and relationship context.

---

## 17. Network Intelligence

Orbit should eventually reason about the network:

- "Who can introduce me to someone at Anthropic?"
- "Who do I know at Goldman Sachs?"
- "Who is connected to people in quantitative trading?"
- "Who should I talk to if I want to learn videography?"
- "Who in my network would be interested in building this product?"
- "Who are the best two engineers I know for this project?"

This may require the system to understand direct relationships, second-degree connections, shared organizations, shared interests, skills, past experiences, trust, relationship strength, and willingness to make introductions.

The system should eventually move from **search** → **reasoning** → **network intelligence**.

Answering these requires holding some information about people Abdoul has **never met** — the engineer a friend keeps mentioning, someone's colleague at a company he cares about. These are not relationships and Orbit must never treat them as such: no orbit, no maintenance, no suggestions to reach out. They exist so that introductions are findable, and nothing more.

When Abdoul does eventually meet one of them, what he was told secondhand should be **reconfirmed rather than silently absorbed**. Firsthand experience routinely diverges from someone else's account of a person.

---

## 18. The Core Product Experience

Orbit should have three fundamental modes:

1. **Capture** — "What happened?" Abdoul speaks naturally. Orbit records and structures the event.
2. **Recall** — "Who is this person, and what do I remember about them?" Orbit reconstructs the relationship.
3. **Discover** — "Who do I know that can help with this?" Orbit searches and reasons over the network.

Together: **Capture → Remember → Discover**

### The Use-Case Inventory

The three modes are abstractions. These are the concrete jobs Orbit gets hired for — the inventory that surfaces, screens, and entry points must answer to. Frequency drives prominence: something done daily earns the center of a screen; something done twice a year earns a menu.

#### Capturing life — daily

| Use case | Example |
| --- | --- |
| Post-event debrief | "Had lunch with Sarah…" — spoken within hours of any interaction: breakfast, a run, a dinner, a call |
| Group event capture | "Met Alex, Sarah, James, and Maria at the conference…" |
| Secondhand news | "Alex told me Maria just got back from Japan" |
| Contact details | Pasting an Instagram handle after exchanging socials; "her email is…" mid-memo |
| Micro-note | "Sarah's birthday is March 3" — a remembered fact with no interaction attached |
| Relationship reflection | Describing in his own words what a relationship is and where he wants it to go (§12) — occasional, not per-event |
| Backfill portrait | Onboarding: sitting down to describe someone he's known for years, from scratch |

#### Before seeing someone — weekly

| Use case | Example |
| --- | --- |
| Scheduled prep | Reading the full brief before a lunch |
| The 60-second walk-in | Deck mode, walking to the door |
| Long-gap revival | "I haven't seen this person in two years" — the founding scenario |
| Mid-conversation check | The bathroom glance: recalling something *already in their profile from past captures* — "what's her boyfriend's name again?" Nothing is captured mid-conversation; this is retrieval only, and it must be fast and fragment-searchable |
| Incoming-name placement | A call or text from a name he can't place: "how do I know this person?" |

#### Answering questions about people — weekly

| Use case | Example |
| --- | --- |
| Direct name search | "Sarah" — including nicknames and misspellings |
| Fragment search | Tip-of-the-tongue: "the guy from Greece at the picnic" — attributes, not names |
| Fact lookup | "Where does James work now?" "What's Sarah's brother's situation?" |
| Provenance check | "Did she tell me that, or did Alex? When did I learn it?" — verifying his own memory |
| Promise check | "What have I left open — with her, or with anyone?" |
| Timeline check | "When did I last see her? What did we do?" |

#### Finding people for a need — weekly to monthly

| Use case | Example |
| --- | --- |
| Company | "Who do I know at Google?" |
| Warm path | "Who can connect me to someone at Anthropic?" — includes people known only secondhand |
| Expertise | "Who knows low-latency systems?" "Who should I ask about visas?" |
| Interest | "Who's into videography?" |
| Place | "I'm in New York next week — who's there?" |
| Event or origin | "Who did I meet at startup school?" "Who do I know through Alex?" |
| Era | "Who did I know in college?" "Who haven't I seen in two years?" |
| Brokering | "Maria wants to collaborate — who should she meet?" Introducing people to each other |
| Hosting | "I'm planning a dinner — who should come?" Groups × interests × place |
| Reconnection sweep | "I'm free this weekend — who do I want to see?" |

#### Keeping relationships alive — weekly to monthly

| Use case | Example |
| --- | --- |
| Context-rich reach-out | "Her interview was two weeks ago — ask how it went" (§14: threads, never frequency) |
| Life-event timing | The brother's visit is this month; the exam is Friday |
| Cadence reflection | "Seen Sarah less this year — or just captured less?" — observation, never recommendation |
| Loop follow-through | "You still owe Dom that essay" |
| Orbit gardening | An occasional deliberate session: updating relationship narratives, moving people between orbits |

#### Trust and upkeep — rare

| Use case | Example |
| --- | --- |
| Set-aside triage | Working through deferred proposals, at leisure |
| Duplicate merge | "These two Sarahs are the same person" |
| Correction | Fixing a wrong fact; seeing what was corrected and why |
| Export | Taking the entire memory out, readable — the data is his |

#### What the inventory implies

Nearly every use case enters through one of **three doors**:

1. **"What happened?"** — capture, in all its forms. The only daily-frequency door; it earns the center.
2. **"Who…?"** — one search field that accepts a name, a company, a fragment, or a question. The name search and "who do I know at Google" are the same door — the user should never have to know which kind of query they're making.
3. **"I'm seeing someone"** — the brief, reached through search or through whatever surfaced the person.

Maintenance never earns a door of its own: it arrives as context *inside* the other doors (a loop on a profile, a life event in a brief), because a dedicated "relationships to service" surface is the CRM Orbit must never become.

Two inventory items — the **micro-note** and the **backfill portrait** — required extending the event model: events may now have *subjects* who were not present (§7), so a remembered fact or a portrait of an old friend is captured without faking an interaction. The history inside a portrait splits the way memory itself does: **specific episodes become events on the shared timeline; ongoing truths become facts.** A decade-old friendship gets a timeline with a real beginning, not one that starts the day Orbit was installed.

---

## 19. The Product's Defining Promise

Orbit should help Abdoul do two things extraordinarily well:

**Remember people deeply** — even after long periods of time.

**Find people intelligently** — even when Abdoul does not know exactly who he is looking for.

The system should preserve both the history of relationships and the structure of the network.

---

## 20. Current One-Sentence Description

> Orbit is a personal AI memory for relationships that captures the events and details of Abdoul's life, preserves the history of the people he knows, helps him recall relationships with remarkable fidelity, and lets him intelligently search and reason over his network.

---

## 21. Current North Star

> Make the people Abdoul cares about feel like they were never forgotten.

---

## 22. Product Constitution

These are the principles Orbit should not violate as the product evolves.

### Principle 1: The Human Is the Authority

Orbit may assist with interpretation. It may suggest. It may organize. It may surface patterns. But it should not override Abdoul's understanding of his own relationships.

*AI assists. The human decides.*

### Principle 2: Never Silently Rewrite History

Past information should not disappear simply because it is no longer current. People change. Jobs change. Interests change. Relationships change. The historical record should remain intact.

*The past is context, not obsolete data.*

### Principle 3: Capture Should Be Effortless

The system should make it easy to record what happened. Natural speech should be enough. Abdoul should not have to think about schemas, fields, tags, or database structure while remembering his life.

*Speak naturally. The system does the structuring.*

### Principle 4: Accuracy Is More Important Than Automation

When the system is uncertain, it should ask or flag uncertainty. It should not confidently invent who said something, who was present, what someone meant, or how Abdoul feels about a relationship.

*Uncertainty is better than false memory.*

### Principle 5: Nothing Is Final Without Confirmation

The system may propose changes. It should not silently finalize important changes to a person's profile. Abdoul must be able to review, edit, accept, reject, or defer.

*The system can remember for you, but it cannot decide what is true for you.*

### Principle 6: Relationships Are Not Scores

People should not be reduced to a single relationship score. A relationship can be deep but infrequent, frequent but casual, professionally valuable, emotionally important, dormant but meaningful, or naturally resilient.

*Relationships are multidimensional.*

### Principle 7: Small Details Matter

The seemingly insignificant details may be the most valuable. A future trip. A difficult exam. A family member visiting. A dream someone mentioned once. A hobby. A fear. A passing comment.

These details can be the difference between *"How are you?"* and *"How did that thing you were worried about turn out?"*

*The details are the relationship.*

### Principle 8: The System Should Help Abdoul Show Up Better

The purpose is not to maximize contact frequency. The purpose is not to increase the number of messages sent. The purpose is to help Abdoul be more thoughtful, more present, and more consistent with the people he cares about.

*Better relationships, not more activity.*

### Principle 9: Context Before Contact

Before suggesting that Abdoul reach out to someone, Orbit should understand the context. A reminder without context is noise. A reminder with context can be valuable.

Instead of *"Message Sarah."* prefer *"Sarah was nervous about her interview the last time you spoke. You might want to ask how it went."*

*The reason matters as much as the reminder.*

### Principle 10: The System Should Feel Like Memory, Not Administration

The product should never feel like maintaining a CRM. The user should feel like they are remembering, reflecting, preparing, discovering, reconnecting.

*Orbit should feel like an extension of memory, not a database demanding maintenance.*

### Principle 11: Relationships Should Be Allowed to Change

People move between orbits. A relationship can become closer, more distant, dormant, or important again. Orbit should make change visible without treating change as failure.

*Relationships are living things.*

### Principle 12: Preserve the Human Meaning of the Relationship

The ultimate purpose of Orbit is not to know more facts about people. It is to help Abdoul maintain meaningful human connections. The system should never lose sight of the fact that behind every profile is a real person.

*The data exists to serve the relationship. Never the other way around.*

---

## Final Product Constitution

If Orbit ever becomes complicated, the following question should guide product decisions:

> Does this help Abdoul remember people more deeply, show up for them more thoughtfully, or discover meaningful connections within his network?

If the answer is no, the feature should be questioned.

The ultimate goal is simple: **People should feel remembered.**
