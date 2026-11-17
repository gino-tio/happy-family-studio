#!/usr/bin/env bash
# Applies new supabase/migrations/studio_*.sql files to the shared Hub Supabase project, in name
# order, then runs supabase/checks.sql. Run by .github/workflows/migrations.yml after a merge to main.
#
# A file counts as applied when core.migrations has (app 'studio', file name without .sql). Each
# file runs in one transaction together with that row, so a failed file changes nothing and the
# job stops there. Needs SUPABASE_ACCESS_TOKEN (a Supabase personal access token for the Hub
# project). DRY_RUN=1 only lists what would run.
set -euo pipefail

APP=studio
REF=${SUPABASE_PROJECT_REF:-ddzwhmcxeokkwzmhglft}
API="https://api.supabase.com/v1/projects/$REF/database/query"
cd "$(dirname "$0")/.."

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is not set}"

# query SQL [read_only] -> prints the JSON result; exits non-zero on an API or SQL error.
query() {
  local body code out
  body=$(jq -n --arg q "$1" --argjson ro "${2:-false}" '{query: $q, read_only: $ro}')
  out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X POST "$API" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H 'Content-Type: application/json' \
    --data-binary "$body")
  if [[ $code != 2* ]]; then
    echo "Supabase answered HTTP $code:" >&2
    jq -r '.message // .' "$out" >&2 || cat "$out" >&2
    rm -f "$out"
    return 1
  fi
  cat "$out"
  rm -f "$out"
}

applied=$(query "select name from core.migrations where app_id = '$APP'" true | jq -r '.[].name')

pending=()
for f in supabase/migrations/${APP}_*.sql; do
  name=$(basename "$f" .sql)
  [[ $name =~ ^${APP}_[0-9]{4}_[a-z0-9_]+$ ]] || { echo "Bad migration name: $f" >&2; exit 1; }
  grep -qxF "$name" <<<"$applied" || pending+=("$f")
done

if ((${#pending[@]} == 0)); then
  echo "Nothing to apply: every ${APP}_* migration is in core.migrations."
else
  for f in "${pending[@]}"; do
    name=$(basename "$f" .sql)
    if [[ ${DRY_RUN:-} == 1 ]]; then echo "Would apply $name"; continue; fi
    echo "Applying $name"
    sql=$(printf 'begin;\n%s\n;\ninsert into core.migrations (app_id, name) values (%s, %s) on conflict do nothing;\ncommit;\n' \
      "$(cat "$f")" "'$APP'" "'$name'")
    query "$sql" >/dev/null
    echo "Applied $name"
  done
fi

problems=$(query "$(cat supabase/checks.sql)" true)
if [[ $(jq 'length' <<<"$problems") != 0 ]]; then
  echo "Shared DB checks found problems:" >&2
  jq -r '.[] | "  \(.problem): \(.object)"' <<<"$problems" >&2
  exit 1
fi
echo "Shared DB checks: clean."
