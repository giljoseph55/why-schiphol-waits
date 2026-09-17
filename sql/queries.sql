-- =====================================================================
--  Why Schiphol waits: every published figure, as a query
--  Database : atfm.db (SQLite)
--  Source   : EUROCONTROL PRU, Airport Arrival ATFM Delay (APT-DLY)
--             downloaded 16 September 2026 from ansperformance.eu/data
--  Author   : Gilroy Joseph
--
--  Schema
--    airport(icao PK, name, state)
--    cause_code(code PK, cause_name, cause_group)
--    arrivals(icao FK, flt_date, yr, mth, arrivals, delay_min_total,
--             arr_delayed, arr_delayed_15)                PK (icao, flt_date)
--    delay_by_cause(icao FK, flt_date, code FK, delay_min) PK (icao, flt_date, code)
--
--  delay_by_cause holds only non-zero rows: 65,985 of a possible 16.5m.
--  Most airport-days carry no flow-management delay at all.
--
--  Every query below is restricted to January-July so that 2026, which
--  ends on 31 July, is compared against the same seven months in every
--  earlier year.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q0.  INTEGRITY CHECK. Run this first, before trusting anything else.
--      The sixteen cause rows must sum to the reported total column.
--      Expected: 7409233 = 7409233, difference 0.
-- ---------------------------------------------------------------------
SELECT
    ROUND(SUM(a.delay_min_total))                       AS total_column,
    (SELECT ROUND(SUM(d.delay_min))
       FROM delay_by_cause d
       JOIN arrivals x ON x.icao = d.icao AND x.flt_date = d.flt_date
      WHERE x.yr = 2025)                                AS sum_of_causes,
    ROUND(SUM(a.delay_min_total)) -
    (SELECT ROUND(SUM(d.delay_min))
       FROM delay_by_cause d
       JOIN arrivals x ON x.icao = d.icao AND x.flt_date = d.flt_date
      WHERE x.yr = 2025)                                AS difference
FROM arrivals a
WHERE a.yr = 2025;


-- ---------------------------------------------------------------------
-- Q1.  THE RANKING  (page 03, and the appendix table)
--      Minutes of arrival ATFM delay per landing, 2026 Jan-Jul.
--      Published: Schiphol 3.03, Zurich 2.54 ... Rome 0.06
-- ---------------------------------------------------------------------
WITH peer AS (
    SELECT column1 AS icao FROM (VALUES
        ('EHAM'),('EGLL'),('LFPG'),('EDDF'),('EDDM'),
        ('LSZH'),('LEMD'),('EKCH'),('EBBR'),('LIRF'))
)
SELECT  p.name                                              AS airport,
        SUM(a.arrivals)                                     AS arrivals,
        ROUND(SUM(a.delay_min_total) * 1.0 / SUM(a.arrivals), 2)
                                                            AS min_per_landing,
        ROUND(SUM(a.arr_delayed_15) * 100.0 / SUM(a.arrivals), 1)
                                                            AS pct_over_15_min
FROM arrivals a
JOIN airport p  ON p.icao = a.icao
JOIN peer      ON peer.icao = a.icao
WHERE a.yr = 2026 AND a.mth <= 7
GROUP BY p.name
ORDER BY min_per_landing DESC;


-- ---------------------------------------------------------------------
-- Q2.  CAUSE BREAKDOWN, SCHIPHOL AGAINST THE PEER MEDIAN  (page 05)
--      SQLite has no MEDIAN(), so it is built with a window function.
--      The median of nine is row 5 of nine when ordered.
--      Published: Aerodrome Capacity 1.287 against 0.112
-- ---------------------------------------------------------------------
WITH peer AS (
    SELECT column1 AS icao FROM (VALUES
        ('EGLL'),('LFPG'),('EDDF'),('EDDM'),
        ('LSZH'),('LEMD'),('EKCH'),('EBBR'),('LIRF'))
),
-- delay_by_cause stores only non-zero rows, so an airport with no delay
-- under a given code has no row at all. Building the full grid first and
-- coalescing to zero is what keeps the median honest: an airport that
-- recorded nothing must still count as a zero, not vanish from the set.
grid AS (
    SELECT t.icao, c.code, t.arrivals
    FROM (SELECT icao, SUM(arrivals) AS arrivals
            FROM arrivals WHERE yr = 2026 AND mth <= 7
           GROUP BY icao) t
    CROSS JOIN cause_code c
),
totals AS (
    SELECT d.icao, d.code, SUM(d.delay_min) AS mins
    FROM delay_by_cause d
    JOIN arrivals a ON a.icao = d.icao AND a.flt_date = d.flt_date
    WHERE a.yr = 2026 AND a.mth <= 7
    GROUP BY d.icao, d.code
),
per_airport AS (
    SELECT  g.icao,
            g.code,
            COALESCE(t.mins, 0) * 1.0 / g.arrivals AS min_per_landing
    FROM grid g
    LEFT JOIN totals t ON t.icao = g.icao AND t.code = g.code
),
ranked AS (
    SELECT  pa.code,
            pa.min_per_landing,
            ROW_NUMBER() OVER (PARTITION BY pa.code ORDER BY pa.min_per_landing) AS rn,
            COUNT(*)     OVER (PARTITION BY pa.code)                             AS n
    FROM per_airport pa
    JOIN peer ON peer.icao = pa.icao
)
SELECT  c.cause_name,
        c.cause_group,
        ROUND(COALESCE(mo.min_per_landing, 0), 3)   AS schiphol,
        ROUND(COALESCE(med.v, 0), 3)                AS peer_median,
        ROUND(COALESCE(mo.min_per_landing, 0)
              - COALESCE(med.v, 0), 3)              AS gap
FROM cause_code c
LEFT JOIN per_airport mo ON mo.code = c.code AND mo.icao = 'EHAM'
LEFT JOIN (SELECT code, AVG(min_per_landing) AS v
             FROM ranked
            WHERE rn IN ((n + 1) / 2, (n + 2) / 2)
            GROUP BY code) med ON med.code = c.code
ORDER BY schiphol DESC;


-- ---------------------------------------------------------------------
-- Q3.  AERODROME CAPACITY, EIGHT YEARS  (page 06)
--      Published: Schiphol highest in six of eight years.
--      Zurich higher in 2021, Frankfurt higher in 2023.
-- ---------------------------------------------------------------------
WITH peer AS (
    SELECT column1 AS icao FROM (VALUES
        ('EHAM'),('EGLL'),('LFPG'),('EDDF'),('EDDM'),
        ('LSZH'),('LEMD'),('EKCH'),('EBBR'),('LIRF'))
),
g AS (
    SELECT  a.yr,
            a.icao,
            COALESCE(SUM(d.delay_min), 0) * 1.0 / SUM(a.arrivals) AS g_min
    FROM arrivals a
    JOIN peer ON peer.icao = a.icao
    LEFT JOIN delay_by_cause d
           ON d.icao = a.icao AND d.flt_date = a.flt_date AND d.code = 'G'
    WHERE a.mth <= 7
    GROUP BY a.yr, a.icao
),
ranked AS (
    SELECT yr, icao, g_min,
           ROW_NUMBER() OVER (PARTITION BY yr ORDER BY g_min DESC) AS worst_rank
    FROM g
)
SELECT  r.yr,
        ROUND(MAX(CASE WHEN r.icao = 'EHAM' THEN r.g_min END), 2) AS schiphol,
        ROUND(MAX(CASE WHEN r.icao = 'LSZH' THEN r.g_min END), 2) AS zurich,
        MAX(CASE WHEN r.worst_rank = 1 THEN p.name END)           AS worst_airport,
        ROUND(MAX(CASE WHEN r.worst_rank = 1 THEN r.g_min END), 2) AS worst_value
FROM ranked r
JOIN airport p ON p.icao = r.icao
GROUP BY r.yr
ORDER BY r.yr;


-- ---------------------------------------------------------------------
-- Q4.  IS IT A FEW BAD DAYS?  (page 07)
--      Share of the year's delay minutes falling on the ten worst days.
--      Published: Schiphol 31%, Munich 70%, Madrid 59%, Rome 100%.
-- ---------------------------------------------------------------------
WITH peer AS (
    SELECT column1 AS icao FROM (VALUES
        ('EHAM'),('EGLL'),('LFPG'),('EDDF'),('EDDM'),
        ('LSZH'),('LEMD'),('EKCH'),('EBBR'),('LIRF'))
),
daily AS (
    SELECT a.icao, a.flt_date, a.delay_min_total AS m,
           ROW_NUMBER() OVER (PARTITION BY a.icao ORDER BY a.delay_min_total DESC) AS rn
    FROM arrivals a
    JOIN peer ON peer.icao = a.icao
    WHERE a.yr = 2026 AND a.mth <= 7
)
SELECT  p.name                                                   AS airport,
        ROUND(SUM(CASE WHEN d.rn <= 10 THEN d.m ELSE 0 END) * 100.0
              / NULLIF(SUM(d.m), 0), 0)                          AS pct_from_worst_10_days,
        ROUND(SUM(CASE WHEN d.rn <= 30 THEN d.m ELSE 0 END) * 100.0
              / NULLIF(SUM(d.m), 0), 0)                          AS pct_from_worst_30_days
FROM daily d
JOIN airport p ON p.icao = d.icao
GROUP BY p.name
ORDER BY pct_from_worst_10_days;


-- ---------------------------------------------------------------------
-- Q5.  WEATHER REMOVED  (page 04, and the appendix)
--      The place my own argument gives way: Zurich is worse than
--      Schiphol once weather and de-icing come out.
--      Published: Zurich 1.735, Schiphol 1.326
-- ---------------------------------------------------------------------
WITH peer AS (
    SELECT column1 AS icao FROM (VALUES
        ('EHAM'),('EGLL'),('LFPG'),('EDDF'),('EDDM'),
        ('LSZH'),('LEMD'),('EKCH'),('EBBR'),('LIRF'))
),
base AS (
    SELECT icao, SUM(arrivals) AS arrivals, SUM(delay_min_total) AS total
    FROM arrivals WHERE yr = 2026 AND mth <= 7 GROUP BY icao
),
wx AS (
    SELECT d.icao, SUM(d.delay_min) AS weather
    FROM delay_by_cause d
    JOIN arrivals a ON a.icao = d.icao AND a.flt_date = d.flt_date
    WHERE a.yr = 2026 AND a.mth <= 7 AND d.code IN ('W','D')
    GROUP BY d.icao
)
SELECT  p.name                                                        AS airport,
        ROUND(b.total / b.arrivals, 3)                                AS all_causes,
        ROUND(COALESCE(w.weather, 0) / b.arrivals, 3)                 AS weather,
        ROUND((b.total - COALESCE(w.weather, 0)) / b.arrivals, 3)     AS non_weather
FROM base b
JOIN peer ON peer.icao = b.icao
JOIN airport p ON p.icao = b.icao
LEFT JOIN wx w ON w.icao = b.icao
ORDER BY non_weather DESC;


-- ---------------------------------------------------------------------
-- Q6.  WHY ZURICH DOES NOT OVERTURN THE FINDING  (page 04)
--      Zurich's non-weather delay sits in the unnamed code "Other".
--      Published: 1.248 of Zurich's 1.735.
-- ---------------------------------------------------------------------
SELECT  c.cause_name,
        ROUND(SUM(d.delay_min) * 1.0 / t.arrivals, 3) AS min_per_landing
FROM delay_by_cause d
JOIN arrivals a   ON a.icao = d.icao AND a.flt_date = d.flt_date
JOIN cause_code c ON c.code = d.code
CROSS JOIN (SELECT SUM(arrivals) AS arrivals FROM arrivals
             WHERE icao = 'LSZH' AND yr = 2026 AND mth <= 7) t
WHERE d.icao = 'LSZH' AND a.yr = 2026 AND a.mth <= 7
GROUP BY c.cause_name, t.arrivals
ORDER BY min_per_landing DESC;
