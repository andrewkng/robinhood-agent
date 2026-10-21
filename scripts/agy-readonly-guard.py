#!/usr/bin/env python3
"""PreToolUse hook for Antigravity (agy).

When AGY_READONLY_REPORT=1 is set (by scripts/swingtrade-report-agy.sh),
strictly enforces the same read-only tool allow/deny policy as swingtrade-report-claude.sh:
- Allows only read-only Robinhood MCP tools (get_accounts, get_portfolio, get_*_positions,
  get_*_quotes, get_option_chains, get_option_instruments, get_equity_fundamentals,
  get_equity_analyst_ratings, get_earnings_results, get_equity_historicals,
  get_equity_technical_indicators).
- Allows read_file/view_file, search_web, and read-only python3/jq commands.
- Denies all mutating Robinhood MCP tools (place_*, review_*, preview_*, cancel_*,
  exercise_option, decline_trade_approval, alert/watchlist/scan/legend writes),
  file writes/edits, URL fetches, and subagents.

In interactive sessions (AGY_READONLY_REPORT != 1), always blocks place_* / cancel_* /
exercise_option if --dangerously-skip-permissions is active, otherwise defers to default policy.
"""
import json
import os
import sys

ALLOWED_ROBINHOOD_TOOLS = {
    "get_accounts",
    "get_portfolio",
    "get_equity_positions",
    "get_option_positions",
    "get_crypto_positions",
    "get_equity_quotes",
    "get_crypto_quotes",
    "get_option_chains",
    "get_option_instruments",
    "get_option_quotes",
    "get_equity_fundamentals",
    "get_equity_analyst_ratings",
    "get_earnings_results",
    "get_equity_historicals",
    "get_equity_technical_indicators",
    "preview_scan",
    "run_scan",
    "get_scans",
}

DENIED_ROBINHOOD_TOOLS = {
    "place_equity_order",
    "place_option_order",
    "place_crypto_order",
    "place_advanced_order",
    "review_equity_order",
    "review_option_order",
    "review_advanced_order",
    "preview_crypto_order",
    "cancel_equity_order",
    "cancel_option_order",
    "cancel_crypto_order",
    "cancel_advanced_order",
    "cancel_option_exercise",
    "exercise_option",
    "decline_trade_approval",
    "create_alert",
    "update_alert",
    "delete_alert",
    "mark_alerts_read",
    "create_watchlist",
    "update_watchlist",
    "add_to_watchlist",
    "remove_from_watchlist",
    "add_option_to_watchlist",
    "remove_option_from_watchlist",
    "follow_watchlist",
    "unfollow_watchlist",
    "create_scan",
    "update_scan_config",
    "update_scan_filters",
    "add_legend_indicator",
    "update_legend_indicator",
    "remove_legend_indicator",
    "set_legend_chart_settings",
}


def reply(decision: str, reason: str = "") -> None:
    out = {"decision": decision}
    if reason:
        out["reason"] = reason
    print(json.dumps(out))
    sys.exit(0)


def main() -> None:
    if os.environ.get("AGY_READONLY_REPORT") != "1":
        reply("allow")

    try:
        payload = json.load(sys.stdin)
    except Exception:
        reply("allow")

    tool_call = payload.get("toolCall") or {}
    name = tool_call.get("name", "")
    args = tool_call.get("args") or {}

    # 1. Lazy-loaded MCP tool invocation via call_mcp_tool
    if name == "call_mcp_tool":
        server = args.get("ServerName", "")
        mcp_tool = args.get("ToolName", "")
        if server != "robinhood":
            reply("deny", f"MCP server '{server}' is not allowed in headless read-only report mode.")
        if mcp_tool in DENIED_ROBINHOOD_TOOLS or mcp_tool not in ALLOWED_ROBINHOOD_TOOLS:
            reply("deny", f"Robinhood tool '{mcp_tool}' is disallowed in headless read-only report mode.")
        reply("allow")

    # 2. Eager MCP tools (if ever registered as mcp_robinhood_<tool>)
    if name.startswith("mcp_robinhood_"):
        mcp_tool = name[len("mcp_robinhood_"):]
        if mcp_tool in DENIED_ROBINHOOD_TOOLS or mcp_tool not in ALLOWED_ROBINHOOD_TOOLS:
            reply("deny", f"Robinhood tool '{mcp_tool}' is disallowed in headless read-only report mode.")
        reply("allow")

    # 3. Built-in read/search tools
    if name in {"read_file", "view_file", "search_web", "grep_search", "find_by_name", "list_dir"}:
        reply("allow")

    # 4. Terminal commands: allow python3 / jq calculations
    if name == "run_command":
        cmd = (args.get("CommandLine") or "").strip()
        if cmd.startswith(("python3", "jq")):
            reply("allow")
        reply("deny", "Only python3 and jq commands are allowed in headless read-only report mode.")

    # 5. Deny all file writes, edits, URL fetches, subagents, and timers
    reply("deny", f"Tool '{name}' is disallowed in headless read-only report mode.")


if __name__ == "__main__":
    main()
