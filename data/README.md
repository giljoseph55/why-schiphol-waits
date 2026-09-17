# Source data

The analysis runs on one file, which is not committed here because it is about 96 MB.

## Get it

1. Go to <https://ansperformance.eu/data/>
2. Under **Operations at Airports**, find *Airport arrival ATFM delays (no post ops adjustments)*
3. Download the Excel file: `Airport_Arrival_ATFM_Delay.xlsx`
4. Put it in this folder: `data/raw/Airport_Arrival_ATFM_Delay.xlsx`

Direct link at the time of writing:
<https://www.eurocontrol.int/performance/data/download/xls/Airport_Arrival_ATFM_Delay.xlsx>

## Then

```bash
python sql/load.py
```

This reads the `DATA` sheet, normalises the 32-column wide format into four tables and
writes `sql/atfm.db`. It takes about thirty seconds and prints the integrity check.

## What is in the file

Nine sheets. Only `DATA` is used. The others are pivot views built for the EUROCONTROL
dashboard. `DATA` holds one row per airport per day:

| Column | Meaning |
|---|---|
| `APT_ICAO`, `APT_NAME`, `STATE_NAME` | the airport |
| `FLT_DATE`, `YEAR`, `MONTH_NUM` | the day |
| `FLT_ARR_1` | IFR arrivals |
| `DLY_APT_ARR_1` | total arrival ATFM delay, minutes |
| `DLY_APT_ARR_<code>_1` | the same minutes split across 16 cause codes |
| `FLT_ARR_1_DLY`, `FLT_ARR_1_DLY_15` | arrivals delayed, and delayed over 15 minutes |

Cause codes are defined by EUROCONTROL at
<https://ansperformance.eu/definition/atfm-delay-codes/> and are loaded into the
`cause_code` table by `load.py`.

Retrieved 16 September 2026. The dataset is updated monthly, so re-running against a newer
download will move the figures.

## Cache

The first run writes `data/raw/apt_dly.csv`, a flat extract of the `DATA` sheet, and reuses
it afterwards. Re-parsing 96 MB of XML on every run is waste, and the extract is
deterministic. Delete that file to force a fresh read of the workbook.

Both files are in `.gitignore`.
