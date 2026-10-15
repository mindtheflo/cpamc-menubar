# Global quota forecasting

Forecasts apply to the **enabled fleet**, never to an individual licence. Codex and Claude cannot substitute for one another. Account bars and numbers remain actual measurements, not simulated balances.

## 1. Measure demand without inventing activity

For quota kind \(k\), aggregate each account’s quota increments into a pooled rate:

\[
r_k(t_i)=\sum_a \frac{u_{a,k}(t_i)-u_{a,k}(t_{i-1})}{t_i-t_{i-1}}.
\]

Time is in hours; usage is in **percentage points of one licence’s quota**. Two equal-plan licences have 200 points, not 100. Every increment uses the actual provider-observation timestamps.

A valid interval requires fresh, advancing readings on every enabled account, the same quota cycle, nondecreasing usage, and at most 15 minutes between observations. Crossing a reset discards that interval instead of inventing either negative demand or an assumed 100-point spend. Duplicate cached reads provide no evidence. A completely blocked fleet censors demand, so its flat usage is not evidence of inactivity. Historical changes can include direct clients using the same subscriptions; the quota endpoint does not identify the caller.

Only the current continuous fleet configuration is used. Disabled licences add neither demand nor capacity. Same-provider plans must be known and identical: percentages alone do not identify an exchange rate between different plans. Unknown/custom quota durations, stale readings and ambiguous availability cause abstention.

## 2. Two-timescale demand, with a local-time profile

The baseline uses at most the last 24 **comparable** observed hours, exponentially weighted with a six-hour half-life:

\[
b_k = \frac{\sum_i \Delta t_i 2^{-A_i/6}r_k(t_i)}{\sum_i \Delta t_i2^{-A_i/6}}.
\]

\(A_i\) is calendar age in comparable hours. Weekday age skips weekends; weekend age skips weekdays. This carries Friday into Monday without folding two inactive days into the weekday rate. Missing coverage never counts as observed time. At least six observed comparable hours are required, including 1.5 hours of coverage in the latest two hours and a valid observation within 15 minutes.

A fast estimate \(f_k\) uses the last two actual hours and a **30-minute** half-life. The local-hour profile uses up to 21 days, separating weekdays and weekends, normalized so older absolute activity does not replace the recent baseline. Sparse hourly estimates shrink toward that baseline; two observed hours of that local hour/day type give the profile full weight.

For \(h\) hours into the future, the central prediction is:

\[
\hat r_k(h)=\max\{0,\; b_k s_k(\text{local hour, day type})+(f_k-b_k)2^{-h/6}\}.
\]

The burst adjustment applies only to the same day type. A sudden acceleration therefore influences the rest of today, without persisting through the entire week or automatically overruling an observed quiet weekend. Activity need not follow fixed office hours. Intervals are assigned to calendar periods by their midpoint, so Sunday’s final quiet interval is not mislabelled as Monday activity.

A fully observed, repeatedly inactive weekend may borrow the latest weekday amplitude while applying its learned zero-weekend profile; that also preserves a nonzero forecast when work resumes Monday. A previously unseen weekend is **bracketed between zero activity and continued work**, not presumed inactive.

## 3. Demand bounds, not invented probability

Hourly blocks prevent frequent polling from masquerading as independent evidence. The symmetric uncertainty scale is the largest of:

- 25% of the baseline;
- half the observed hourly 90th–10th percentile rate spread;
- 25% of the fast/baseline disagreement.

The scale widens by \(1+0.1\sqrt{h/24}\) with forecast distance. Lower demand is clamped at zero. An unobserved change of day type has a zero lower bound and an upper bound covering continued current work.

These are **sensitivity bounds**. The percentile spread does not make this an empirically calibrated 80%, 90% or 95% prediction interval. No such accuracy percentage is shown. Real-world predictive coverage still needs prospective evaluation on collected observations.

## 4. Supply is a coupled renewal problem

An account has a vector of remaining balances \(q_{a,k}\), not independently transferable session and weekly pools. Its capacity for a global workload measured in rate-hours is

\[
c_a=\min_k \frac{q_{a,k}}{r_k},\qquad C=\sum_{a\text{ available}}c_a.
\]

A simulated workload of size \(x\) on account \(a\) consumes \(xr_k\) from **every** applicable limit. A licence with weekly room but no session room cannot rescue a different licence with session room but no weekly room. Cooldowns prevent allocation until they expire.

The simulator advances in steps no larger than five minutes, split exactly at known quota resets and cooldown ends. A reset restores that limit to 100 points; it does not refresh the other limit. An idle cycle starts on first simulated use and cannot bank repeated unused refills. Five-hour cycles can repeat many times before the weekly renewal. Forecast refills remain hypothetical; the measured UI does not grant quota until a fresh provider reading confirms it.

The horizon is at least 24 hours and extends through the latest currently reported weekly renewal (about one week). An idle weekly allowance with no reset timestamp gets a full-week horizon starting now, rather than silently truncating its forecast to one day. Two feasible allocations are checked: earliest-expiring capacity first, and proportional coupled-headroom allocation. A successful fluid allocation is a model-feasible schedule, not a guarantee of the proxy’s exact request routing, discrete request sizes, model mix or future provider policy.

### Why an orange prediction is stronger than a failed routing heuristic

A greedy allocation can fail even when another routing schedule succeeds. Orange therefore needs a separate necessary-condition violation. For each quota kind, construct an **optimistic** cumulative supply envelope:

\[
U_k(t)=\sum_a q_{a,k}(0)+100\sum_a N_{a,k}(t).
\]

\(N\) counts the earliest possible future renewals. This envelope even banks unused quota, so it is an upper bound on true supply. If cumulative **lower-bound** demand exceeds \(U_k(t)\) at any time, a shortage is unavoidable under that demand scenario regardless of allocation. A simulation failure without this certificate stays neutral.

## 5. Colour decisions

Define pressure as the maximum cumulative demand divided by optimistic cumulative capacity, checked along the timeline, including immediately before renewal events.

| Colour | Requirement |
| --- | --- |
| **Blue** | Upper-bound demand is feasible under both allocation policies and peak pressure stays below 50%. |
| **Green** | Upper-bound demand is feasible under both policies, and lower-bound peak pressure is at least 50%. |
| **Orange** | Even lower-bound demand breaches the optimistic supply envelope before renewal capacity can cover it. |
| **Grey / neutral** | Missing evidence, unknown comparable capacities, ambiguous availability, or scenarios cross a colour boundary. |
| **Red** | Actual measured exhaustion only; not a forecast. |

Provider bars use the joint forecast. Session/weekly icon bars use the corresponding joint-model constraint result; they never use spare Claude capacity to excuse a Codex bottleneck. All represented providers need a supported prediction before the combined bar takes a forecast colour. Partial readings always remain neutral. The UI shows a brief neutral reason rather than defaulting to green or warning orange from a low percentage alone.

## Validation boundary

Deterministic tests cover all three forecast colours, abstention, accelerated use, quiet weekends, Friday-to-Monday continuity, repeating sessions, staggered weekly renewals, incompatible per-account constraints, provider isolation, disabled accounts, cached reads, resets, sleep gaps, private local persistence and colour propagation. These checks prove the implemented model’s scenario behaviour, **not** its measured real-world forecast accuracy. A newly installed model has no historical demand evidence and starts neutral.
