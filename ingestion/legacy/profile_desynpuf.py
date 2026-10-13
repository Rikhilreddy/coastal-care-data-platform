"""
Profile the CMS DE-SynPUF legacy source files.

Reads every CSV in data/source/desynpuf as text (so leading zeros in IDs and
codes are preserved), computes file-level and column-level statistics, checks
candidate business keys for uniqueness, validates code formats, and writes a
Markdown report to docs/profiling/desynpuf_profile.md.

Run from the project root:
    python ingestion/legacy/profile_desynpuf.py
"""
from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path

import pandas as pd

SOURCE_DIR = Path("data/source/desynpuf")
REPORT_PATH = Path("docs/profiling/desynpuf_profile.md")

# Candidate business keys to test for uniqueness (only tested if all columns exist).
CANDIDATE_KEYS = [
    ["DESYNPUF_ID"],
    ["CLM_ID"],
    ["CLM_ID", "SEGMENT"],
    ["DESYNPUF_ID", "CLM_ID", "SEGMENT"],
]

DATE_RE = r"^(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$"
NUMERIC_RE = r"^-?\d+(\.\d+)?$"
# ICD-9-CM diagnosis: 3-5 digits, V codes (V + 2-4 digits), E codes (E + 3-4 digits)
ICD9_DX_RE = r"^(\d{3,5}|V\d{2,4}|E\d{3,4})$"
# ICD-9-CM procedure: 2-4 digits
ICD9_PX_RE = r"^\d{2,4}$"
# HCPCS: 5 characters, Level I (CPT, numeric) or Level II (letter + 4 digits)
HCPCS_RE = r"^[A-Z0-9]\d{3}[A-Z0-9]$"


def infer_type(s: pd.Series) -> str:
    sample = s.dropna().head(5000)
    if sample.empty:
        return "empty"
    if sample.str.match(DATE_RE).mean() > 0.95:
        return "date"
    if sample.str.match(NUMERIC_RE).mean() > 0.95:
        return "numeric"
    return "text/code"


def code_rule(column: str) -> tuple[str, str] | None:
    """Return (label, regex) for columns that hold standard healthcare codes."""
    if "ICD9_DGNS" in column:
        return "ICD-9 dx", ICD9_DX_RE
    if "ICD9_PRCDR" in column:
        return "ICD-9 px", ICD9_PX_RE
    if column.startswith("HCPCS_CD"):
        return "HCPCS", HCPCS_RE
    return None


def md(value) -> str:
    """Make a value safe for a Markdown table cell."""
    return str(value).replace("|", "\\|").replace("\n", " ")


def profile_column(name: str, s: pd.Series) -> dict:
    total = len(s)
    non_null = int(s.notna().sum())
    kind = infer_type(s)
    row = {
        "column": name,
        "type": kind,
        "null_pct": round(100 * (total - non_null) / total, 2) if total else 0,
        "distinct": int(s.nunique(dropna=True)),
        "min": "",
        "max": "",
        "notes": [],
    }

    if kind == "date":
        parsed = pd.to_datetime(s, format="%Y%m%d", errors="coerce")
        invalid = int((s.notna() & parsed.isna()).sum())
        if parsed.notna().any():
            row["min"] = parsed.min().strftime("%Y-%m-%d")
            row["max"] = parsed.max().strftime("%Y-%m-%d")
        if invalid:
            row["notes"].append(f"{invalid:,} unparseable dates")
    elif kind == "numeric":
        nums = pd.to_numeric(s, errors="coerce")
        row["min"] = nums.min()
        row["max"] = nums.max()
        negatives = int((nums < 0).sum())
        if negatives:
            row["notes"].append(f"{negatives:,} negative values")

    rule = code_rule(name)
    if rule and non_null:
        label, pattern = rule
        values = s.dropna()
        bad = values[~values.str.match(pattern)]
        pct_valid = round(100 * (1 - len(bad) / len(values)), 2)
        note = f"{label} format valid: {pct_valid}%"
        if len(bad):
            examples = ", ".join(bad.unique()[:3])
            note += f" (e.g. bad: {examples})"
        row["notes"].append(note)

    top = s.value_counts(dropna=True).head(3)
    row["top_values"] = ", ".join(f"{v} ({c:,})" for v, c in top.items())
    return row


def profile_file(path: Path) -> list[str]:
    print(f"Profiling {path.name} ...")
    df = pd.read_csv(path, dtype=str, keep_default_na=True)
    lines = [f"## {path.name}", ""]
    lines.append(f"- **Rows:** {len(df):,}")
    lines.append(f"- **Columns:** {df.shape[1]}")
    lines.append(f"- **Fully duplicated rows:** {int(df.duplicated().sum()):,}")

    lines.append("- **Candidate key checks:**")
    tested = False
    for key in CANDIDATE_KEYS:
        if all(col in df.columns for col in key):
            tested = True
            dupes = int(df.duplicated(subset=key).sum())
            nulls = int(df[key].isna().any(axis=1).sum())
            verdict = "UNIQUE" if dupes == 0 and nulls == 0 else "not unique"
            lines.append(
                f"  - `{' + '.join(key)}`: {verdict} "
                f"({dupes:,} duplicates, {nulls:,} rows with null key)"
            )
    if not tested:
        lines.append("  - none of the candidate keys exist in this file")

    lines += [
        "",
        "| Column | Type | Null % | Distinct | Min | Max | Top values | Notes |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for name in df.columns:
        r = profile_column(name, df[name])
        lines.append(
            f"| {md(r['column'])} | {r['type']} | {r['null_pct']} | {r['distinct']:,} "
            f"| {md(r['min'])} | {md(r['max'])} | {md(r['top_values'])} "
            f"| {md('; '.join(r['notes']))} |"
        )
    lines.append("")
    print(f"  {len(df):,} rows, {df.shape[1]} columns")
    return lines


def main() -> None:
    files = sorted(SOURCE_DIR.glob("*.csv"))
    if not files:
        raise SystemExit(f"No CSV files found in {SOURCE_DIR}. Run from the project root.")

    report = [
        "# DE-SynPUF Legacy Source Profile",
        "",
        f"Generated {datetime.now():%Y-%m-%d %H:%M} by `ingestion/legacy/profile_desynpuf.py`.",
        "All columns were read as text to preserve leading zeros in IDs and codes.",
        "",
    ]
    for path in files:
        report += profile_file(path)

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text("\n".join(report), encoding="utf-8")
    print(f"\nReport written to {REPORT_PATH}")


if __name__ == "__main__":
    main()
