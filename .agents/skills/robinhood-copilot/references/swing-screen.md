# Swing screen: pick one trade from the user's holdings

A swing trade lasts about 1–3 weeks. The screen exists to find a setup where the stop actually protects you and nothing scheduled can jump past it.

## Filters, in order

1. **Earnings window.** Call `get_earnings_results` for every held stock in one parallel turn. ETFs like IBIT have no earnings, so skip them. Exclude any name that reports within ~3 weeks, because a gap through earnings makes the stop meaningless. This usually eliminates most of the holdings, which is fine. Run the remaining filters **only on the names that survive**. That keeps the history and indicator calls small.
2. **Not still falling.** Pull ~3 months of daily bars (`get_equity_historicals`, `interval="day"`, all survivors in one call, max 10). Reject names that have just broken their most recent swing low (lower lows), because the support has failed.
3. **Defined support.** Look for a level tested 2–3 times in the last ~3 months, with the price within ~1 ATR above it.
4. **Momentum context.** RSI(14) and ATR(14) via `get_equity_technical_indicators` (`output="latest"`, one call per indicator for all symbols). RSI 30–40 at support is a bounce candidate. An RSI around 50 mid-range has no edge.
5. **Cost of trading.** Wide spreads or high fees (crypto ~1% each way) eat a swing edge. Note them.
6. **Existing exposure.** If the user already owns a lot of the winner, cap the size and make it a time-boxed trade, not an addition to the position. If a short option already gives exposure to a name, say so rather than adding more.
7. **News & catalysts (`search_web`).** Only **after** picking the recommended ticker (never search other holdings; skip if the result is "no trade"), search once with `search_web` (e.g. `"<SYMBOL> stock news upcoming events <month year>"`) for:
   - Unscheduled news from the last ~7 days (M&A talk, guidance changes, lawsuits/regulatory actions, analyst moves, management changes).
   - Scheduled catalysts before the time stop (confirmed earnings date, ex-dividend, FDA/PDUFA dates, investor or product days, FOMC/CPI).
   Prefer primary or credible sources (company IR or press releases, SEC filings, Reuters, Bloomberg, WSJ, CNBC) and note each source with its date. News is context only: it can flag a risk or tighten a condition, but must not override the technical filters.

## Trade plan

| Field | How |
|---|---|
| Entry | Limit order near support. Add a condition, e.g. "only if it holds $X in the first 30–60 min. Skip if it opens below $Y." |
| Stop | Below the support low, about 1–1.5 × ATR |
| Target 1 | The nearest overhead level. Sell half there and move the stop to your entry price. |
| Target 2 | The start of the breakdown or the prior gap |
| Reward vs. risk | Show it for both targets |
| Time stop | Exit before the next earnings date |
| Size | Risk-based, then capped by concentration. Show sizes for the tradable account and for the user's main account. |

## Also include

Start with a **Bottom line** of 2–3 lines: the ticker, entry, stop, target and size, or "no trade". Then the trade-plan table, then:

- **News & catalysts:** recent news (last ~7 days) and scheduled catalysts before the time stop for the recommended ticker, citing each credible source with its date, or "no major catalysts found".
- **What I passed on:** a table of every holding with its earnings date and the one-line reason it failed a filter. Users often ask "why X and not Y", so answer it up front.
- **What would cancel the idea:** e.g. a gap below support, or a sector-wide drop.
- **How it fits with the user's other open plans or positions,** e.g. a short call strike above target 2 is compatible.
- If nothing passes, say "no trade" and offer the post-earnings re-screen date.
