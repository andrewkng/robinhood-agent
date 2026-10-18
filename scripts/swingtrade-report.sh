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
ALLOWED="${MCP}get_accounts,${MCP}get_portfolio,${MCP}get_equity_positions,${MCP}get_option_positions,${MCP}get_crypto_positions,${MCP}get_equity_quotes,${MCP}get_crypto_quotes,${MCP}get_option_instruments,${MCP}get_option_quotes,${MCP}get_equity_fundamentals,${MCP}get_equity_analyst_ratings,${MCP}get_earnings_results,${MCP}get_equity_historicals,${MCP}get_equity_technical_indicators,Bash(python3:*),Bash(jq:*),Read,Skill"
DENIED="${MCP}place_equity_order,${MCP}place_option_order,${MCP}place_crypto_order,${MCP}place_advanced_order,${MCP}review_equity_order,${MCP}review_option_order,${MCP}review_advanced_order,${MCP}preview_crypto_order,${MCP}cancel_equity_order,${MCP}cancel_option_order,${MCP}cancel_crypto_order,${MCP}cancel_advanced_order,${MCP}cancel_option_exercise,${MCP}exercise_option,${MCP}decline_trade_approval"

PROMPT="/robinhood-copilot Run the swing screen on my holdings for today ($DATE). Analysis only: do not trade, review, or preview any orders. If the US stock market is closed today (holiday), say so in one line and stop. Output ONLY the final markdown report, starting with a '# Swing trade — $DATE' heading: Bottom line, trade plan table, What I passed on, What would cancel the idea, and how it fits with open positions. Timestamp the quotes."

cd "$REPO"
log "Starting swing-trade analysis for $DATE"
if "$CLAUDE" -p "$PROMPT" --allowedTools "$ALLOWED" --disallowedTools "$DENIED" > "$OUT.tmp"; then
  mv "$OUT.tmp" "$OUT"
  log "Wrote $OUT"
else
  status=$?
  mv "$OUT.tmp" "$OUT_DIR/swingtrade-$DATE.error.md"
  log "claude exited $status — see swingtrade-$DATE.error.md"
  exit "$status"
fi
