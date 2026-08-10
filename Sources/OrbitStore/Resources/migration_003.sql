-- Migration 003 — retiring a person (FIELD-NOTES FN-29)
--
-- "Remove this person" means withdraw them from every surface, not delete them.
-- Their facts, the events they attended and the evidence they anchor all stay
-- exactly where they were; what changes is presence — the roster, search, the
-- whisper primer and the extraction context all skip them. Reversible, so it is
-- safe to do on a hunch.
--
-- A hard erase was designed alongside this and deliberately dropped. It would
-- have required a named exception in all twelve append-only triggers, which is
-- INV-1 weakened permanently in order to tidy a list — and the case that
-- motivated it (a mis-extracted "his brother" row) is a mistake, for which
-- hiding is enough. If a real erase is ever needed it is a privacy demand, not
-- a typo, and that trade gets made deliberately then.
--
-- A side table, not a column on `person`. `ALTER TABLE ... ADD COLUMN` has no
-- IF NOT EXISTS form, so a column migration cannot be idempotent, and this one
-- runs against a phone that already holds real memos. Adding a value to
-- `status`'s CHECK would be worse still: SQLite would need the whole table
-- rebuilt — create, copy, drop, rename, restore every index and foreign key.
--
-- Applied to databases created before schema_version 3. Fresh databases get
-- the same table from 001_schema.
CREATE TABLE IF NOT EXISTS person_retirement (
    person_id  TEXT PRIMARY KEY REFERENCES person(id),
    retired_at TEXT NOT NULL
);
