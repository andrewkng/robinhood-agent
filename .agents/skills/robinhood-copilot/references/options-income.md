# Options income layer: covered calls and cash-secured puts

## Default rules and why

| Rule | Default | Why |
|---|---|---|
| Account | **Roth IRA first** if it holds the shares and has options level ≥2 | Premium and assignment are tax-free there. In the taxable account, every premium is taxed as short-term income, and assignment realizes the gain. |
| Expiration | 25–45 days out, and **before** the next earnings date | Time decay is fastest in this window. Earnings can jump the stock past any strike. |
| Strike | Delta 0.15–0.25 | Roughly a 75–85% chance the option expires worthless, with meaningful premium |
| Coverage | **At most 50% of the free shares in each lot.** This is a hard limit (see below). | |
| Take profit | Buy back at 50% of the premium (GTC limit placed right after the fill) | Captures most of the edge and frees the shares |
| Manage | Roll at 21 days left, or when delta goes above ~0.40, only for a net credit | |
| Puts: size | Total cash set aside for puts ≤ ~20% of the account | |
| Puts: stop | Close if the mark reaches 2–3× the credit received. Roll down and out only for a credit. | |
| Puts: names | Only on stocks the user is happy to own at that strike, with a maximum position size | |
| Earnings | Close or roll calls you don't want assigned **before** the report. Sell new premium **after** it, once the move has happened. | |
| Other events | Web-search each recommended ticker for big events before expiration (see step 5) | FDA dates, investor days, M&A, lawsuits or an ex-dividend date can gap the stock or trigger early assignment, just like earnings. The Robinhood tools don't report them. |

## The 50% coverage limit is firm, so don't offer exceptions

People holding long-term winners regret capped upside far more than they value an extra $50–100 of premium. The classic failure is a position with 100% of its shares under deep in-the-money calls: no upside, early-assignment risk, and a forced taxable sale. A cap that gets offered as "optional, breaks the rule" stops being a rule. Users will take the suggestion, so leave it out.

How to apply it:
- **Count coverage for each lot, in each account.** Shares in the Roth and in the taxable account are separate lots, because a call can only be covered by shares in the same account.
- **Free shares = shares − 100 × short calls already open in that account.**
- **Maximum new contracts = floor(0.5 × free shares ÷ 100).**
- That means **a lot under 200 free shares can't take a covered call at all.** List those lots under "what to leave alone" with the reason "under 200 free shares". Don't recommend them, even as a small add-on.

## Process for "what would you sell Monday"

1. Get the earnings date for each **eligible** lot only (≥200 free shares, see above). Drop expirations after the report. Skip the earnings lookup entirely for ineligible lots.
2. Call `get_option_chains(underlying_symbol)` and pick the expiration 25–45 days out that falls before earnings.
3. **Estimate the target strike before fetching any contracts**, so you only need 3:
   `strike ≈ price × (1 + 0.8 × IV × √(days/365))`. This gives roughly delta 0.20.
   Use the IV from any option quote you already have on that underlying, or 0.35 for megacap tech, 0.50+ for high-beta names.
   Round to the chain's strike spacing. Then request the estimate, one strike below and one strike above, in a single parallel turn: `get_option_instruments(chain_symbol, expiration_dates, type="call", strike_price=X)`.
   Follow with one `get_option_quotes` call for all of them. Don't request unfiltered chains. They return 100+ rows.
4. Pick the strike closest to delta 0.20–0.25. The one above is the fallback.
5. **Check for big events with `search_web`**, only for the ticker(s) you're about to recommend (never every holding). Search once per ticker, e.g. `"<SYMBOL> stock news upcoming events <month year>"`, and look for anything between today and the expiration:
   - Scheduled: confirmed earnings date (cross-check the Robinhood date), ex-dividend date, FDA/PDUFA or trial readouts, investor or product days, shareholder votes, lock-up expiries, splits, index adds or deletes.
   - Unscheduled (last ~7 days): M&A talk, guidance changes, lawsuits or regulatory actions, analyst moves, management changes.
   - Market-wide: an FOMC or CPI date before expiration, noted once, not per ticker.

   Prefer primary or credible sources (company IR or press releases, SEC filings, Reuters, Bloomberg, WSJ, CNBC) and note each source's date. Then act on it:
   - An event that could gap the stock before expiration → pick an expiration before it, move to the higher fallback strike, or skip the name and say why.
   - **Ex-dividend before expiration** on a covered call → early assignment risk is high if the dividend exceeds the call's extrinsic value the day before. Flag it.
   - Nothing material → say "no major events found" in one line. News is context: it can flag a risk, but don't let headlines override the delta, earnings and coverage rules.
6. Size the trade using the coverage formula, in the best tax location.

## Output template (aim for ≤ ~750 words)

Start with a **Bottom line** of 2–4 lines: the trade, the premium, and why now. Then:

- **The trade:** account, sell to open N × SYMBOL $strike call, expiration, limit price (start at mid, set a floor near the bid), delta, chance of profit, premium in $, strike as % above the price, return over the period and annualized, and coverage (N×100 of the free shares = X%).
- **Why:** 2–3 bullets (earnings timing, tax location, coverage).
- **Events to note:** each event found before expiration with its date, its source and what you did about it, or "no major events found".
- **Management:** take-profit price, roll trigger, and an entry-timing note (sell calls on up days).
- **What to leave alone:** one compact table covering every other holding, with columns for lot, earnings date, and reason or next step. Reasons include reporting soon, under 200 free shares, or already capped.
- **Fallback:** the next strike up, in one line.
- If the trade can't be placed by the agent (wrong account), say so in one line.
