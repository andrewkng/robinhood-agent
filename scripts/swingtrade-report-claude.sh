#!/bin/bash
# Read-only swing-trade + options-income analysis, run by launchd Mon and Wed shortly after market open.
# Both reports go into swingtrade-reports/swingtrade-YYYY-MM-DD.md (date in America/New_York).
# Set FORCE=1 to bypass the weekday/time guards for manual testing.
set -euo pipefail

REPO=/Users/yannipeng/git-projects/robinhood-agent
CLAUDE=/opt/homebrew/bin/claude
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

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

MCP=mcp__robinhood-trading__
ALLOWED="${MCP}get_accounts,${MCP}get_portfolio,${MCP}get_equity_positions,${MCP}get_option_positions,${MCP}get_crypto_positions,${MCP}get_equity_quotes,${MCP}get_crypto_quotes,${MCP}get_option_chains,${MCP}get_option_instruments,${MCP}get_option_quotes,${MCP}get_equity_fundamentals,${MCP}get_equity_analyst_ratings,${MCP}get_earnings_results,${MCP}get_equity_historicals,${MCP}get_equity_technical_indicators,${MCP}preview_scan,${MCP}run_scan,${MCP}get_scans,Bash(python3:*),Bash(jq:*),Read,Skill,WebSearch"
# Deny every tool that can trade or change the account. Deny rules win over any
# allow rule or permission mode, including the user's global "auto" defaultMode.
DENIED=$(printf "${MCP}%s," \
  place_equity_order place_option_order place_crypto_order place_advanced_order \
  review_equity_order review_option_order review_advanced_order preview_crypto_order \
  cancel_equity_order cancel_option_order cancel_crypto_order cancel_advanced_order \
  cancel_option_exercise exercise_option decline_trade_approval \
  create_alert update_alert delete_alert mark_alerts_read \
  create_watchlist update_watchlist add_to_watchlist remove_from_watchlist \
  add_option_to_watchlist remove_option_from_watchlist follow_watchlist unfollow_watchlist \
  create_scan update_scan_config update_scan_filters \
  add_legend_indicator update_legend_indicator remove_legend_indicator set_legend_chart_settings)
DENIED="${DENIED%,},Write,Edit,NotebookEdit,WebFetch,Agent"

SWING_PROMPT="/robinhood-copilot Run the swing screen on my holdings for today ($DATE). Analysis only: do not trade, review, or preview any orders. If the US stock market is closed today (holiday), say so in one line and stop. Output ONLY the final markdown report, starting with a '# Swing trade — $DATE' heading: Bottom line, trade plan table, What I passed on, What would cancel the idea, and how it fits with open positions. Timestamp the quotes. Only AFTER you have picked the trade, use WebSearch for that one recommended ticker only (never search other holdings; skip searching if the result is 'no trade'): news from the last 7 days and scheduled catalysts before the time stop (e.g. FDA dates, investor days, Fed/CPI). Prefer primary or credible sources (company IR/press releases, SEC, Reuters, Bloomberg, WSJ, CNBC). Add a 'News & catalysts' section citing each source with its date. News is context only: it can flag a risk but must not override the technical filters."

OPTIONS_PROMPT="/robinhood-copilot Options income mode for today ($DATE): what calls should I sell this week for premium without earnings risk? Follow references/options-income.md exactly (expiration 25–45 days out and before the next earnings date, delta 0.15–0.25, ≥100 free shares per lot, Roth first). Analysis only: do not trade, review, or preview any orders. If the US stock market is closed today (holiday), say so in one line and stop. Output ONLY the final markdown report, starting with a '# Options income — $DATE' heading: Bottom line, The trade, Why, Events to note, Management, What to leave alone, Fallback. Timestamp the quotes. Only AFTER you have picked the trade, use WebSearch for the recommended ticker(s) only (never other holdings; skip if there is no trade) to find big events before the expiration (confirmed earnings, ex-dividend, FDA dates, investor days, M&A, lawsuits, Fed/CPI), citing credible sources with dates under 'Events to note'. Events can change the expiration or strike, or rule a name out, but must not override the delta, earnings and coverage rules."

# dontAsk: any tool not in ALLOWED is refused outright instead of being auto-approved.
# --tools limits built-in tools to Read/Bash/Skill/WebSearch (no file writes, page fetches, or subagents).
run_claude() {
  "$CLAUDE" -p "$1" \
    --permission-mode dontAsk \
    --tools "Read,Bash,Skill,WebSearch" \
    --allowedTools "$ALLOWED" \
    --disallowedTools "$DENIED"
}

# Retry a failed run once after a pause (e.g. rate limiting). The retry overwrites the
# failed attempt's output, so only the half that failed is rerun.
RETRY_DELAY=${RETRY_DELAY:-300}
run_with_retry() {
  local name=$1 prompt=$2 out=$3 rc=0
  run_claude "$prompt" > "$out" || rc=$?
  if (( rc != 0 )); then
    log "$name run exited $rc — retrying once in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
    rc=0
    run_claude "$prompt" > "$out" || rc=$?
    (( rc == 0 )) && log "$name retry succeeded" || log "$name retry exited $rc"
  fi
  return "$rc"
}

cd "$REPO"
swing_pid=""
opt_pid=""

if (( ! has_swing )); then
  log "Starting claude swing-trade analysis for $DATE"
  run_with_retry swing "$SWING_PROMPT" "$OUT.swing.tmp" & swing_pid=$!
else
  log "Swing trade report already exists in $OUT — skipping swing run."
fi

if (( ! has_options )); then
  log "Starting claude options-income analysis for $DATE"
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
  log "claude exited $status — see swingtrade-$DATE.error.md"
  exit "$status"
fi
