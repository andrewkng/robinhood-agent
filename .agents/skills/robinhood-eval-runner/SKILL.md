---
name: robinhood-eval-runner
description: >-
  Runs and grades the evaluation suite (evals.json) for the robinhood-copilot skill in Antigravity (agy) using parallel isolated subagents and automated transcript auditing. Use this skill whenever the user asks to "run the evals", "test robinhood-copilot", "benchmark the skill", "run evals.json", or grade skill performance.
---

# Robinhood Copilot Eval Runner (`agy`)

This skill executes the evaluation suite for `robinhood-copilot` natively in Antigravity (`agy`) using parallel isolated `self` subagents and grades every assertion using both deterministic transcript checks and semantic verification.

## Step 1: Load the Eval Suite

1. Read the eval definitions from [evals.json](./evals/evals.json) (or `.claude/skills/robinhood-copilot/evals/evals.json` if updated more recently).
2. Identify which eval IDs to run:
   - By default, run **all** evals (`id: 1` through `id: 4`).
   - If the user specifies a subset (e.g., "run eval 2"), only launch those.

## Step 2: Launch Isolated Subagents in Parallel

Call `invoke_subagent` once with an entry in `Subagents` for each eval case:
- `TypeName`: `"self"` (so each subagent inherits the workspace skills and `robinhood` MCP server in a clean, isolated context).
- `Model`: `"inherit"` (unless the user explicitly requests a specific model tier).
- `Role`: `"Eval <id>: <short title>"`
- `Prompt`: Pass the exact `prompt` string from `evals.json` verbatim.

**Important:** Do **not** poll `manage_subagents` in a loop after calling `invoke_subagent`. End your turn and wait for the system to deliver each subagent's completion message.

## Step 3: Run the Automated Transcript Audit

Once all subagents have reported back, run [audit_transcripts.py](./scripts/audit_transcripts.py) via `run_command`, passing `<eval_id>:<conversation_id>` pairs:

```bash
python3 .agents/skills/robinhood-eval-runner/scripts/audit_transcripts.py \
  1:<conv_id_1> 2:<conv_id_2> 3:<conv_id_3> 4:<conv_id_4>
```

The script inspects `<appDataDir>/brain/<conv_id>/.system_generated/logs/transcript_full.jsonl` for each subagent and deterministically verifies:
- **Word count** (both whitespace-delimited and alphanumeric/numeric tokens excluding Markdown table pipes) against the eval's word limit (`<=800` or `<=900` words).
- **Account number masking** (verifies no full 9-digit `account_number` or 12-digit `rhc_account_number` appears in the output).
- **Read-only safety** (verifies zero calls to `place_*`, `review_*`, `preview_*`, `cancel_*`, `exercise_*`, or `decline_*`).
- **Earnings lookup efficiency** (verifies `get_earnings_calendar` was never called).
- **Option chain efficiency** (counts `get_option_instruments` calls by `strike_price` per underlying).
- **Realized P&L tool usage** (checks if `get_pnl_trade_history` or `get_realized_pnl` was called for Eval 3).

## Step 4: Grade All Assertions & Report the Scorecard

Combine the deterministic checks from Step 3 with semantic verification of each subagent's response against the `assertions` array in `evals.json`. Present:

1. **Overall Summary Table:** Eval ID, clickable link to the subagent transcript (`[Eval N](conversation://<conv_id>)`), pass count (`X / Y`), word count, MCP tool call count, and any failed assertions.
2. **Per-Eval Assertion Checklist:** Every assertion from `evals.json` marked with `✅` or `❌` and a concise 1-line evidence note citing the exact numbers/tools from the subagent run.
3. **Actionable Skill Fixes (if any assertions failed):** Point out specific lines in `.agents/skills/robinhood-copilot/SKILL.md` or `references/*.md` that can be tightened to fix any failing assertions.
