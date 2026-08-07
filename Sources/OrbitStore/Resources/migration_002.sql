-- Migration 002 — person aliases (FIELD-NOTES FN-19)
--
-- Entities have had an alias table since 001; people never did, so person
-- matching ran on `display_name` alone. That is what makes a pointer-shaped
-- name dangerous: two different people's "his brother" match each other and
-- silently merge two strangers. Aliases give the person side the same safety
-- net §7.10 gives entities — every confirmed way of saying a name accumulates,
-- so matching improves instead of colliding.
--
-- Applied to databases created before schema_version 2. Fresh databases get
-- the same table from 001_schema.
CREATE TABLE IF NOT EXISTS person_alias (
    person_id TEXT NOT NULL REFERENCES person(id),
    alias     TEXT NOT NULL,
    PRIMARY KEY (person_id, alias)
);
CREATE INDEX IF NOT EXISTS person_alias_alias ON person_alias(alias);
