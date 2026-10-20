# Options income layer: covered calls and cash-secured puts

## Default rules and why

| Rule | Default | Why |
|---|---|---|
| Account | **Roth IRA first** if it holds the shares and has options level ≥2 | Premium and assignment are tax-free there. In the taxable account, every premium is taxed as short-term income, and assignment realizes the gain. |
| Expiration | 25–45 days out, and **before** the next earnings date | Time decay is fastest in this window. Earnings can jump the stock past any strike. |
| Strike | Delta 0.15–0.25 | Roughly a 75–85% chance the option expires worthless, with meaningful premium |
| Volatility (IV vs. HV) | **IV > historical average** (1-Yr IV Percentile > 50%, ideally > 70%; IV > 20-day / 30-day realized HV) | Selling premium only pays when implied moves exceed actual historical moves. Avoid selling cheap volatility. |
| Coverage | **≥100 free shares in the lot** (1 contract for 100–199 free shares; up to 50% of free shares for ≥200 free shares). | Keeps upside uncapped on larger positions while allowing 1-lot covered calls on 100+ share holdings. |
| Take profit | Buy back at 50% of the premium (GTC limit placed right after the fill) | Captures most of the edge and frees the shares |
| Manage | Roll at 21 days left, or when delta goes above ~0.40, only for a net credit | |
| Puts: size | Total cash set aside for puts ≤ ~20% of the account | |
| Puts: stop | Close if the mark reaches 2–3× the credit received. Roll down and out only for a credit. | |
| Puts: names | Only on stocks the user is happy to own at that strike, with a maximum position size | |
| Earnings | Close or roll calls you don't want assigned **before** the report. Sell new premium **after** it, once the move has happened. | |
| Other events | Web-search each recommended ticker for big events before expiration (see step 5) | FDA dates, investor days, M&A, lawsuits or an ex-dividend date can gap the stock or trigger early assignment, just like earnings. The Robinhood tools don't report them. |

## Coverage sizing per lot

How to apply it:
- **Count coverage for each lot, in each account.** Shares in the Roth and in the taxable account are separate lots, because a call can only be covered by shares in the same account.
- **Free shares = shares − 100 × short calls already open in that account.**
- **Eligible lot = at least 100 free shares.** Any lot with **under 100 free shares** can't cover a call; list those lots under "what to leave alone" with the reason "under 100 free shares".
- **Maximum new contracts:** `1` contract if the lot has 100–199 free shares; `floor(0.5 × free shares ÷ 100)` if the lot has ≥200 free shares (so larger positions keep at least half of their shares uncapped).

## Practical Workflow for Option Sellers (IV vs. HV Checkpoint)

Before opening or recommending any short premium trade (covered calls, credit spreads, or cash-secured puts), make checking the option contract's Implied Volatility (IV) a priority eligibility criterion. The contract's IV **must be higher than its historical average** to be eligible for recommendation.

**Strict Tool Routing for Volatility & Catalyst Data:**
- **Strictly use Robinhood MCP tools** for:
  - **Contract IV & Greeks:** `get_option_quotes` (`implied_volatility`, `delta`, `theta`, `mark_price`).
  - **Underlying 30D IV & 52W IV Range:** `preview_scan` scoped to the candidate ticker(s) (`expression: "symbol"`, `predicate: "PREDICATE_ANY_OF"`) with columns `atmIv30Day` (or standard column `"Implied volatility"`), `iv52weeksLow`, `iv52weeksHigh`, `frontIV`, `backIV`.
  - **1-Year IV Rank (IVR):** `preview_scan` column `ivRank` (and `atmIv60DayPosInRange` if helpful).
  - **Realized Historical Volatility (HV):** `preview_scan` columns `statVol(candleCount=20, candlePeriod="1d", session="regular")` (20D HV), `statVol(candleCount=30, candlePeriod="1d", session="regular")` (30D HV), and `statVol1Year` (1Y HV) — or computed directly from `get_equity_historicals` daily closes.
- **Use `WebSearch`** for:
  - **1-Year IV Percentile (IVP):** e.g., `"<SYMBOL> implied volatility percentile IVP"` (since Robinhood MCP provides `ivRank` but not day-count IV Percentile).
  - **Volatility Catalysts (Earnings / Ex-Div & Corporate Events):** cross-checking earnings / ex-dividend dates and finding FDA dates, product/investor days, M&A, or regulatory events.

**4-Step Checkpoint:**
1. **Check the 1-Year IV Percentile (via `WebSearch`):** Ensure it is > 50% (ideally > 70%).
2. **Compare to IV Rank (via MCP `preview_scan` `ivRank`):** If IV Percentile is 80% but IV Rank is only 30%, a historical outlier spike (`iv52weeksHigh`) is warping the chart. Rely on the Percentile.
3. **Verify IV > HV — The IV vs. HV Ratio (strictly via MCP):** Confirm that the option contract's IV (`get_option_quotes`) and underlying 30D IV (`atmIv30Day`) are significantly higher than 20-day and 30-day realized Historical Volatility (`statVol` 20d/30d from `preview_scan` or `get_equity_historicals`)—meaning the market is pricing in larger future moves than the stock has actually delivered over the last month.
4. **Identify Volatility Catalysts (via `WebSearch` + `get_earnings_results`):** Ensure the high IV isn't solely due to an upcoming earnings report, ex-dividend date, or major corporate event unless the user is explicitly trying to play a post-earnings "IV Crush".

## Process for "what would you sell Monday"

1. Get the earnings date (`get_earnings_results`) for each **eligible** lot only (≥100 free shares, see above). Drop expirations after the report. Skip the earnings lookup entirely for ineligible lots.
2. Call `get_option_chains(underlying_symbol)` and pick the expiration 25–45 days out that falls before earnings.
3. **Fetch underlying IV, 52W IV range, IV Rank, and 20D/30D/1Y Realized HV strictly from MCP** in a single `preview_scan` call for the eligible symbol(s):
   - Filter: `{"expression": "symbol", "predicate": "PREDICATE_ANY_OF", "values": ["<SYMBOL>", ...]}`
   - Columns: `ivRank`, `iv52weeksHigh`, `iv52weeksLow`, `atmIv30Day`, `frontIV`, `backIV`, `statVol(candleCount=20, candlePeriod="1d", session="regular")`, `statVol(candleCount=30, candlePeriod="1d", session="regular")`, `statVol1Year`.
4. **Estimate the target strike before fetching any contracts**, so you only need 3:
   `strike ≈ price × (1 + 0.8 × IV × √(days/365))`. This gives roughly delta 0.20.
   Use `atmIv30Day` / `frontIV` from Step 3 (or the IV from any option quote you already have on that underlying, or 0.35 for megacap tech, 0.50+ for high-beta names).
   Round to the chain's strike spacing. Then request the estimate, one strike below and one strike above, in a single parallel turn: `get_option_instruments(chain_symbol, expiration_dates, type="call", strike_price=X)`.
   Follow with one `get_option_quotes` call for all of them to get contract `implied_volatility` and Greeks. Don't request unfiltered chains. They return 100+ rows.
5. Pick the strike closest to delta 0.20–0.25. The one above is the fallback.
6. **Complete the Volatility Checkpoint (IV > HV strictly via MCP; 1-Yr IV Percentile & Catalysts via `WebSearch`)**, only for the ticker(s) you're about to recommend (never every holding):
   - **IV vs. Historical Average (Priority Eligibility Check):** Strictly using the MCP numbers from Steps 3–4, verify that the contract's `implied_volatility` and underlying `atmIv30Day` exceed the 20-day and 30-day realized HV (`statVol` 20d/30d) and compare against `ivRank`, `iv52weeksLow`–`iv52weeksHigh`, and `statVol1Year`. Use `WebSearch` to fetch the **1-Year IV Percentile (IVP)**; verify IVP > 50% (ideally > 70%, relying on IVP over MCP's `ivRank` if an outlier spike in `iv52weeksHigh` warps Rank). If IV is below the historical average or realized HV, flag it or pivot to an eligible candidate with richer relative premium.
   - **Volatility Catalysts & Upcoming Events (via `WebSearch`):** Search once per recommended ticker, e.g. `"<SYMBOL> stock news upcoming events earnings ex-dividend <month year>"`, and look for anything between today and the expiration (confirming high IV isn't solely driven by an unspotted binary event):
     - Scheduled: confirmed earnings date (cross-check the Robinhood date), ex-dividend date, FDA/PDUFA or trial readouts, investor or product days, shareholder votes, lock-up expiries, splits, index adds or deletes.
     - Unscheduled (last ~7 days): M&A talk, guidance changes, lawsuits or regulatory actions, analyst moves, management changes.
     - Market-wide: an FOMC or CPI date before expiration, noted once, not per ticker.

   Prefer primary or credible sources (company IR or press releases, SEC filings, Reuters, Bloomberg, WSJ, CNBC, or reputable options data providers for IV Percentile) and note each source's date. Then act on it:
   - An event that could gap the stock before expiration → pick an expiration before it, move to the higher fallback strike, or skip the name and say why.
   - **Ex-dividend before expiration** on a covered call → early assignment risk is high if the dividend exceeds the call's extrinsic value the day before. Flag it.
   - Nothing material → say "no major events found" in one line. News is context: it can flag a risk, but don't let headlines override the delta, IV vs. HV, earnings and coverage rules.
7. Size the trade using the coverage formula, in the best tax location.

## Output template (aim for ≤ ~750 words)

Start with a **Bottom line** of 2–4 lines: the trade, the premium, and why now. Then:

- **The trade:** account, sell to open N × SYMBOL $strike call, expiration, limit price (start at mid, set a floor near the bid), delta, contract IV vs. 20d/30d HV (and 1-Yr IV Percentile / IV Rank), chance of profit, premium in $, strike as % above the price, return over the period and annualized, and coverage (N×100 of the free shares = X%).
- **Why:** 2–3 bullets (IV > HV / volatility edge, earnings timing, tax location, coverage).
- **Events to note:** each event found before expiration with its date, its source and what you did about it, or "no major events found".
- **Management:** take-profit price, roll trigger, and an entry-timing note (sell calls on up days).
- **What to leave alone:** one compact table covering every other holding, with columns for lot, earnings date, and reason or next step. Reasons include reporting soon, under 100 free shares, IV below historical average, or already capped.
- **Fallback:** the next strike up, in one line.
- If the trade can't be placed by the agent (wrong account), say so in one line.
