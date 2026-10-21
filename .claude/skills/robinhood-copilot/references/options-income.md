# Options income layer: covered calls and cash-secured puts

## Default rules and why

| Rule | Default | Why |
|---|---|---|
| **Dual recommendation** | **Always recommend BOTH a Covered Call AND a Cash-Secured Put (CSP)** | Options income uses two complementary levers: harvesting call premium on existing 100+ share lots and harvesting put premium with idle buying power to acquire quality shares at a discount. Always evaluate and output a recommendation for **both** legs (if no candidate passes the rules for one leg, explicitly state **"No trade"** for that leg and explain why). |
| Account | **Roth IRA first** if it holds the shares (for calls) or sufficient free buying power (for puts) and has options level ≥2; otherwise Individual taxable | Premium and assignment are tax-free in the Roth. In the taxable account, every premium is taxed as short-term income, and call assignment realizes capital gains. |
| Expiration | 25–45 days out, and **before** the next earnings date | Time decay is fastest in this window. Earnings can gap the stock past any strike. |
| Strike | **Calls:** Delta `+0.15` to `+0.25`<br>**Puts:** Delta `-0.15` to `-0.25` (`|Δ|` 0.15–0.25) | Roughly a 75–85% chance the option expires worthless, with meaningful premium and an OTM buffer. |
| Volatility (IV vs. HV) | **IV > historical average** (1-Yr IV Percentile > 50%, ideally > 70%; IV > 20-day / 30-day realized HV) | Selling premium only pays when implied moves exceed actual historical moves. Avoid selling cheap volatility. |
| Calls: coverage | **≥100 free shares in the lot** (1 contract for 100–199 free shares; up to 50% of free shares for ≥200 free shares). | Keeps upside uncapped on larger positions while allowing 1-lot covered calls on 100+ share holdings. |
| Take profit | Buy back at 50% of the premium (GTC limit placed right after the fill) | Captures most of the edge and frees the shares or cash collateral early. |
| Calls: manage | Roll at 21 days left, or when delta goes above ~0.40, only for a net credit | |
| Puts: size | Total cash collateral (`strike × 100 × contracts`, including existing open short puts) ≤ ~20% of the account and ≤ available `buying_power` | Keeps plenty of dry powder and prevents over-leverage in a market drawdown. |
| Puts: stop & manage | Close if the mark reaches 2–3× the credit received, or roll down and out for a net credit at 21 DTE / `|delta| > 0.40`. | Caps downside tail risk if the underlying breaks support. |
| Puts: names | Quality stocks/ETFs in the user's holdings (especially under-100-share lots they are building) that aren't already >20% of total portfolio | Ensures put assignment only adds to high-conviction names at a discount without worsening single-stock concentration. |
| Earnings | Close or roll short options you don't want assigned **before** the report. Sell new premium **after** it, once the move has happened. | |
| Other events | Web-search each recommended ticker for big events before expiration (see step 6) | FDA dates, investor days, M&A, lawsuits or an ex-dividend date can gap the stock or trigger early assignment, just like earnings. The Robinhood tools don't report them. |

## Coverage & collateral sizing

### 1. Covered Calls (share coverage per lot)
- **Count coverage for each lot, in each account.** Shares in the Roth and in the taxable account are separate lots, because a call can only be covered by shares in the same account.
- **Free shares = shares − 100 × short calls already open in that account.**
- **Eligible call lot = at least 100 free shares + clean pre-earnings 25–45 DTE window + IV > historical average (IV > 20D/30D HV & 1-Yr IVP > 50%).** Any lot with **under 100 free shares** can't cover a call; list those lots under "what to leave alone" for calls with the reason "under 100 free shares" (though they remain eligible candidates for cash-secured puts!).
- **Maximum new call contracts:** `1` contract if the lot has 100–199 free shares; `floor(0.5 × free shares ÷ 100)` if the lot has ≥200 free shares (so larger positions keep at least half of their shares uncapped).

### 2. Cash-Secured Puts (cash collateral per account)
- **Check free buying power in each option-enabled account (`option_level ≥ 2`):** Use `buying_power` from `get_portfolio`.
- **Count existing put collateral:** Sum `strike × 100 × qty` across all open short puts in that account.
- **Available CSP collateral budget:** `min(free buying_power, max(0, 0.20 × account_equity − existing_put_collateral))`.
- **Eligible CSP candidates:** Any held stock or ETF in the user's portfolio where:
  1. Combined holding weight across all accounts is **< 20% of total portfolio value** (never sell puts on an already over-concentrated core position like a >30% holding).
  2. One contract's collateral (`put_strike × 100`) fits inside the account's **available CSP collateral budget**.
  3. The ticker has an expiration 25–45 days out **strictly before** its next earnings report.
  4. **IV > historical average:** The put contract's `implied_volatility` and underlying `atmIv30Day` exceed 20D/30D realized HV (`statVol` 20d/30d) and 1-Yr IV Percentile > 50% (ideally > 70%).

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

## Process for "what would you sell Monday" (Covered Calls & Cash-Secured Puts)

You must evaluate and recommend **both** a Covered Call and a Cash-Secured Put:

1. **Identify eligible candidates and check earnings (`get_earnings_results`):**
   - **Covered Call candidates:** Lots with `≥100 free shares` in an option-enabled account.
   - **Cash-Secured Put candidates:** Held tickers with `<20%` combined portfolio concentration whose approximate collateral (`0.9 × price × 100`) fits within an option-enabled account's available CSP collateral budget (`≤ buying_power` and keeps total put collateral `≤ 20%` of account value).
   - Call `get_earnings_results` in parallel for all eligible Call and Put candidates. Drop any expiration that falls on or after the next earnings date.
2. Call `get_option_chains(underlying_symbol)` for candidates with clean pre-earnings windows and pick the expiration 25–45 days out that falls strictly before earnings.
3. **Fetch underlying IV, 52W IV range, IV Rank, and 20D/30D/1Y Realized HV strictly from MCP** in a single `preview_scan` call for all eligible Call and Put symbols:
   - Filter: `{"expression": "symbol", "predicate": "PREDICATE_ANY_OF", "values": ["<SYMBOL>", ...]}`
   - Columns: `ivRank`, `iv52weeksHigh`, `iv52weeksLow`, `atmIv30Day`, `frontIV`, `backIV`, `statVol(candleCount=20, candlePeriod="1d", session="regular")`, `statVol(candleCount=30, candlePeriod="1d", session="regular")`, `statVol1Year`.
4. **Estimate the target strikes before fetching any contracts**, so you only need 3 strikes per leg:
   - **Covered Call strike (~`+0.20` delta):** `call_strike ≈ price × (1 + 0.8 × IV × √(days/365))`
   - **Cash-Secured Put strike (~`-0.20` delta):** `put_strike ≈ price × (1 - 0.8 × IV × √(days/365))`
   Use `atmIv30Day` / `frontIV` from Step 3 (or 0.35 for megacap tech, 0.50+ for high-beta names).
   Round to the chain's strike spacing. Then request the estimate, one strike below and one strike above, in a single parallel turn:
   - Calls: `get_option_instruments(chain_symbol, expiration_dates, type="call", strike_price=X)`
   - Puts: `get_option_instruments(chain_symbol, expiration_dates, type="put", strike_price=Y)`
   Follow with one batched `get_option_quotes` call for all fetched option IDs to get contract `implied_volatility` and Greeks. Don't request unfiltered chains (they return 100+ rows).
5. **Select primary and fallback strikes for both legs:**
   - **Covered Call:** Pick the call strike closest to delta `+0.15` to `+0.25`. The next strike **up** is the call fallback.
   - **Cash-Secured Put:** Pick the put strike closest to delta `-0.15` to `-0.25` (`|Δ|` 0.15–0.25). The next strike **down** is the put fallback.
6. **Complete the Volatility Checkpoint (IV > HV strictly via MCP; 1-Yr IV Percentile & Catalysts via `WebSearch`)**, only for the ticker(s) you're about to recommend for the Call and Put (never every holding):
   - **IV vs. Historical Average (Priority Eligibility Check):** Strictly using the MCP numbers from Steps 3–4, verify that the contract's `implied_volatility` and underlying `atmIv30Day` exceed the 20-day and 30-day realized HV (`statVol` 20d/30d) and compare against `ivRank`, `iv52weeksLow`–`iv52weeksHigh`, and `statVol1Year`. Use `WebSearch` to fetch the **1-Year IV Percentile (IVP)**; verify IVP > 50% (ideally > 70%, relying on IVP over MCP's `ivRank` if an outlier spike in `iv52weeksHigh` warps Rank). If IV is below the historical average or realized HV, flag it or pivot to an eligible candidate with richer relative premium.
   - **Volatility Catalysts & Upcoming Events (via `WebSearch`):** Search once per recommended ticker, e.g. `"<SYMBOL> stock news upcoming events earnings ex-dividend <month year>"`, and look for anything between today and the expiration (confirming high IV isn't solely driven by an unspotted binary event):
     - Scheduled: confirmed earnings date (cross-check the Robinhood date), ex-dividend date, FDA/PDUFA or trial readouts, investor or product days, shareholder votes, lock-up expiries, splits, index adds or deletes.
     - Unscheduled (last ~7 days): M&A talk, guidance changes, lawsuits or regulatory actions, analyst moves, management changes.
     - Market-wide: an FOMC or CPI date before expiration, noted once, not per ticker.

   Prefer primary or credible sources (company IR or press releases, SEC filings, Reuters, Bloomberg, WSJ, CNBC, or reputable options data providers for IV Percentile) and note each source's date. Then act on it:
   - An event that could gap the stock before expiration → pick an expiration before it, move to a safer fallback strike (higher for calls, lower for puts), or skip the name and say why.
   - **Ex-dividend before expiration** on a covered call → early assignment risk is high if the dividend exceeds the call's extrinsic value the day before. Flag it.
   - Nothing material → say "no major events found" in one line. News is context: it can flag a risk, but don't let headlines override the delta, IV vs. HV, earnings and coverage/collateral rules.
7. **Size both trades in the best tax location:**
   - **Covered Call:** Size using the lot share-coverage formula (Roth IRA first).
   - **Cash-Secured Put:** Size within the account's available CSP collateral budget (`put_strike × 100 × N ≤ free buying_power` and total put collateral `≤ ~20%` of account value; Roth IRA first if it has enough free buying power, otherwise Individual taxable).

## Output template (aim for ≤ ~750 words)

Start with a **Bottom line** of 2–4 lines summarizing **both** the Covered Call recommendation and the Cash-Secured Put recommendation (the trades, total premiums, and why now — or stating clearly if either leg is a "No trade" due to earnings/IV/cash constraints). Then:

- **The trades:** present a compact comparison table covering **1) Covered Call** and **2) Cash-Secured Put** side-by-side: account, action (`Sell to open N × SYMBOL $strike Call` and `Sell to open M × SYMBOL $strike Put`), expiration (DTE), limit price (start at mid, set a floor near the bid), delta, contract IV vs. 20d/30d HV (and 1-Yr IV Percentile / IV Rank), chance of profit, total premium in $, buffer (% above spot for call / % below spot & net breakeven for put), return over the period and annualized (on share value for call; on `strike × 100` collateral for put), and coverage/collateral (`N×100` of free shares = X% for call; `$collateral` = Y% of account / free buying power for put).
- **Why:** 2–4 bullets covering both legs (IV > HV / volatility edge, pre-earnings timing, tax location, share coverage & put collateral sizing).
- **Events to note:** each event found before expiration for the recommended call and put ticker(s) with its date, its source and what you did about it, or "no major events found".
- **Management:** take-profit prices (50% of credit for each), roll/stop triggers (roll calls at 21 DTE or `Δ > 0.40` for a credit; close puts at 2–3× credit or roll down/out for a credit at 21 DTE / `|Δ| > 0.40`), and entry-timing notes (**sell calls on green/up days; sell puts on red/down days**).
- **What to leave alone:** one compact table covering every other holding, with columns for lot, earnings date, and reason skipped for Calls and/or Puts (e.g., reporting soon, under 100 free shares for calls, collateral exceeds free buying power or >20% portfolio concentration for puts, IV below historical average, or already capped).
- **Fallback:** one line each for the Covered Call (next strike **up**) and Cash-Secured Put (next strike **down**).
- If the trade(s) can't be placed by the agent (wrong account), say so in one line.
