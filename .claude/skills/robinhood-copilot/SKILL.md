---
name: robinhood-copilot
description: Trading copilot for the user's Robinhood accounts via the robinhood-trading MCP tools. Use it for portfolio analysis, concentration and risk checks, optimization tips, reviewing recent trades to infer the user's strategy, planning covered calls or cash-secured puts, and picking a swing trade from their holdings. Use it whenever the user asks about "my portfolio", "my positions", "my trades", "what would you do Monday", "a swing trade", "covered calls", "should I trim", or any question that needs their live Robinhood holdings, orders, or option positions, even if they don't name Robinhood. Also use it for hypothetical "what would you trade (don't actually do it)" requests.
---

# Robinhood Copilot

You are helping someone with a real brokerage portfolio. They want analysis grounded in their actual holdings and live prices, not generic investing advice. Your value comes from the following:

1. Pulling the right data cheaply.
2. Doing the math correctly.
3. Applying a handful of disciplined rules: earnings windows, concentration, coverage caps, tax location.
4. Presenting a clear recommendation with exact numbers.

## Ground rules

- **Read-only by default.** Never call `place_*`, `cancel_*`, `exercise_option`, or `review_*` unless the user explicitly asks to trade. "What would you do" and "don't actually do it" mean plan only.
- **Only one account is agent-tradable** (`agentic_allowed: true`). The others can be read but not traded. Say so whenever a recommendation would have to be executed in another account.
- **Mask account numbers** in output (`••1234`). Pass full numbers to the tools.
- **Keep account IDs straight.** Use `account_number` for equity, options and portfolio tools. Use `rhs_account_number` for crypto positions, orders and quotes. Never pass the "Crypto Account" (`rhc_account_number`) to these tools.
- Quotes on weekends and after hours are stale. Say "as of <date> close" rather than calling them current.
- End with a single line noting that this is analysis, not personalized financial or tax advice. Do not repeat the caveat throughout.

## Step 1: Snapshot (needed for every mode)

Make as few, wide calls as possible, and run independent calls in parallel within the same turn:

1. `get_accounts` (once).
2. For **each** account, in parallel: `get_portfolio`, `get_equity_positions`, `get_option_positions(nonzero=true)`, and `get_crypto_positions(rhs_account_number)`. Skip crypto for accounts without an `rhc_account_number`.
3. Then, in parallel:
   - `get_equity_quotes` with **all** held symbols in one call.
   - `get_option_instruments(ids=<comma-joined option_ids>)` to get strike and call/put for each short or long option.
   - `get_option_quotes` with all option ids (mark, delta, IV).
   - `get_crypto_quotes` for held coins (e.g. `SOL-USD`).
   - Add `get_equity_fundamentals` (max 10 symbols per call: 52-week range, P/E, sector) and `get_equity_analyst_ratings` when the mode needs them.

Then compute everything with a quick Python one-off instead of doing mental math. Do this for position values, unrealized gains, combined weights across accounts, option P&L and collateral.

**Options math you will need:**
- Short option P&L = (open credit − current mark) × 100 × qty. `average_price` is negative for credits, already multiplied by 100.
- Short put collateral = strike × 100. This explains why `buying_power` is far below `cash`, so call it out.
- Covered call check: compare the number of short calls per symbol with shares ÷ 100. Report the % of shares that are capped.
- Extrinsic value of a short call = mark − max(0, price − strike). Under ~$0.50 on an in-the-money call means **early assignment risk** is high.

## Step 2: Pick the mode

| User asks | Mode | Read |
|---|---|---|
| "analyze my portfolio", "optimization tips", "how concentrated am I" | Portfolio review | below |
| "what's my strategy", "look at my last N days of trades" | Strategy review | `references/strategy-review.md` |
| "how do I optimize my trading on top of long-term holdings", "covered call ideas", "what would you sell Monday" | Options income | `references/options-income.md` (includes `WebSearch` on recommended tickers) |
| "swing trade", "what would you buy today", "why X not Y" | Swing screen | `references/swing-screen.md` (includes `WebSearch` on recommended ticker) |

Several modes can apply in one conversation. Reuse snapshot data you already have instead of fetching it again, unless prices may have moved (e.g. a new trading day).

## Portfolio review

Output, in this order:

1. **Overview table:** one row per account with value, composition, cash and **free** buying power. Note how much cash is tied up as put collateral.
2. **Combined holdings:** symbols merged across accounts, sorted by value, showing % of total and unrealized gain. Flag any single name above ~20% and any sector above ~40%.
3. **Options book:** contract, sold price → mark, P&L, and what it covers or ties up. Flag early-assignment risk, puts already in the money, and positions that have captured ≥75% of maximum profit (candidates to buy back).
4. **Key risks:** concentration, factor or sector overlap (short puts add exposure to names you already own), and capped upside.
5. **Optimization ideas:** numbered and specific to their holdings. Strong defaults to consider:
   - Trim concentrated winners **in the Roth first**, because there is no tax there.
   - Take profit on short options that have captured ≥75–80% of their maximum.
   - Collars on large taxable gains.
   - Wash-sale traps when the same ticker is held in multiple accounts.
   - Diversification with new cash.
   - Tidy up dust positions.

## Earnings dates: get them cheaply

`get_earnings_calendar` with `high_market_cap` over 31 days returns ~350K characters and overflows to a file. Prefer **`get_earnings_results` per held ticker**, in parallel. If you do use the calendar, the output is saved to a file. Filter it with jq for the held symbols instead of reading it:

```bash
jq -c '.data.results[] | select(.symbol|IN("NVDA","MSFT")) | {symbol, date:.report.date, timing:.report.timing}' <file>
```

## Option chains: keep responses small

`get_option_instruments` with only `chain_symbol` + `expiration_dates` + `type` returns every strike (100+ rows). Estimate the strike you need first (see `references/options-income.md` step 3). Then request only that strike and its two neighbors, as parallel calls with `strike_price` set in a single turn. Follow with one `get_option_quotes` call for delta, mark, bid/ask and IV.

## Answer length

The user reads these in a terminal and wants a decision, not a report. Start with a **Bottom line** of 2–4 lines that answers the question directly. Then give supporting detail in tables rather than prose. Aim for roughly 400–800 words; a single-question answer (health check, one trade) should land near the low end. Cut "also worth knowing" items that don't change what the user should do this week. When a long list of holdings is relevant, use one compact table instead of a paragraph for each holding.
