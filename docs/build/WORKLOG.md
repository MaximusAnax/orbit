# Build Worklog

Append-only. Each entry: date · phase · what/why · verification tier (T1 local / T2 CI / T3 device-or-secret) · check IDs touched. Newest last.

---

## 2026-07-29 · Phase 0 · Environment + scaffold

- **Mandate:** full build on `feature/initial_build` (Abdoul, in-session). BUILD.md outline ratified same day; "planning/build" branch instruction was stale and is superseded.
- **Environment found:** Ubuntu 24.04 container; libsqlite3 3.45.1 + headers (FTS5 confirmed); clang/gcc; Python 3.11; Node 22; **no Swift toolchain and no path to install one** (proxy policy denies `download.swift.org` and GitHub release assets; only npm/PyPI/crates/golang registries + this repo's git remote are reachable).
- **Consequence:** Swift verification is T2 (CI) for this session; the SQL fast-loop (`scripts/dev/sql_check.py`, T1) carries local correctness for the ledger's DDL/triggers/read-model SQL against the same SQLite engine. Recorded as BUILD.md §1.4/risk 10.
- **Scaffold landed:** SPM package (module boundaries per BUILD §2), `scripts/check.sh` single gate, write-path lint (INV-5/INV-15/SwiftUI containment), CI workflows (`core.yml` ubuntu / `app.yml` macos).
- **BLOCKER (open):** all pushes to `MaximusAnax/orbit` return 403 — both the session git gateway and the GitHub App API ("Resource not accessible by integration"). Reads work. The remote was reorganized after session start (session branch deleted; `planning/evaluation` appeared), so write permission likely changed then. **Needs Abdoul:** restore write access for the Claude GitHub integration on this repo. Until then: commits accumulate locally; push retried at every phase gate. CI (T2) is unreachable, so Swift code is verified-by-construction + SQL fast-loop only — every such claim is tiered honestly in this log.
- Also: `.github/workflows/` pushes may additionally require the `workflow` scope on the integration once write access returns — verify then.

## 2026-07-29 · Phase 1 · BUILD.md ratified content written

- `docs/BUILD.md` written per the ratified outline + environment deltas. Notable deltas from the pre-ratification outline, both argued in the doc: **no GRDB** (first-party `OrbitSQLite` wrapper — GRDB has no Linux support, and zero third-party deps in the trust core is a privacy posture, §1.2); **verification tiers** formalized (§1.4).
- README map updated to include BUILD.md. Tier: T1 (docs).
