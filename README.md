# Why Schiphol waits

**Question:** Is Schiphol's arrival delay just weather, or does something else separate it from nine comparable European hubs?

**Finding:** Schiphol averages 3.03 minutes of arrival delay per landing against a peer median of 0.73. Its largest non-weather gap is Aerodrome Capacity (1.287 vs 0.112), highest in 6 of 8 years, so weather alone does not explain it.

**So what:** At EUROCONTROL's indicative €100 per minute, the gap to the peer median is roughly €31.6m over Jan–Jul 2026, an order of magnitude and not an invoice.

Arrival flow-management delay at Amsterdam Schiphol, measured against nine comparable
European hub airports, from 1,033,177 daily airport records published by EUROCONTROL.

---

## The question

Amsterdam Schiphol is the second-busiest arrival airport in Europe. It also carries more
flow-management delay per landing than any comparable hub on the continent.

The obvious explanation is weather: a coastal airport with six runways and a lot of
crosswind. This project tests that explanation and finds it insufficient, then isolates
what actually separates Schiphol from its peers, and prices it.

## What I found

| | |
|---|---|
| Schiphol, Jan–Jul 2026 | **3.03** minutes of arrival ATFM delay per landing |
| Median of nine comparable hubs | **0.73** |
| Weather, Schiphol | 1.70, the worst of the ten |
| **Aerodrome Capacity, Schiphol** | **1.287** against a peer median of **0.112** |
| ATC Capacity and ATC Staffing | Schiphol is **better** than the peer median on both |
| Share of delay from the ten worst days | 31%, among the lowest, so this is chronic, not storm-driven |
| Position held | Highest on Aerodrome Capacity in **six of eight years**, 2019–2026 |

Priced at EUROCONTROL's own network average of €100 per ATFM delay minute, the gap between
Schiphol and the peer median comes to roughly **€31.6 million over seven months**. That
figure is an order of magnitude, not an invoice. See *Limitations*.

## Where the argument gives way

This is in the analysis, not hidden in a footnote:

**Remove weather entirely and Schiphol is not the worst.** Zürich is, at 1.735 non-weather
minutes per landing against Schiphol's 1.326.

What keeps the finding standing is that **1.248 of Zürich's 1.735 sits in the code marked
`O` (Other)**, an unclassified bucket. Schiphol's excess sits in a code with a name and a
defined meaning. Those two numbers are not the same kind of evidence, and the analysis says so.

## Data

| | |
|---|---|
| Source | EUROCONTROL Performance Review Unit, Airport Arrival ATFM Delay (APT-DLY) |
| Download | <https://ansperformance.eu/data/>, file `Airport_Arrival_ATFM_Delay.xlsx` |
| Retrieved | 16 September 2026 |
| Coverage | 1 January 2019 – 31 July 2026 · 405 airports · 43 states |
| Records | 1,033,177 airport-days |
| Licence | EUROCONTROL open performance data, attribution required |

The source workbook is ~96 MB and is **not committed to this repository**. `sql/load.py`
rebuilds the database from it. See [`data/README.md`](data/README.md).

## Method

**Window.** January to July only, in every year. The 2026 data ends on 31 July, so comparing
it against full calendar years would have flattered it. Restricting all years to the same
seven months removes that.

**Peer set.** Large Western European hubs built around a dominant network carrier: Heathrow,
Paris CDG, Frankfurt, Munich, Zürich, Madrid, Copenhagen, Brussels, Rome Fiumicino. Istanbul
handles more arrivals than Schiphol but sits outside the EU regulatory regime, so its capacity
constraints are set differently and it is excluded. Barcelona and Gatwick are excluded as
point-to-point rather than connecting operations.

**Central measure.** Delay minutes divided by arrivals, so airport size drops out.
**Median, not mean**, across the nine peers, so one outlier cannot move it.

**Integrity check, run before anything else.** The sixteen cause columns must sum to the
reported total. They do, exactly: 7,409,233 minutes against 7,409,233 for 2025, difference
zero. That check is `Q0` in [`sql/queries.sql`](sql/queries.sql).

## Data model

Normalised out of the source file's 32-column wide format:

```
airport           (icao PK, name, state)                                405 rows
cause_code        (code PK, cause_name, cause_group)                     16 rows
arrivals          (icao FK, flt_date, yr, mth, arrivals,
                   delay_min_total, arr_delayed, arr_delayed_15)  1,033,177 rows
                   PK (icao, flt_date)
delay_by_cause    (icao FK, flt_date, code FK, delay_min)            65,985 rows
                   PK (icao, flt_date, code)
```

`delay_by_cause` stores only non-zero rows: 65,985 out of a possible 16.5 million. Most
airport-days carry no flow-management delay at all.

**That sparsity caused a real bug.** The first version of the median query returned 0.120
instead of 0.112, because airports recording *zero* aerodrome-capacity delay had no row and
silently dropped out of the set, and the median was taken over seven airports instead of nine.
The fix builds the full grid with `CROSS JOIN cause_code`, `LEFT JOIN`s the aggregates and
coalesces to zero. The comment explaining it is still in the query, because it is the most
useful thing in this repository.

SQLite has no `MEDIAN()`. It is built with `ROW_NUMBER() OVER (PARTITION BY …)`.

## Running it

```bash
# 1. download Airport_Arrival_ATFM_Delay.xlsx from ansperformance.eu/data
#    into data/raw/

pip install pandas openpyxl

# 2. build the database
#    first run  ~2 min  (parses the workbook, caches the extract)
#    after that ~15 sec (reads the cache)
python sql/load.py

# 3. run any query
sqlite3 sql/atfm.db < sql/queries.sql
```

Or open `sql/atfm.db` in [DB Browser for SQLite](https://sqlitebrowser.org/) and paste
queries from `sql/queries.sql`. Results as produced on 16 September 2026 are recorded in
[`sql/query_results.txt`](sql/query_results.txt).

## What is in here

```
sql/schema.sql          the DDL on its own
sql/load.py             rebuilds the database from the source workbook
sql/queries.sql         six queries, each mapped to a published figure
sql/query_results.txt   their output, so the numbers can be checked without running anything
analysis/               Excel workbook: sources, metric definitions, KPI tables, charts
site/index.html         the findings, written to be read on a phone
```

## Limitations

**ATFM delay is not total delay.** It is assigned before departure because the destination
cannot accept the flight on time. Crew, baggage, boarding and turnaround delays are not in
this dataset at all. A flight can arrive an hour late with zero ATFM delay recorded.

**This is measured at the airport, not the airline.** It covers every carrier landing at
Schiphol, not KLM alone.

**The €100 per minute is indicative.** EUROCONTROL publishes it as a network average for
general insight and states that it should not be used for specific analyses or operational
planning. It supports an order-of-magnitude statement and nothing finer.

**I cannot see inside the airport.** Aerodrome Capacity delay points at declared capacity
against scheduled demand. Why that gap exists (runway configuration, the movement cap, slot
allocation, how often the declared rate is cut and how late) needs data I do not have.
The analysis stops where the public record stops.

**2021 is not a normal year** for any airport in this set, and 2026 covers seven months.

## Attribution

Source data © EUROCONTROL, Performance Review Unit. Delay cost reference values from
EUROCONTROL Standard Inputs for Economic Analyses, release 10.0.2, drawn from University of
Westminster, *European airline delay cost reference values*, version 4.1.

Analysis and code by **Gilroy Joseph**, [gilroybjoseph@gmail.com](mailto:gilroybjoseph@gmail.com)
· [linkedin.com/in/gilroy-joseph](https://www.linkedin.com/in/gilroy-joseph)
