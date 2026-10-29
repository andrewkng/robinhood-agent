#!/bin/bash
# Read-only swing-trade + options-income analysis via Antigravity CLI (agy),
# run by launchd Mon and Wed shortly after market open.
# Both reports go into swingtrade-reports/swingtrade-YYYY-MM-DD.md (date in America/New_York).
# Set FORCE=1 to bypass the weekday/time guards for manual testing.
set -euo pipefail

# Repo root = parent of this script, so the clone can live anywhere. Override with REPO=...
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
NVM_BINS=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -Vr | paste -sd: - || true)
# launchd starts jobs with a minimal PATH, so add the usual install locations.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:${NVM_BINS:+$NVM_BINS:}/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
AGY=${AGY:-$(command -v agy || echo "$HOME/.local/bin/agy")}
export AGY_READONLY_REPORT=1

DATE=$(TZ=America/New_York date +%F)
OUT_DIR="$REPO/swingtrade-reports"
OUT="$OUT_DIR/swingtrade-$DATE.md"
mkdir -p "$OUT_DIR/logs"

log() { echo "[$(date '+%F %T %Z')] $*"; }

has_swing=0
has_options=0
if [[ -s "$OUT" ]]; then
  grep -Eq '^#+[[:space:]]+Swing trade' "$OUT" && has_swing=1
  grep -Eq '^#+[[:space:]]+Options income' "$OUT" && has_options=1
fi

if (( has_swing && has_options )); then
  log "Both Swing trade and Options income reports already exist in $OUT — skipping."
  exit 0
fi

if [[ "${FORCE:-0}" != "1" ]]; then
  DOW=$(TZ=America/New_York date +%u)   # 1=Mon … 7=Sun
  HHMM=$(TZ=America/New_York date +%H%M)
  if (( DOW > 5 )); then
    log "Weekend in ET — skipping."
    exit 0
  fi
  if (( 10#$HHMM < 935 )); then
    log "Before 09:35 ET — skipping."
    exit 0
  fi
fi

SWING_PROMPT="Use the robinhood-copilot skill to run the swing screen on my holdings for today ($DATE). Analysis only: do not trade, review, or preview any orders, and do not write files or create artifacts. If the US stock market is closed today (holiday), say so in one line and stop. Output ONLY the final markdown report, starting with a '# Swing trade — $DATE' heading: Bottom line, trade plan table, What I passed on, What would cancel the idea, and how it fits with open positions. Timestamp the quotes. Only AFTER you have picked the trade, use search_web for that one recommended ticker only (never search other holdings; skip searching if the result is 'no trade'): news from the last 7 days and scheduled catalysts before the time stop (e.g. FDA dates, investor days, Fed/CPI). Prefer primary or credible sources (company IR/press releases, SEC, Reuters, Bloomberg, WSJ, CNBC). Add a 'News & catalysts' section citing each source with its date. News is context only: it can flag a risk but must not override the technical filters."

OPTIONS_PROMPT="Use the robinhood-copilot skill in Options income mode for today ($DATE): what covered calls AND cash-secured puts should I sell this week for premium without earnings risk? You must evaluate and include a recommendation for BOTH a covered call and a cash-secured put, following references/options-income.md exactly (expiration 25–45 days out and before the next earnings date, |delta| 0.15–0.25, IV > historical average [IV > 20D/30D HV and 1-Yr IV Percentile > 50%] for both calls and puts, ≥100 free shares per lot for calls, put collateral ≤ available buying power and ≤20% of account value on non-overconcentrated holdings, Roth first). Analysis only: do not trade, review, or preview any orders, and do not write files or create artifacts. If the US stock market is closed today (holiday), say so in one line and stop. Output ONLY the final markdown report, starting with a '# Options income — $DATE' heading: Bottom line, The trades (both Covered Call and Cash-Secured Put), Why, Events to note, Management, What to leave alone, Fallback. Timestamp the quotes. Only AFTER you have picked the trades, use search_web for the recommended ticker(s) only (never other holdings; skip if there is no trade) to find 1-Yr IV Percentile and big events before the expiration (confirmed earnings, ex-dividend, FDA dates, investor days, M&A, lawsuits, Fed/CPI), citing credible sources with dates under 'Events to note'. Events can change the expiration or strike, or rule a name out, but must not override the delta, IV vs. HV, earnings and coverage/collateral rules."

# Headless non-interactive print mode (-p).
# Combined with .agents/hooks.json (active when AGY_READONLY_REPORT=1), any mutating MCP call,
# file write/edit, URL fetch, or subagent invocation is hard-denied at PreToolUse.
run_agy() {
  "$AGY" -p "$1" \
    --mode auto \
    --sandbox \
    --dangerously-skip-permissions
}

# Retry a failed run once after a pause (e.g. rate limiting). The retry overwrites the
# failed attempt's output, so only the half that failed is rerun.
RETRY_DELAY=${RETRY_DELAY:-300}
run_with_retry() {
  local name=$1 prompt=$2 out=$3 rc=0
  run_agy "$prompt" > "$out" || rc=$?
  if (( rc != 0 )); then
    log "$name run exited $rc — retrying once in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
    rc=0
    run_agy "$prompt" > "$out" || rc=$?
    (( rc == 0 )) && log "$name retry succeeded" || log "$name retry exited $rc"
  fi
  return "$rc"
}

cd "$REPO"
swing_pid=""
opt_pid=""

if (( ! has_swing )); then
  log "Starting agy swing-trade analysis for $DATE"
  run_with_retry swing "$SWING_PROMPT" "$OUT.swing.tmp" & swing_pid=$!
else
  log "Swing trade report already exists in $OUT — skipping swing run."
fi

if (( ! has_options )); then
  log "Starting agy options-income analysis for $DATE"
  run_with_retry options "$OPTIONS_PROMPT" "$OUT.options.tmp" & opt_pid=$!
else
  log "Options income report already exists in $OUT — skipping options run."
fi

status=0
[[ -n "$swing_pid" ]] && { wait "$swing_pid" || status=$?; }
[[ -n "$opt_pid" ]]   && { wait "$opt_pid"   || status=$?; }

if (( status == 0 )); then
  if (( ! has_swing && ! has_options )); then
    { cat "$OUT.swing.tmp"; printf '\n\n---\n\n'; cat "$OUT.options.tmp"; } > "$OUT"
    log "Wrote $OUT"
  elif (( ! has_swing )); then
    { printf '\n\n---\n\n'; cat "$OUT.swing.tmp"; } >> "$OUT"
    log "Appended Swing trade report to $OUT"
  elif (( ! has_options )); then
    { printf '\n\n---\n\n'; cat "$OUT.options.tmp"; } >> "$OUT"
    log "Appended Options income report to $OUT"
  fi
  rm -f "$OUT.swing.tmp" "$OUT.options.tmp"
else
  {
    [[ -f "$OUT.swing.tmp" ]] && cat "$OUT.swing.tmp"
    [[ -f "$OUT.swing.tmp" && -f "$OUT.options.tmp" ]] && printf '\n\n---\n\n'
    [[ -f "$OUT.options.tmp" ]] && cat "$OUT.options.tmp"
  } > "$OUT_DIR/swingtrade-$DATE.error.md"
  rm -f "$OUT.swing.tmp" "$OUT.options.tmp"
  log "agy exited $status — see swingtrade-$DATE.error.md"
  exit "$status"
fi
