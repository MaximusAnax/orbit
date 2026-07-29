#!/usr/bin/env python3
"""T1 property suite for the ledger SQL (schema + triggers + read models).

Runs the DATA-MODEL invariants against the exact .sql resources the app ships,
on the same SQLite engine. The Swift suite (OrbitInvariantTests) re-verifies the
same properties through the production code path in CI; check IDs match EVALS.md.
"""
from __future__ import annotations

import itertools
import random
import sqlite3
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
RES = ROOT / "Sources" / "OrbitStore" / "Resources"

PASS: list[str] = []


def new_db() -> sqlite3.Connection:
    con = sqlite3.connect(":memory:")
    con.execute("PRAGMA foreign_keys=ON")
    for name in ("001_schema.sql", "002_triggers.sql", "003_readmodels.sql"):
        con.executescript((RES / name).read_text())
    return con


def rebuild(con: sqlite3.Connection) -> None:
    con.executescript((RES / "004_rebuild_readmodels.sql").read_text())


def uid() -> str:
    return str(uuid.uuid4())


def ok(check: str) -> None:
    PASS.append(check)


def expect_abort(con, check, sql, params=()):
    try:
        con.execute(sql, params)
    except sqlite3.IntegrityError:
        ok(check)
        return
    raise AssertionError(f"{check}: expected abort, statement succeeded: {sql}")


# ── fixtures ─────────────────────────────────────────────────────────

def add_person(con, name, status="active", is_self=0, pid=None):
    pid = pid or uid()
    con.execute(
        "INSERT INTO person (id, display_name, status, is_self, created_at) VALUES (?,?,?,?,?)",
        (pid, name, status, is_self, "2026-01-01T00:00:00Z"),
    )
    return pid


def add_event(con, kind="dinner", occurred="2026-07-01T20:00:00Z", lifecycle="confirmed",
              participants=(), transcript="…", derived_from=None, eid=None):
    eid = eid or uid()
    con.execute(
        """INSERT INTO event (id, occurred_at, kind, transcript, lifecycle, captured_at,
                              confirmed_at, derived_from_event_id)
           VALUES (?,?,?,?,?,?,?,?)""",
        (eid, occurred, kind, transcript, "captured", occurred, None, derived_from),
    )
    for pid, attendance in participants:
        con.execute(
            "INSERT INTO event_participant (event_id, person_id, attendance) VALUES (?,?,?)",
            (eid, pid, attendance),
        )
    if lifecycle == "confirmed":
        con.execute(
            "UPDATE event SET lifecycle='confirmed', confirmed_at=? WHERE id=?",
            (occurred, eid),
        )
    return eid


def add_assertion(con, subject, event, predicate="interest", verbatim="she loves x",
                  observed="2026-07-01T21:00:00Z", valid_from=None, valid_to=None,
                  source_kind="firsthand", attributed_to=None, entity=None,
                  object_value=None, status="active", aid=None):
    aid = aid or uid()
    con.execute(
        """INSERT INTO assertion (id, subject_id, predicate, object_entity_id, object_value,
               verbatim, valid_from, valid_to, observed_at, source_event_id, source_kind,
               attributed_to_person_id, status, retraction_reason)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (aid, subject, predicate, entity, object_value, verbatim, valid_from, valid_to,
         observed, event, source_kind, attributed_to, status,
         "test" if status == "retracted" else None),
    )
    return aid


# ── INV-1 / INV-3: history is never rewritten ────────────────────────

def test_inv1_events():
    con = new_db()
    p = add_person(con, "Sarah")
    e = add_event(con, participants=[(p, "confirmed")], transcript="original words")
    expect_abort(con, "INV-1 confirmed transcript frozen",
                 "UPDATE event SET transcript='rewritten' WHERE id=?", (e,))
    expect_abort(con, "INV-1 confirmed occurred_at frozen",
                 "UPDATE event SET occurred_at='2020-01-01T00:00:00Z' WHERE id=?", (e,))
    expect_abort(con, "INV-1 event delete denied", "DELETE FROM event WHERE id=?", (e,))
    # audio deletion is the one allowed post-confirmation change (§7.5)
    con.execute("UPDATE event SET raw_audio_ref=NULL WHERE id=?", (e,))
    ok("INV-1 audio-clear permitted post-confirmation")
    # captured events remain editable (transcript review happens pre-confirmation)
    e2 = add_event(con, lifecycle="captured", participants=[(p, "confirmed")])
    con.execute("UPDATE event SET transcript='edited during review' WHERE id=?", (e2,))
    ok("INV-1 captured events editable pre-confirmation")
    expect_abort(con, "confirmation requires timestamp",
                 "UPDATE event SET lifecycle='confirmed' WHERE id=?", (e2,))
    # participants of reviewed events frozen
    expect_abort(con, "INV-1 participants frozen after review",
                 "DELETE FROM event_participant WHERE event_id=?", (e,))


def test_inv1_inv3_assertions():
    con = new_db()
    p = add_person(con, "Sarah")
    e = add_event(con, participants=[(p, "confirmed")])
    a = add_assertion(con, p, e, predicate="employment", object_value="Google",
                      verbatim="works at Google")
    expect_abort(con, "INV-1 verbatim frozen",
                 "UPDATE assertion SET verbatim='works at Alphabet' WHERE id=?", (a,))
    expect_abort(con, "INV-1 provenance frozen",
                 "UPDATE assertion SET source_event_id=? WHERE id=?", (uid(), a))
    expect_abort(con, "INV-1 assertion delete denied", "DELETE FROM assertion WHERE id=?", (a,))
    # CLOSE: valid_to only (INV-3)
    con.execute("UPDATE assertion SET valid_to='2026-06-01' WHERE id=?", (a,))
    ok("INV-3 CLOSE sets valid_to")
    expect_abort(con, "INV-3 re-close denied",
                 "UPDATE assertion SET valid_to='2026-07-01' WHERE id=?", (a,))
    a2 = add_assertion(con, p, e, predicate="employment", object_value="Stripe",
                       verbatim="works at Stripe now")
    expect_abort(con, "INV-3 CLOSE touching another column denied",
                 "UPDATE assertion SET valid_to='2026-06-01', object_value='X' WHERE id=?", (a2,))
    # CORRECT: retraction with reason; reason required by CHECK
    con.execute("UPDATE assertion SET status='retracted', retraction_reason='was wrong' WHERE id=?", (a2,))
    ok("Decision-2 CORRECT retracts with reason")
    expect_abort(con, "CORRECT is one-way",
                 "UPDATE assertion SET status='active', retraction_reason=NULL WHERE id=?", (a2,))
    # operational fields stay writable
    a3 = add_assertion(con, p, e)
    con.execute("UPDATE assertion SET pinned=1, muted=0, last_surfaced_at='2026-07-02' WHERE id=?", (a3,))
    ok("operational ranking fields writable")


def test_inv2_audit_visibility():
    con = new_db()
    p = add_person(con, "Maria")
    e = add_event(con, participants=[(p, "confirmed")])
    a = add_assertion(con, p, e, status="retracted")
    rebuild(con)
    audit = con.execute("SELECT COUNT(*) FROM assertion WHERE id=?", (a,)).fetchone()[0]
    exposed = con.execute("SELECT COUNT(*) FROM rm_current_state WHERE assertion_id=?", (a,)).fetchone()[0]
    assert audit == 1 and exposed == 0
    ok("INV-2 retracted: queryable in audit, excluded from read models")


# ── INV-8 / INV-10: uncertainty stored, not resolved ─────────────────

def test_inv8_unresolved_subjects():
    con = new_db()
    p1, p2 = add_person(con, "James"), add_person(con, "Alex")
    e = add_event(con, participants=[(p1, "confirmed"), (p2, "confirmed")])
    a = add_assertion(con, None, e, verbatim="someone works in AI infra")
    con.execute("INSERT INTO assertion_subject_candidate VALUES (?,?)", (a, p1))
    con.execute("INSERT INTO assertion_subject_candidate VALUES (?,?)", (a, p2))
    rebuild(con)
    assert con.execute("SELECT COUNT(*) FROM rm_current_state WHERE assertion_id=?", (a,)).fetchone()[0] == 0
    ok("INV-8 unresolved subject absent from every read model")
    # resolution: subject NULL→value allowed, then candidates can't be added
    con.execute("UPDATE assertion SET subject_id=? WHERE id=?", (p1, a))
    expect_abort(con, "candidates denied once resolved",
                 "INSERT INTO assertion_subject_candidate VALUES (?,?)", (a, p2))
    expect_abort(con, "resolved subject immutable",
                 "UPDATE assertion SET subject_id=? WHERE id=?", (p2, a))


def test_inv10_hearsay_marking():
    con = new_db()
    p, alex = add_person(con, "Sarah"), add_person(con, "Alex")
    e = add_event(con, participants=[(alex, "confirmed")])
    expect_abort(con, "INV-10 secondhand requires attribution",
                 """INSERT INTO assertion (id, subject_id, predicate, verbatim, observed_at,
                    source_event_id, source_kind) VALUES (?,?,?,?,?,?,?)""",
                 (uid(), p, "life_event", "Sarah got engaged", "2026-07-01", e, "secondhand"))
    expect_abort(con, "INV-10 firsthand forbids attribution",
                 """INSERT INTO assertion (id, subject_id, predicate, verbatim, observed_at,
                    source_event_id, source_kind, attributed_to_person_id) VALUES (?,?,?,?,?,?,?,?)""",
                 (uid(), p, "life_event", "x", "2026-07-01", e, "firsthand", alex))
    add_assertion(con, p, e, source_kind="secondhand", attributed_to=alex,
                  predicate="life_event", verbatim="Alex told me Sarah got engaged")
    ok("INV-10 hearsay carries who said it")


# ── INV-11/12/13/14: contact is sacred ───────────────────────────────

def test_contact_guards():
    con = new_db()
    sarah = add_person(con, "Sarah")
    dom = add_person(con, "Dom")
    # real dinner (counts), note about Sarah (never counts), reconstructed event (never counts)
    dinner = add_event(con, participants=[(sarah, "confirmed")], occurred="2026-07-03T20:00:00Z")
    add_event(con, kind="note", participants=[(sarah, "about")], occurred="2026-07-10T09:00:00Z")
    portrait = add_event(con, kind="portrait", participants=[(dom, "about")], occurred="2026-07-11T09:00:00Z")
    add_event(con, participants=[(sarah, "confirmed")], occurred="2026-07-12T20:00:00Z",
              derived_from=portrait)
    rebuild(con)
    rows = con.execute(
        "SELECT month, event_count FROM rm_contact_rhythm WHERE person_id=?", (sarah,)
    ).fetchall()
    assert rows == [("2026-07", 1)], rows
    ok("INV-11 notes never count as contact; INV-12 reconstructed never enters rate math")
    # co-attendance: about never creates knows-each-other; small-event cap holds
    e = add_event(con, participants=[(sarah, "confirmed"), (dom, "about")])
    rebuild(con)
    assert con.execute("SELECT COUNT(*) FROM rm_network_edge WHERE edge_kind='co_attendance'").fetchone()[0] == 0
    ok("INV-13 co-attendance derives from present attendance only")
    big = add_event(con, participants=[(add_person(con, f"P{i}"), "confirmed") for i in range(8)])
    rebuild(con)
    assert con.execute(
        "SELECT COUNT(*) FROM rm_network_edge WHERE edge_kind='co_attendance' AND evidence_id=?", (big,)
    ).fetchone()[0] == 0
    ok("co-attendance capped to small events (8-person event emits no edges)")
    # INV-14
    note = add_event(con, kind="note", participants=[(sarah, "about")])
    expect_abort(con, "INV-14 first_met never a note",
                 "UPDATE person SET first_met_event_id=? WHERE id=?", (note, sarah))
    con.execute("UPDATE person SET first_met_event_id=? WHERE id=?", (dinner, sarah))
    ok("INV-14 first_met anchors to an attended meeting")


# ── INV-17: merge by pointer, unmerge exact ──────────────────────────

def test_inv17_merge_unmerge():
    con = new_db()
    winner = add_person(con, "Sarah Chen")
    loser = add_person(con, "Sarah C.")
    e = add_event(con, participants=[(loser, "confirmed")])
    add_assertion(con, loser, e, predicate="interest", verbatim="wants to learn videography")
    rebuild(con)
    before = con.execute("SELECT * FROM rm_current_state ORDER BY assertion_id").fetchall()
    assert before[0][1] == loser
    # merge: pointer only — zero assertion rows rewritten
    con.execute("UPDATE person SET merged_into=?, status='merged' WHERE id=?", (winner, loser))
    rebuild(con)
    after_merge = con.execute("SELECT subject_id FROM rm_current_state").fetchall()
    assert after_merge == [(winner,)]
    raw_subject = con.execute("SELECT subject_id FROM assertion").fetchone()[0]
    assert raw_subject == loser  # log untouched
    ok("INV-17 merge resolves at read time; zero rows rewritten")
    # unmerge: clear one field, results restore exactly
    con.execute("UPDATE person SET merged_into=NULL, status='active' WHERE id=?", (loser,))
    rebuild(con)
    restored = con.execute("SELECT * FROM rm_current_state ORDER BY assertion_id").fetchall()
    assert restored == before
    ok("INV-17 unmerge restores pre-merge query results exactly")


# ── INV-22/23: the self ──────────────────────────────────────────────

def test_self_scope():
    con = new_db()
    me = add_person(con, "Abdoul", is_self=1)
    expect_abort(con, "INV-22 second self row denied",
                 "INSERT INTO person (id, display_name, status, is_self, created_at) VALUES (?,?,?,?,?)",
                 (uid(), "Impostor", "active", 1, "2026-01-01"))
    other = add_person(con, "Eliah")
    expect_abort(con, "INV-22 self never merges",
                 "UPDATE person SET merged_into=?, status='merged' WHERE id=?", (other, me))
    expect_abort(con, "INV-22 is_self immutable",
                 "UPDATE person SET is_self=0 WHERE id=?", (me,))
    e = add_event(con, participants=[(me, "confirmed")])
    for check, sql, params in [
        ("INV-23 self has no relationship state",
         "INSERT INTO relationship_state (id, person_id, authored_by, created_at) VALUES (?,?,?,?)",
         (uid(), me, "human", "2026-01-01")),
        ("INV-23 self has no threads",
         "INSERT INTO thread (id, person_id, title, archetype, opened_event_id) VALUES (?,?,?,?,?)",
         (uid(), me, "x", "decision", e)),
        ("INV-23 self has no loops",
         "INSERT INTO open_loop (id, person_id, source_event_id, direction, description) VALUES (?,?,?,?,?)",
         (uid(), me, e, "abdoul_owes", "x")),
    ]:
        expect_abort(con, check, sql, params)
    ghost = add_person(con, "Friend-of-friend", status="known_of")
    expect_abort(con, "INV-9 known_of never receives relationship state",
                 "INSERT INTO relationship_state (id, person_id, authored_by, created_at) VALUES (?,?,?,?)",
                 (uid(), ghost, "human", "2026-01-01"))
    # but the self accumulates plain assertions (that's the point of §7.12)
    add_assertion(con, me, e, predicate="education", verbatim="CS at Carnegie Mellon")
    ok("INV-22 self accumulates ordinary assertions")


# ── proposals & threads ──────────────────────────────────────────────

def test_proposal_machine():
    con = new_db()
    p = add_person(con, "Sarah")
    e = add_event(con, participants=[(p, "confirmed")])
    x = uid(); s = uid(); prop = uid()
    con.execute("INSERT INTO extraction VALUES (?,?,1,'m','v1','2026-07-01','{}',NULL)", (x, e))
    con.execute("INSERT INTO sync_run VALUES (?,?,?,'2026-07-01',NULL)", (s, e, x))
    con.execute(
        "INSERT INTO proposal (id, sync_run_id, op, payload, rationale) VALUES (?,?,?,?,?)",
        (prop, s, "ASSERT", '{"predicate":"interest"}', "she said so at dinner"),
    )
    expect_abort(con, "proposal content immutable",
                 "UPDATE proposal SET payload='{}' WHERE id=?", (prop,))
    con.execute("UPDATE proposal SET state='deferred' WHERE id=?", (prop,))
    con.execute("UPDATE proposal SET state='accepted', resolved_at='2026-07-02' WHERE id=?", (prop,))
    expect_abort(con, "resolved proposals stay resolved",
                 "UPDATE proposal SET state='pending' WHERE id=?", (prop,))
    expect_abort(con, "rejected proposals are kept",
                 "DELETE FROM proposal WHERE id=?", (prop,))
    ok("proposal lifecycle: pending→deferred→accepted, one-way")
    # review outcomes are append-only (J-12)
    ro = uid()
    con.execute("INSERT INTO review_outcome (id, proposal_id, action, created_at) VALUES (?,?,?,?)",
                (ro, prop, "accepted", "2026-07-02"))
    expect_abort(con, "review outcomes append-only", "DELETE FROM review_outcome WHERE id=?", (ro,))


def test_thread_rules():
    con = new_db()
    p = add_person(con, "Sarah")
    e = add_event(con, participants=[(p, "confirmed")])
    t = uid()
    con.execute(
        "INSERT INTO thread (id, person_id, title, archetype, opened_event_id) VALUES (?,?,?,?,?)",
        (t, p, "the Boston move", "decision", e),
    )
    expect_abort(con, "threads never deleted", "DELETE FROM thread WHERE id=?", (t,))
    expect_abort(con, "thread resolution records its cause",
                 "UPDATE thread SET state='resolved' WHERE id=?", (t,))
    e2 = add_event(con, participants=[(p, "confirmed")])
    con.execute("UPDATE thread SET state='resolved', resolved_by_event_id=?, resolution_note='moved!' WHERE id=?",
                (e2, t))
    ok("thread resolution flows through a real event (§9.4)")


# ── INV-4: read models rebuild deterministically ─────────────────────

def test_inv4_rebuild_determinism():
    con = new_db()
    people = [add_person(con, f"P{i}") for i in range(5)]
    for i in range(10):
        e = add_event(con, participants=[(random.choice(people), "confirmed")])
        add_assertion(con, random.choice(people), e, verbatim=f"fact {i}",
                      valid_to="2026-01-01" if i % 3 == 0 else None)
    rebuild(con)
    dump1 = [con.execute(f"SELECT * FROM {t} ORDER BY 1,2,3").fetchall()
             for t in ("rm_current_state", "rm_network_edge", "rm_contact_rhythm")]
    rebuild(con)
    dump2 = [con.execute(f"SELECT * FROM {t} ORDER BY 1,2,3").fetchall()
             for t in ("rm_current_state", "rm_network_edge", "rm_contact_rhythm")]
    assert dump1 == dump2
    ok("INV-4 rebuild is deterministic (drop+rebuild == rebuild)")


# ── INV-21: bitemporal fuzz against a shadow model ───────────────────

def test_inv21_bitemporal_fuzz():
    rng = random.Random(20260729)
    con = new_db()
    p = add_person(con, "Fuzz Subject")
    e = add_event(con, participants=[(p, "confirmed")])
    # shadow: list of dicts mirroring assertion lifecycle
    shadow = []
    tick = [0]

    def ts():
        tick[0] += 1
        return f"2026-01-{tick[0]:02d}T00:00:00Z" if tick[0] <= 28 else f"2026-02-{tick[0]-28:02d}T00:00:00Z"

    for step in range(40):
        op = rng.choice(["assert", "close", "correct"])
        if op == "assert" or not shadow:
            vf = ts()
            oa = ts()
            aid = add_assertion(con, p, e, predicate="interest",
                                verbatim=f"fact-{step}", valid_from=vf, observed=oa)
            shadow.append({"id": aid, "valid_from": vf, "valid_to": None,
                           "observed_at": oa, "status": "active", "retracted_at": None})
        elif op == "close":
            open_rows = [s for s in shadow if s["valid_to"] is None and s["status"] == "active"]
            if open_rows:
                row = rng.choice(open_rows)
                vt = ts()
                con.execute("UPDATE assertion SET valid_to=? WHERE id=?", (vt, row["id"]))
                row["valid_to"] = vt
        else:
            active = [s for s in shadow if s["status"] == "active"]
            if active:
                row = rng.choice(active)
                con.execute(
                    "UPDATE assertion SET status='retracted', retraction_reason='fuzz' WHERE id=?",
                    (row["id"],))
                row["status"] = "retracted"
                row["retracted_at"] = ts()

    # validity-time query: what was true in the world at time T
    # observation-time query: what did we believe at time T (facts learned by T,
    # still active — retraction removes belief everywhere except the audit view)
    for _ in range(30):
        t = f"2026-01-{rng.randint(1, 28):02d}T12:00:00Z"
        want_valid = sorted(s["id"] for s in shadow
                            if s["status"] == "active"
                            and s["valid_from"] <= t
                            and (s["valid_to"] is None or s["valid_to"] > t))
        got_valid = sorted(r[0] for r in con.execute(
            """SELECT id FROM assertion
               WHERE status='active' AND valid_from <= ?
                 AND (valid_to IS NULL OR valid_to > ?)""", (t, t)).fetchall())
        assert want_valid == got_valid, f"validity-time mismatch at {t}"

        want_known = sorted(s["id"] for s in shadow
                            if s["status"] == "active" and s["observed_at"] <= t)
        got_known = sorted(r[0] for r in con.execute(
            "SELECT id FROM assertion WHERE status='active' AND observed_at <= ?", (t,)).fetchall())
        assert want_known == got_known, f"observation-time mismatch at {t}"
    ok("INV-21 bitemporal fuzz: validity-time and observation-time reconstruct (40 ops × 30 probes)")


# ── DATA-MODEL §3 worked example, end to end at the SQL level ────────

def test_worked_example():
    con = new_db()
    me = add_person(con, "Abdoul", is_self=1)
    sarah = add_person(con, "Sarah")
    # pre-existing knowledge: Sarah works at Google (learned last year)
    e0 = add_event(con, occurred="2025-05-10T19:00:00Z", participants=[(sarah, "confirmed")])
    a_google = add_assertion(con, sarah, e0, predicate="employment", object_value="Google",
                             verbatim="works at Google", observed="2025-05-10T21:00:00Z",
                             valid_from="2024-01-01")
    # tonight's dinner
    dinner = add_event(con, occurred="2026-07-28T20:00:00Z", participants=[(sarah, "confirmed")],
                       transcript="I had dinner with Sarah tonight. She works at Stripe now…")
    # sync run → proposals (shapes only; op semantics tested fully in Phase 3)
    x, s = uid(), uid()
    con.execute("INSERT INTO extraction VALUES (?,?,1,'test-model','v1','2026-07-28','{}',NULL)", (x, dinner))
    con.execute("INSERT INTO sync_run VALUES (?,?,?,'2026-07-28',NULL)", (s, dinner, x))
    # accepted: ASSERT employment→Stripe, CLOSE employment→Google
    add_assertion(con, sarah, dinner, predicate="employment", object_value="Stripe",
                  verbatim="works at Stripe now", observed="2026-07-28T22:00:00Z",
                  valid_from="2026-06-01")
    con.execute("UPDATE assertion SET valid_to='2026-06-01' WHERE id=?", (a_google,))
    # edited accept: goal, "probably" hedge preserved in verbatim
    add_assertion(con, sarah, dinner, predicate="goal", object_value="Boston",
                  verbatim="thinking about moving to Boston next year — probably",
                  observed="2026-07-28T22:00:00Z")
    add_assertion(con, sarah, dinner, predicate="interest", object_value="videography",
                  verbatim="really wants to learn videography", observed="2026-07-28T22:00:00Z")
    loop = uid()
    con.execute(
        """INSERT INTO open_loop (id, person_id, source_event_id, direction, description)
           VALUES (?,?,?,?,?)""",
        (loop, sarah, dinner, "abdoul_owes", "send her the AI agents paper"))
    t = uid()
    con.execute(
        "INSERT INTO thread (id, person_id, title, archetype, opened_event_id) VALUES (?,?,?,?,?)",
        (t, sarah, "Boston move", "decision", dinner))

    # Six months later: where did Sarah work in 2024? → Google (not deleted, closed)
    probe = "2024-06-15"
    row = con.execute(
        """SELECT object_value FROM assertion
           WHERE subject_id=? AND predicate='employment' AND status='active'
             AND valid_from <= ? AND (valid_to IS NULL OR valid_to > ?)""",
        (sarah, probe, probe)).fetchall()
    assert row == [("Google",)], row
    # …and now? → Stripe, via the current-state read model
    rebuild(con)
    now = con.execute(
        "SELECT object_value FROM rm_current_state WHERE subject_id=? AND predicate='employment'",
        (sarah,)).fetchall()
    assert now == [("Stripe",)], now
    ok("worked example (§3): 'where did Sarah work in 2024' → Google; current → Stripe")


ALL = [v for k, v in sorted(globals().items()) if k.startswith("test_")]

if __name__ == "__main__":
    for t in ALL:
        t()
    print(f"sql properties: {len(PASS)} checks green")
    for c in PASS:
        print(f"  ✓ {c}")
