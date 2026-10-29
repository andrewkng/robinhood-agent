#!/bin/bash
# Install (or remove) the Mon/Wed swing-trade launchd job for this clone.
# Fills the plist template with this repo's path and 9:40 AM ET converted to the Mac's local time.
#
#   scripts/install-launchd.sh claude            # install + load
#   scripts/install-launchd.sh agy
#   scripts/install-launchd.sh claude uninstall  # unload + remove
set -euo pipefail

AGENT=${1:-}
ACTION=${2:-install}
if [[ "$AGENT" != "claude" && "$AGENT" != "agy" ]]; then
  echo "usage: $0 <claude|agy> [install|uninstall]" >&2
  exit 1
fi

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LABEL="com.robinhood-agent.swingtrade-$AGENT"
TEMPLATE="$REPO/scripts/$LABEL.plist"
TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# Unload any existing copy first so a reinstall picks up changes.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "$ACTION" == "uninstall" ]]; then
  rm -f "$TARGET"
  echo "Removed $LABEL"
  exit 0
fi

# 9:40 AM ET (10 min after the open) expressed in local time, e.g. 06:40 on a Pacific Mac.
RUN_ET=${RUN_ET:-09:40}
EPOCH=$(TZ=America/New_York date -j -f "%Y-%m-%d %H:%M" "$(date +%F) $RUN_ET" +%s)
HOUR=$(date -r "$EPOCH" +%-H)
MINUTE=$(date -r "$EPOCH" +%-M)

mkdir -p "$HOME/Library/LaunchAgents" "$REPO/swingtrade-reports/logs"
sed -e "s|__REPO__|$REPO|g" -e "s|__HOUR__|$HOUR|g" -e "s|__MINUTE__|$MINUTE|g" "$TEMPLATE" > "$TARGET"
plutil -lint "$TARGET" >/dev/null
launchctl bootstrap "$DOMAIN" "$TARGET"

printf 'Installed %s: Mon & Wed at %02d:%02d local (%s ET)\n' "$LABEL" "$HOUR" "$MINUTE" "$RUN_ET"
echo "Test now: launchctl kickstart -k $DOMAIN/$LABEL"
