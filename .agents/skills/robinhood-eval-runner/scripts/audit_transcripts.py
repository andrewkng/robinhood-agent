#!/usr/bin/env python3
"""Deterministic transcript auditor for robinhood-copilot eval runs in Antigravity."""

import json
import re
import sys
from pathlib import Path

APP_DATA_DIR = Path.home() / ".gemini" / "antigravity-cli" / "brain"
WRITE_PREFIXES = ("place_", "review_", "preview_", "cancel_", "exercise_", "decline_")


def audit_conversation(eval_id: str, conv_id: str) -> dict:
    tpath = APP_DATA_DIR / conv_id / ".system_generated" / "logs" / "transcript_full.jsonl"
    if not tpath.exists():
        tpath = APP_DATA_DIR / conv_id / ".system_generated" / "logs" / "transcript.jsonl"
    if not tpath.exists():
        return {"eval_id": eval_id, "conv_id": conv_id, "error": f"Transcript not found at {tpath}"}

    mcp_calls = []
    sent_message = ""
    raw_account_numbers = set()

    with open(tpath, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            step = json.loads(line)

            # Extract raw account numbers from get_accounts tool responses if present
            content = step.get("content") or ""
            for match in re.findall(r'"(?:rhs_|rhc_)?account_number"\s*:\s*"(\d{6,})"', content):
                raw_account_numbers.add(match)

            for tc in step.get("tool_calls") or []:
                name = tc.get("name") or ""
                args = tc.get("args") or tc.get("arguments") or {}
                if isinstance(args, str):
                    try:
                        args = json.loads(args)
                    except Exception:
                        args = {}
                if name == "call_mcp_tool":
                    tname = args.get("ToolName") or args.get("tool_name") or ""
                    targs = args.get("Arguments") or args.get("arguments") or {}
                    mcp_calls.append((tname, targs))
                elif name == "send_message":
                    sent_message = args.get("Message") or ""

    whitespace_words = len(sent_message.split())
    prose_tokens = len(re.findall(r"[A-Za-z0-9$%+.]+", sent_message))
    first_6_lines = "\n".join(sent_message.strip().splitlines()[:6])

    leaked_accounts = [acc for acc in raw_account_numbers if acc in sent_message]
    write_tools = [t for t, _ in mcp_calls if any((t or "").startswith(p) for p in WRITE_PREFIXES)]
    calendar_calls = [t for t, _ in mcp_calls if t == "get_earnings_calendar"]
    pnl_calls = [t for t, _ in mcp_calls if t in ("get_pnl_trade_history", "get_realized_pnl")]

    opt_strike_queries = [
        a for t, a in mcp_calls
        if t == "get_option_instruments" and isinstance(a, dict) and ("chain_symbol" in a or "strike_price" in a)
    ]

    return {
        "eval_id": eval_id,
        "conv_id": conv_id,
        "whitespace_words": whitespace_words,
        "prose_tokens": prose_tokens,
        "leaked_accounts": leaked_accounts,
        "write_tools_called": write_tools,
        "earnings_calendar_called": len(calendar_calls) > 0,
        "pnl_tools_called": pnl_calls,
        "option_strike_queries_count": len(opt_strike_queries),
        "option_strike_queries": opt_strike_queries,
        "total_mcp_calls": len(mcp_calls),
        "mcp_tool_names": [t for t, _ in mcp_calls],
        "first_6_lines": first_6_lines,
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: audit_transcripts.py <eval_id>:<conv_id> [...]", file=sys.stderr)
        sys.exit(1)

    results = []
    for arg in sys.argv[1:]:
        if ":" not in arg:
            continue
        eid, cid = arg.split(":", 1)
        results.append(audit_conversation(eid, cid))

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
