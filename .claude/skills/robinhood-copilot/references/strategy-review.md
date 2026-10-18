# Strategy review: infer the user's strategy from recent trades

## Data

Fetch in parallel, for each account and for the window the user asked about (default 30 days):

- `get_equity_orders(account_number, created_at_gte=<date>, state="filled")`
- `get_option_orders(account_number, created_at_gte=<date>, state="filled")`
- `get_crypto_orders(rhs_account_number, created_at_gte=<ISO UTC>, state="filled")`. Only for accounts with crypto.
- Then `get_pnl_trade_history(account_number, span="month")`. Use `3month` for longer windows. This gives realized P&L per closing trade, which saves you from pairing opens and closes yourself.

If `next` is non-empty, follow the cursor until the window is covered.

Pull `get_pnl_trade_history` only for accounts that actually had fills in the window. An account with no orders has no realized P&L, so those calls are wasted.

## How to classify activity

Group the orders by symbol and order them by time, then label each pattern:

| Pattern | Signature |
|---|---|
| Short-term covered calls | `short_call` open and then close within days, usually at a profit, often re-sold at a new strike |
| Cash-secured puts / rolling | `short_put` opens. Multi-leg orders that close one put and open another are **rolls**. Note the direction: down and out means getting defensive. |
| Range / swing trading | Repeated buys and sells of the same stock in small size around a core position |
| Averaging down | Successive buys at lower prices, sometimes combined with a short put on the same stock |
| Passive | `placed_agent: "drip"` (dividend reinvestment), recurring buys, or no activity (common in a Roth) |
| Crypto buying | Small market buys. Note the fee rate (`fee_rate`, e.g. 0.95%). |

## Output (aim for ≤ ~850 words)

1. **Bottom line** of 2–3 sentences: what the strategy is, and the net result *including* open P&L on positions opened in the window. Realized P&L alone flatters a seller of options.
2. **One section per pattern**, with a compact table of the actual trades: sold → bought back, days held, realized P&L. Merge small patterns (a one-off round trip) into a single line.
3. **Scorecard:** number of closing trades, win rate, total realized P&L, and how much came from each pattern.
4. **What to tighten.** Give the top ~5 points, **ranked by dollar impact**. Base each point on the data. Common findings:
   - **Market orders on stocks.** Check `type: market` and compare against the bid/ask spread.
   - **Expensive crypto fees.**
   - **Asymmetry:** small profits taken on calls while puts carry larger unrealized losses.
   - **All gains are short-term,** so taxed as ordinary income. Compare the monthly P&L with the account size.
   - **Growing concentration** in a name the user keeps averaging down on.
   - **Far-dated calls (90+ days out, far above the price) closed quickly.** These are bets on the stock price more than income trades. Say so plainly.
