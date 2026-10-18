#!/bin/bash
# Read-only swing-trade analysis, run by launchd Mon and Wed shortly after market open.
# Writes swingtrade-reports/swingtrade-YYYY-MM-DD.md (date in America/New_York).
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

if [[ -e "$OUT" ]]; then
  log "Report already exists: $OUT — skipping."
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
ALLOWED="${MCP}get_accounts,${MCP}get_portfolio,${MCP}get_equity_positions,${MCP}get_option_positions,${MCP}get_crypto_positions,${MCP}get_equity_quotes,${MCP}get_crypto_quotes,${MCP}get_option_instruments,${MCP}get_option_quotes,${MCP}get_equity_fundamentals,${MCP}get_equity_analyst_ratings,${MCP}get_earnings_results,${MCP}get_equity_historicals,${MCP}get_equity_technical_indicators,Bash(python3:*),Bash(jq:*),Read,Skill,WebSearch"
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

PROMPT="/robinhood-copilot Run the swing screen on my holdings for today ($DATE). Analysis only: do not trade, review, or preview any orders. If the US stock market is closed today (holiday), say so in one line and stop. Output ONLY the final markdown report, starting with a '# Swing trade — $DATE' heading: Bottom line, trade plan table, What I passed on, What would cancel the idea, and how it fits with open positions. Timestamp the quotes. Only AFTER you have picked the trade, use WebSearch for that one recommended ticker only (never search other holdings; skip searching if the result is 'no trade'): news from the last 7 days and scheduled catalysts before the time stop (e.g. FDA dates, investor days, Fed/CPI). Prefer primary or credible sources (company IR/press releases, SEC, Reuters, Bloomberg, WSJ, CNBC). Add a 'News & catalysts' section citing each source with its date. News is context only: it can flag a risk but must not override the technical filters."

# dontAsk: any tool not in ALLOWED is refused outright instead of being auto-approved.
# --tools limits built-in tools to Read/Bash/Skill/WebSearch (no file writes, page fetches, or subagents).
cd "$REPO"
log "Starting swing-trade analysis for $DATE"
if "$CLAUDE" -p "$PROMPT" \
     --permission-mode dontAsk \
     --tools "Read,Bash,Skill,WebSearch" \
     --allowedTools "$ALLOWED" \
     --disallowedTools "$DENIED" > "$OUT.tmp"; then
  mv "$OUT.tmp" "$OUT"
  log "Wrote $OUT"
else
  status=$?
  mv "$OUT.tmp" "$OUT_DIR/swingtrade-$DATE.error.md"
  log "claude exited $status — see swingtrade-$DATE.error.md"
  exit "$status"
fi
