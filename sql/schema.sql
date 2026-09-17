-- =====================================================================
--  atfm.db schema
--
--  The source workbook is one wide table: 32 columns, one row per
--  airport per day, with sixteen delay-cause columns side by side.
--  That shape is fine for a spreadsheet and poor for querying, so it is
--  normalised into two dimensions and two facts.
-- =====================================================================

DROP TABLE IF EXISTS delay_by_cause;
DROP TABLE IF EXISTS arrivals;
DROP TABLE IF EXISTS cause_code;
DROP TABLE IF EXISTS airport;


-- Dimension: 405 airports across 43 states.
CREATE TABLE airport (
    icao   TEXT PRIMARY KEY,
    name   TEXT NOT NULL,
    state  TEXT NOT NULL
);


-- Dimension: the sixteen official EUROCONTROL ATFM delay codes.
-- Definitions: https://ansperformance.eu/definition/atfm-delay-codes/
-- cause_group is EUROCONTROL's own rollup, kept so that causes can be
-- aggregated the way they aggregate them rather than the way I would.
CREATE TABLE cause_code (
    code         TEXT PRIMARY KEY,
    cause_name   TEXT NOT NULL,
    cause_group  TEXT NOT NULL
);


-- Fact: one row per airport per day. The grain of the source file.
-- delay_min_total is carried straight from the source rather than
-- derived, so that it can be checked against the sum of the causes.
-- That check is Q0 in queries.sql and it is the first thing to run.
CREATE TABLE arrivals (
    icao             TEXT    NOT NULL REFERENCES airport(icao),
    flt_date         TEXT    NOT NULL,          -- ISO date, YYYY-MM-DD
    yr               INTEGER NOT NULL,
    mth              INTEGER NOT NULL,
    arrivals         INTEGER NOT NULL,          -- IFR arrivals
    delay_min_total  REAL    NOT NULL,          -- arrival ATFM delay, minutes
    arr_delayed      INTEGER,                   -- arrivals with any ATFM delay
    arr_delayed_15   INTEGER,                   -- arrivals delayed over 15 min
    PRIMARY KEY (icao, flt_date)
);


-- Fact: the same minutes, split by cause.
--
-- Only non-zero rows are stored: 65,985 out of a possible 16.5 million.
-- Most airport-days carry no flow-management delay at all, and writing
-- sixteen zero rows for each of them would be sixteen million rows of
-- nothing.
--
-- The cost of that choice is that an airport recording zero under a
-- given code has no row here. Any query that averages or takes a median
-- across airports must rebuild the full grid first and coalesce the
-- missing values to zero, or the absent airports drop out of the
-- denominator. Q2 in queries.sql shows how, and why it matters: getting
-- this wrong returned a median of 0.120 instead of 0.112.
CREATE TABLE delay_by_cause (
    icao       TEXT NOT NULL REFERENCES airport(icao),
    flt_date   TEXT NOT NULL,
    code       TEXT NOT NULL REFERENCES cause_code(code),
    delay_min  REAL NOT NULL,
    PRIMARY KEY (icao, flt_date, code)
);


CREATE INDEX ix_arr_yr      ON arrivals(yr, mth, icao);
CREATE INDEX ix_cause_code  ON delay_by_cause(code);
