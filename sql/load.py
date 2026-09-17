"""
Build atfm.db from the EUROCONTROL Airport Arrival ATFM Delay workbook.

Usage
    1. put Airport_Arrival_ATFM_Delay.xlsx in data/raw/
       (download: https://ansperformance.eu/data/)
    2. pip install pandas openpyxl
    3. python sql/load.py

Takes about thirty seconds. Prints the integrity check at the end; if
that check does not come out to a difference of zero, stop and find out
why before trusting anything else.

Gilroy Joseph, September 2026
"""

from pathlib import Path
import sqlite3
import sys
import time

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "raw" / "Airport_Arrival_ATFM_Delay.xlsx"
CACHE = ROOT / "data" / "raw" / "apt_dly.csv"
DB = ROOT / "sql" / "atfm.db"
SCHEMA = ROOT / "sql" / "schema.sql"

# The sixteen official codes, with EUROCONTROL's own names and rollup.
# https://ansperformance.eu/definition/atfm-delay-codes/
CAUSE_CODES = [
    ("C",  "ATC Capacity",                "AD Capacity (ATC)"),
    ("S",  "ATC Staffing",                "AD Staffing (ATC)"),
    ("I",  "Industrial Action (ATC)",     "AD Disruptions (ATC)"),
    ("T",  "Equipment (ATC)",             "AD Disruptions (ATC)"),
    ("G",  "Aerodrome Capacity",          "AD Capacity"),
    ("M",  "Military Activity",           "AD Capacity"),
    ("R",  "ATC Routeing",                "AD Capacity"),
    ("V",  "Environmental Issues",        "AD Capacity"),
    ("A",  "Accident/Incident",           "AD Disruptions"),
    ("E",  "Aerodrome Services",          "AD Disruptions"),
    ("N",  "Industrial Action (non-ATC)", "AD Disruptions"),
    ("NA", "Not regulated/Not specified", "AD Disruptions"),
    ("O",  "Other",                       "AD Disruptions"),
    ("P",  "Special Event",               "AD Events"),
    ("D",  "De-icing",                    "AD Weather"),
    ("W",  "Weather",                     "AD Weather"),
]


def read_source() -> pd.DataFrame:
    """
    Read the DATA sheet. The other eight sheets are dashboard pivots.

    Two false starts are worth recording here, because the obvious
    approaches both fail on a 96 MB workbook holding a million rows.

      pd.read_excel()            builds the entire cell tree in memory.
                                 Did not finish.
      openpyxl read_only -> list collecting a million Python lists and
                                 handing them to the DataFrame
                                 constructor is just as bad. Also did
                                 not finish.

    What works is streaming rows straight out to a flat CSV and letting
    pandas' C parser read that back. Flat memory, about two minutes.

    That CSV is kept as a cache next to the workbook. Re-parsing 96 MB of
    XML on every run is pure waste, and the extract is deterministic.
    Delete data/raw/apt_dly.csv to force a fresh read.
    """
    if CACHE.exists():
        print(f"using cached extract {CACHE.name} (delete it to re-read the workbook)")
        return _clean(pd.read_csv(CACHE, low_memory=False))

    if not SRC.exists():
        sys.exit(f"Source workbook not found at {SRC}\nSee data/README.md")

    import csv
    import openpyxl

    print(f"reading {SRC.name} (streaming, ~2 min) ...")
    wb = openpyxl.load_workbook(SRC, read_only=True, data_only=True)
    rows = wb["DATA"].iter_rows(values_only=True)
    header = [str(h).strip() for h in next(rows)]
    keep = [i for i, h in enumerate(header) if h and h not in ("None", "Pivot Label")]

    # Written to a partial file and renamed only on success, so an
    # interrupted run cannot leave a half-written cache behind.
    partial = CACHE.with_suffix(".partial")
    with partial.open("w", newline="", encoding="utf8") as fh:
        writer = csv.writer(fh)
        writer.writerow([header[i] for i in keep])
        for row in rows:
            if row[0] is None:
                continue
            out = [row[i] for i in keep]
            out[3] = str(out[3])[:10]          # FLT_DATE -> ISO date
            writer.writerow(["" if v is None else v for v in out])
    wb.close()
    partial.replace(CACHE)

    return _clean(pd.read_csv(CACHE, low_memory=False))


def _clean(df: pd.DataFrame) -> pd.DataFrame:
    df = df[df["APT_ICAO"].notna()].copy()

    # Empty cause cells mean no delay under that code, not missing data.
    for col in df.columns:
        if col.startswith(("DLY_APT_ARR", "FLT_ARR")):
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    df["YEAR"] = pd.to_numeric(df["YEAR"], errors="coerce").astype(int)
    df["MONTH_NUM"] = pd.to_numeric(df["MONTH_NUM"], errors="coerce").astype(int)
    return df


def build(df: pd.DataFrame) -> None:
    DB.unlink(missing_ok=True)
    con = sqlite3.connect(DB)
    con.executescript("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;")
    con.executescript(SCHEMA.read_text(encoding="utf8"))

    pd.DataFrame(CAUSE_CODES, columns=["code", "cause_name", "cause_group"]) \
        .to_sql("cause_code", con, if_exists="append", index=False)

    (df.groupby("APT_ICAO")
       .agg(name=("APT_NAME", "first"), state=("STATE_NAME", "first"))
       .reset_index().rename(columns={"APT_ICAO": "icao"})
       .to_sql("airport", con, if_exists="append", index=False))

    arrivals = df[["APT_ICAO", "FLT_DATE", "YEAR", "MONTH_NUM", "FLT_ARR_1",
                   "DLY_APT_ARR_1", "FLT_ARR_1_DLY", "FLT_ARR_1_DLY_15"]]
    arrivals.columns = ["icao", "flt_date", "yr", "mth", "arrivals",
                        "delay_min_total", "arr_delayed", "arr_delayed_15"]
    arrivals.to_sql("arrivals", con, if_exists="append", index=False, chunksize=200_000)

    # Wide to long, one code at a time, keeping only non-zero rows.
    # Melting all sixteen columns at once would build a 16.5m-row frame
    # in memory to then throw 99.6% of it away.
    parts = []
    for code, _, _ in CAUSE_CODES:
        col = f"DLY_APT_ARR_{code}_1"
        part = df.loc[df[col] > 0, ["APT_ICAO", "FLT_DATE", col]].copy()
        part.columns = ["icao", "flt_date", "delay_min"]
        part["code"] = code
        parts.append(part[["icao", "flt_date", "code", "delay_min"]])

    pd.concat(parts, ignore_index=True) \
        .to_sql("delay_by_cause", con, if_exists="append", index=False, chunksize=200_000)

    con.commit()
    return con


def report(con: sqlite3.Connection) -> None:
    cur = con.cursor()
    for table in ("airport", "cause_code", "arrivals", "delay_by_cause"):
        n = cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:<16}{n:>10,} rows")

    total, by_cause = cur.execute("""
        SELECT ROUND(SUM(a.delay_min_total)),
               (SELECT ROUND(SUM(d.delay_min))
                  FROM delay_by_cause d
                  JOIN arrivals x ON x.icao = d.icao AND x.flt_date = d.flt_date
                 WHERE x.yr = 2025)
          FROM arrivals a WHERE a.yr = 2025""").fetchone()

    print(f"\nintegrity check, 2025")
    print(f"  total column   {total:>14,.0f}")
    print(f"  sum of causes  {by_cause:>14,.0f}")
    print(f"  difference     {total - by_cause:>14,.0f}"
          f"   {'OK' if total == by_cause else 'MISMATCH, stop here'}")


if __name__ == "__main__":
    t0 = time.time()
    con = build(read_source())
    report(con)
    con.close()
    print(f"\nwrote {DB} in {time.time() - t0:.0f}s")
