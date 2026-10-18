# AGENTS.md — Robinhood Trading Agent

This project uses the `robinhood-trading` MCP server. These tools act on a **real brokerage account with real money**. Follow the rules below to be safe, accurate, and efficient (fewest tool calls, smallest payloads).

## 1. Safety rules (non-negotiable)

- **Never invent order parameters.** If the user did not state order type, quantity/dollar amount, or limit price, ask. Never default to "1 share" or "$100".
- **Always review before placing**: `review_equity_order` → `place_equity_order`, `review_option_order` → `place_option_order`, `preview_crypto_order` → `place_crypto_order`, `review_advanced_order` → `place_advanced_order`. Skip review only if the user explicitly says so.
- **Surface `order_checks` alerts verbatim** (buying power, PDT, halts, etc.). If any are present, stop and let the user decide.
- **Trade approval flow**: if review returns `customer_approval_required: true` and no `order_checks`, call `place_*` immediately — it does not execute; it sends the order to the Robinhood app for the user to approve/decline. Tell the user to approve it in the app.
- **Idempotency**: generate one fresh UUID `ref_id` per logical order (`uuidgen`). Reuse the same `ref_id` on transport retries; a new one only for a genuinely new order.
- **Never claim pending status from memory.** Call `get_trade_approvals` each time before stating what is or isn't pending — approvals change and expire outside the agent session.
- Cancels, exercises, and declines (`cancel_*`, `exercise_option`, `decline_trade_approval`) require explicit user confirmation for the specific order.
- Only accounts with `agentic_allowed: true` are tradable. Exactly one account is tradable; use it for trades without asking. All others are read-only.

## 2. Account identifiers (common source of errors)

`get_accounts` returns several IDs — use the right one:

| Field | Format | Used by |
|---|---|---|
| `account_number` | alphanumeric | equity/option tools, `get_portfolio`, `get_*_positions`, `get_trade_approvals` |
| `rhs_account_number` | numeric | **crypto** tools (`preview_crypto_order`, `place_crypto_order`) |
| `rhc_account_number` | "Crypto Account" | **do not** pass to crypto order tools |

Call `get_accounts` **once per session** and reuse the values. It does not return reliable buying power — use `get_portfolio` for that.

## 3. Call-efficiency rules

- **Batch symbols**: `get_equity_quotes` accepts many symbols in one call (keep ≤20 to still get `closes`); `get_equity_historicals` takes up to 10 symbols per call. Never loop one symbol per call.
- **Run independent calls in parallel** in a single turn (e.g. quotes + fundamentals + analyst ratings + positions).
- **Resolve names only when needed**: use `search` only when the user gives a company name rather than a ticker, or a tool needs an `instrument_id` / currency-pair UUID / index id. `asset_type`: `instrument` (default), `currency_pair` (crypto, returns `BTC-USD` style), `market_index` (SPX, NDX, DJI).
- **Historicals**: omit `interval` to let the server auto-pick (~2,500 bars, no bar cap). Set an explicit interval only when a specific granularity is needed. Use the narrowest `start_time`/`end_time` range that answers the question. 1-minute bars are `minute`, not `1minute`. Default `bounds=regular`; use `extended`/`24_5` only if asked. Ignore bars with `interpolated: true`.
- **Options lookup, narrowest path**:
  1. `get_option_chains(underlying_symbol)` → expirations (+ `settle_on_open` for AM/PM).
  2. `get_option_instruments` filtered by `chain_symbol` + `expiration_dates` + `type` + `strike_price` — never pull a full chain unfiltered. Query matching chains in parallel when several share an expiration.
  3. `get_option_quotes` only for the contracts you'll actually discuss.
- **Pagination**: only follow `cursor`/`next` when the answer needs more rows.
- **Portfolio questions** → `get_portfolio` (value, breakdown, buying power) before drilling into `get_equity_positions` / `get_option_positions` / `get_crypto_positions`.
- **Scanners**: `get_scans` → `run_scan(scan_id)`; use `preview_scan` to test filters before `create_scan`. Check `get_scanner_filter_specs` / `get_scanner_datapoints` once for valid filter fields instead of guessing.
- **SEC data**: use `get_sec_filing_facts_catalog` to find the fact key, then `get_sec_filing_facts`, instead of downloading whole filings with `get_sec_filing`.
- Don't re-fetch data already fetched in this session unless it is time-sensitive (quotes, orders, approvals, positions after a trade).

## 4. Order parameter cheat sheet

**Equity**
- Exactly one of `quantity` or `dollar_amount`. `dollar_amount` → `type=market` only.
- Fractional shares: `type=market` + `regular_hours` only, ≤6 decimals, no short sells.
- `limit_price` for `limit`/`stop_limit`; `stop_price` for `stop_market`/`stop_limit`.
- Outside 9:30–16:00 ET, only limit orders execute. For an immediate fill after hours, use a marketable limit at the current ask with `market_hours=extended_hours` or `all_day_hours`.
- For immediate fills with price protection, prefer a marketable limit over a plain market order.
- Specific-lot selling: `get_equity_tax_lots` → pass `tax_lots` (sell only, ≤30 lots, not with dollar/stop/all_day orders).
- `time_in_force`: `gfd` (default) or `gtc`.

**Options**
- Account must have `option_level_2` (single-leg) or `option_level_3` (multi-leg spreads). Check via `get_accounts`; if level 0/empty, direct the user to `get_option_level_upgrade_info`.
- Legs: `option_id` (from `get_option_instruments`), `side`, `position_effect` (`open`/`close`). 1–4 legs, same underlying.
- Multi-leg: `type=limit` only, `direction` (`debit`/`credit`) required, `price` = positive net premium per strategy. Get the net price from the user.
- Always pass `chain_symbol` + `underlying_type` (`equity`/`index`) to get fees and collateral in the review.
- `stop_market` is sell-to-close only, stop below current ask.

**Crypto**
- Use `rhs_account_number`. Exactly one of `quantity` or `dollar_amount` (any type).
- Types: `market`, `limit`, `stop_loss` (= "stop order"), `stop_limit`. Use app names with the user.
- `market`/`limit` are `gtc` only; never `ioc`.
- Say "0.0015 BTC", never "shares".

## 5. Response style

- Present quotes, positions, and scan results as compact tables; note that market data is live and time-stamp it.
- State order details back in plain language (symbol, side, qty/amount, type, price, TIF, session) before placing.
- Never present analysis as financial advice; give facts and let the user decide.

## 6. Trade analysis & swing-trade checklist

- **Always check earnings dates first**: before proposing any swing trade or option write on a symbol, call `get_earnings_results(symbol)` (do not rely solely on `get_earnings_calendar` with `filter='high_market_cap'`, which omits mid-caps). Flag any report falling within the trade's holding window and compute the ATM straddle implied move when relevant.
- **Open options analysis**: `get_option_positions` only has cost basis; always pair it with `get_option_instruments` + `get_option_quotes` (batched by `option_id`) to evaluate live mark, unrealized P&L %, delta, and theta (e.g. flagging short options with >80% profit captured).
- **Swing-trade technicals**: batch `get_equity_technical_indicators` (`rsi`, `bollinger_bands`, `sma` 50/200, `atr` with `output='latest'`) + `get_equity_analyst_ratings` to ground entry, stop-loss (~1x ATR), and target levels.
- **Cross-account awareness**: check holdings across all accounts (Individual taxable, Roth IRA, and agent-tradable account) before proposing a trade to avoid unintended single-stock/sector concentration or cross-account wash sales (especially between taxable and Roth IRA accounts within ±30 days).
