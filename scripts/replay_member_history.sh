#!/usr/bin/env bash
# SCD-2 backfill: rebuild the member history as if the snapshot had run on Jan 1 of each year.
# A snapshot only moves FORWARD in time, so this starts from an empty history (it drops
# snapshots.member_history first) and replays the years in order; the next `dbt build`
# then adds today's version. Run from the project root after the 834 is loaded and built.
#   ./scripts/replay_member_history.sh            # 2016 .. last year
#   ./scripts/replay_member_history.sh 2018 2024  # custom range
set -euo pipefail
FIRST="${1:-2016}"
LAST="${2:-$(( $(date +%Y) - 1 ))}"
export PGHOST="${PG_HOST:-localhost}" PGPORT="${PG_PORT:-5432}" PGUSER="${PG_USER:-$USER}" PGPASSWORD="${PG_PASSWORD:-}" PGDATABASE="${PG_DB:-coastal_care}"
psql -qc "DROP TABLE IF EXISTS snapshots.member_history"
for year in $(seq "$FIRST" "$LAST"); do
    dbt snapshot --project-dir dbt --profiles-dir dbt --vars "{as_of_date: '${year}-01-01'}" 2>&1 | grep -E "ERROR|Done" | sed "s/^/${year}  /"
done
psql -P pager=off -c "select count(distinct dbt_scd_id) as versions, count(distinct member_key) as members,
                             round(count(*)::numeric / count(distinct member_key), 2) as versions_per_member
                      from snapshots.member_history"
