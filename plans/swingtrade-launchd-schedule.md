# Swing-trade analysis via launchd (Mon & Wed)

## Context
You want a swing-trade analysis of your Robinhood portfolio to run on its own twice a week, on Monday and Wednesday, a few minutes after the market opens. Each report should be saved as `swingtrade-{date}.md` in a dedicated folder in this repo. The repo already has the analysis logic: the `robinhood-copilot` skill in swing-screen mode (`.claude/skills/robinhood-copilot/references/swing-screen.md`). It also has a read-only headless `claude -p` pattern (README → "Headless (scheduled or CI) run, read-only"). The `robinhood-trading` MCP is connected at user scope (`claude mcp list` → ✔ Connected), so a headless run can reuse it.

**Why launchd and not cron:** cron skips a job if the Mac is asleep at the scheduled time. launchd's `StartCalendarInterval` runs a missed job as soon as the Mac wakes, and coalesces several missed runs into one. Neither runs while the Mac is fully powered off.

Timing: the market opens at 9:30 ET, which is 6:30 AM in your local time (PDT). launchd uses local time, and ET and PT both observe US DST, so **6:40 AM local, Monday and Wednesday** stays correct all year.

## Files to create

1. **`swingtrade-reports/`**: the output folder, with a `.gitkeep`. Add `swingtrade-reports/*.md` and `swingtrade-reports/logs/` to `.gitignore`, because the reports contain real holdings. The repo already gitignores portfolio data, e.g. `.claude/skills/robinhood-copilot-workspace/`.

2. **`scripts/swingtrade-report.sh`**: the job entrypoint (`chmod +x`).
   - `set -euo pipefail`. Use absolute paths: `REPO=/Users/yannipeng/git-projects/robinhood-agent` and `CLAUDE=/opt/homebrew/bin/claude`. Export a `PATH` that includes `/opt/homebrew/bin`, because launchd's environment is minimal.
   - `DATE=$(TZ=America/New_York date +%F)` gives the trading date. `OUT=$REPO/swingtrade-reports/swingtrade-$DATE.md`.
   - **Guards**:
     - Exit if `$OUT` already exists. This makes the job idempotent on wake-up re-runs and manual runs.
     - Exit if the ET weekday is Sat or Sun. This covers a late wake-up that lands on a weekend.
     - Exit if the ET time is before 09:35, as a safety check.
   - `cd "$REPO"` so that CLAUDE.md and `.claude/skills` load.
   - Run `"$CLAUDE" -p "<prompt>" --allowedTools "<read-only list>" --disallowedTools "<place_*, cancel_*, exercise_option, decline_trade_approval, review_*, preview_crypto_order>" > "$OUT.tmp"`. The report goes to stdout and the script redirects it, so the model never needs Write permission. On success, `mv "$OUT.tmp" "$OUT"`. On failure, rename the tmp file to `swingtrade-$DATE.error.md`.
   - **Read-only enforcement**, verified headless:
     - `--permission-mode dontAsk`: any tool that isn't on the allow list is refused. This overrides the global `defaultMode: "auto"` in `~/.claude/settings.json`, which would otherwise auto-approve tools.
     - `--tools "Read,Bash,Skill,WebSearch"`: no file writes, no page fetches (`WebFetch`) and no subagents.
     - `--disallowedTools`: every Robinhood tool that trades or changes the account (`place_*`, `review_*`, `preview_crypto_order`, `cancel_*`, `exercise_option`, `decline_trade_approval`, plus alert, watchlist, scan and Legend writes) and `Write`/`Edit`/`WebFetch`/`Agent`. Denied tools are removed from the session entirely, even under `bypassPermissions`.
   - **Prompt:** "/robinhood-copilot Run the swing screen on my holdings for today ($DATE). Analysis only. Do not trade or review orders. If the market is closed today (holiday), say so in one line and stop. Output only the final markdown report: Bottom line, trade plan table, What I passed on, What would cancel the idea, fit with open positions. Timestamp the quotes. Then WebSearch only the one recommended ticker (skip if no trade): last-7-day news and scheduled catalysts before the time stop, credible sources only, cited in a News & catalysts section. News is context, not an override of the filters."
   - **Second run, options income:** after the swing run, the script runs `claude -p` again with the same flags and an options-income prompt: "what calls should I sell", premium without earnings risk, following `references/options-income.md` (25–45 days to expiration and before earnings, delta 0.15–0.25, ≤50% coverage, Roth first), under a `# Options income — $DATE` heading. After picking the trade, it WebSearches only the recommended ticker(s) for big events before expiration and lists them under 'Events to note'. Both outputs are written to the same `$OUT.tmp`, separated by `---`. If either run fails, the file becomes `swingtrade-$DATE.error.md`.
   - **Allowed tools**, taken from the skill's snapshot and swing-screen steps: `get_accounts, get_portfolio, get_equity_positions, get_option_positions, get_crypto_positions, get_equity_quotes, get_crypto_quotes, get_option_instruments, get_option_quotes, get_option_chains, get_equity_fundamentals, get_equity_analyst_ratings, get_earnings_results, get_equity_historicals, get_equity_technical_indicators, Bash(python3:*), Bash(jq:*), Read, Skill, WebSearch`. All MCP names are prefixed `mcp__robinhood-trading__`.

3. **`scripts/com.robinhood-agent.swingtrade.plist`**: a launchd agent checked into the repo, so the schedule is versioned.
   - `Label` = `com.robinhood-agent.swingtrade`.
   - `ProgramArguments` = `/bin/bash`, `<repo>/scripts/swingtrade-report.sh`.
   - `StartCalendarInterval` = an array of 2 dicts: `Weekday` 1 (Mon) and 3 (Wed), `Hour` 6, `Minute` 40.
   - `StandardOutPath`/`StandardErrorPath` = `<repo>/swingtrade-reports/logs/launchd.log`.
   - `WorkingDirectory` = repo.
   - Registration is covered in the "Registering the launchd job" section below.

4. **README.md**: a short "Swing-trade report, Mon & Wed (launchd)" subsection under "Configuration, permissions, and headless runs". It covers the schedule, the output path and naming, install/uninstall, and the caveats below.

## Registering the launchd job
The job is a per-user **LaunchAgent**. It runs in your login session (`gui/<uid>`), as you, with your Claude Code login. It only runs while you are logged in. A Mac that is asleep but logged in counts, and a run missed during sleep starts on wake.

1. **Link the plist into `~/Library/LaunchAgents/`.** launchd reads this folder at every login. A symlink keeps the version in git as the one launchd uses.
   ```bash
   ln -sf /Users/yannipeng/git-projects/robinhood-agent/scripts/com.robinhood-agent.swingtrade.plist ~/Library/LaunchAgents/
   ```
2. **Load it into the current session**, so you don't have to log out and back in:
   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.robinhood-agent.swingtrade.plist
   ```
3. **Reload after any plist edit**, such as a schedule change. Edits to `swingtrade-report.sh` need no reload.
   ```bash
   launchctl bootout   gui/$(id -u)/com.robinhood-agent.swingtrade
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.robinhood-agent.swingtrade.plist
   ```
4. **Inspect / run now / remove:**
   ```bash
   launchctl print     gui/$(id -u)/com.robinhood-agent.swingtrade      # schedule, state, last exit code
   launchctl kickstart -k gui/$(id -u)/com.robinhood-agent.swingtrade   # trigger a run immediately
   launchctl bootout   gui/$(id -u)/com.robinhood-agent.swingtrade && rm ~/Library/LaunchAgents/com.robinhood-agent.swingtrade.plist
   ```

## Caveats to note in the README
- Runs missed while the Mac is asleep happen on wake. A Mac that is powered off misses the run. Optionally run `sudo pmset repeat wakeorpoweron MW 06:35:00` so the run happens on time instead of whenever you open the lid.
- A late wake-up still analyzes with live quotes at that moment, and the report timestamps them.
- Market holidays are handled by the prompt, which writes a one-line "market closed" report. The script doesn't keep a holiday calendar.
- `claude -p` uses your existing Claude Code login (keychain). If it fails with an auth error, run `claude` once interactively.

## Verification
1. Run `scripts/swingtrade-report.sh` manually. Confirm that `swingtrade-reports/swingtrade-<today ET>.md` is created with the swing-screen sections, and that the log shows no `place_*`/`review_*` calls.
2. Run it again and confirm it skips because the file exists.
3. Test it under launchd: delete today's file, then run `launchctl kickstart -k gui/$(id -u)/com.robinhood-agent.swingtrade`. Check that the file and `logs/launchd.log` appear. This confirms that PATH and auth work in launchd's environment.
4. Run `launchctl print gui/$(id -u)/com.robinhood-agent.swingtrade` and confirm the calendar triggers. Check the output after the next Monday or Wednesday open.
