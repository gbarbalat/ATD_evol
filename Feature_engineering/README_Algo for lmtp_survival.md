# Longitudinal-to-Wide Discrete-Time Transformation ($M_0 \rightarrow M_{12}$)

This document specifies the algorithm and R implementation to transform a multi-row longitudinal healthcare dataset (e.g., French SNDS antidepressant trajectories) into a **one-row-per-participant wide discrete-time dataset** suitable for **Longitudinal Targeted Maximum Likelihood Estimation (`ltmle`)**, **sequential G-computation**, or **pooled competing-risks modeling**.

---

## 1. Input & Output Data Structures

### Input Table (`df` — Long Format, Multiple Rows per Participant)
| Variable | Type | Role & Temporal Timing |
| :--- | :--- | :--- |
| `BEN_IDT_ANO` | ID | Unique participant identifier. |
| `Baseline_Vars` | Fixed | Time-invariant covariates (constant across all rows for a given participant). |
| `start` | Numeric (days) | Start day of the dispensing/observation interval (coincident with `PSP_SPE_COD`). |
| `stop` | Numeric (days) | End day of the interval (coincident with `event_num`). |
| `TDC` | Time-varying | Time-dependent covariates measured prior to `start`, classified into four aggregation types (`cumul`, `first`, `last`, `priority`). |
| `PSP_SPE_COD` | Time-varying | Time-dependent exposure (prescriber specialty) assigned at `start`. |
| `event_num` | Integer | Event status at `stop`: `0` = censored / event-free, `1` = primary event, `2+` = competing event. |

### Output Table (`wide_ltmle_df` — Wide Format, One Row per Participant)
Follows the strict causal ordering across twelve 30-day windows ($m = 1, \dots, 12$, where month $m$ covers $[30(m-1), 30m)$ ending at day $30m$):

$$M_0 \longrightarrow (L_1, A_1, Y_1) \longrightarrow (L_2, A_2, Y_2) \longrightarrow \dots \longrightarrow (L_{12}, A_{12}, Y_{12})$$

* **$M_0$ (`[Baseline_Vars]`):** Time-invariant baseline covariates.
* **$L_m$ (`[TDC_m]`):** Aggregated time-dependent confounders for month $m$.
* **$A_m$ (`A_m`):** Dominant exposure (`PSP_SPE_COD`) during month $m$.
* **$Y_m$ (`Y_m`):** Cumulative absorbing outcome status at day $30m$ (`0` = event-free, `1` = primary event, `2+` = competing event, `NA` = right-censored prior to day $30m$).

---

## 2. Step-by-Step Algorithm

### Step 0: Partition Time-Dependent Covariates (`TDC`) by Aggregation & Imputation Rule
Before processing, assign every time-dependent covariate to one of four explicit buckets:

| TDC Bucket | Within-Month Aggregation ($m$) | Quiet-Month Imputation (No Rows in $m$) | Epidemiological Use Case |
| :--- | :--- | :--- | :--- |
| **`tdc_cumul_vars`** | `sum(..., na.rm = TRUE)` | **Zero-fill (`0`)** | Healthcare encounter/utilization counts (`CumulGP`, `CumulPsych`, etc.). |
| **`tdc_first_vars`** | `first()` (earliest row in $m$) | **LOCF** (`fill(..., .direction = "down")`) | Pre-exposure clinical state entering month $m$ (strictly preserves $L_m \prec A_m$). |
| **`tdc_last_vars`** | `last()` (latest row in $m$) | **LOCF** (`fill(..., .direction = "down")`) | Most up-to-date clinical/regimen state leaving month $m$. |
| **`tdc_priority_vars`** | Highest-ranked value in an ordered priority hierarchy | **LOCF** (`fill(..., .direction = "down")`) | Categorical/ordinal severity or care-setting hierarchies (e.g., `"Inpatient" > "Outpatient" > "None"` or `"Psychiatrist" > "GP" > "None"`). |

### Step 1: Sort & Extract Subject-Level Baseline ($M_0$) and Terminal Follow-Up
1. Sort all rows by `BEN_IDT_ANO`, `start`, and `stop`.
2. For each participant (`BEN_IDT_ANO`):
   * Extract **$M_0$** from their baseline covariates.
   * Identify final follow-up time $T_{\text{end}} = \max(\text{stop})$ and terminal outcome $E_{\text{end}}$ (`event_num` on the final row).
   * Compute the terminal month boundary:
     * **If an event occurred ($E_{\text{end}} > 0$):**
       $$k_{\text{event}} = \max\left(1, \left\lceil \frac{T_{\text{end}}}{30} \right\rceil\right)$$
     * **If right-censored ($E_{\text{end}} = 0$):**
       $$k_{\text{cens}} = \left\lfloor \frac{T_{\text{end}}}{30} \right\rfloor$$

### Step 2: Collapse Multiple Rows Within Each Month $m \in \{1, \dots, 12\}$
1. **Time-Dependent Covariates ($L_m$):**
   * Assign each row to month $m = \lfloor \text{start}/30 \rfloor + 1$.
   * Within `(BEN_IDT_ANO, m)`:
     * Sum `tdc_cumul_vars`.
     * Take `first()` for `tdc_first_vars`.
     * Take `last()` for `tdc_last_vars`.
     * For each variable in `tdc_priority_vars`, select the value appearing earliest in its user-defined priority vector `priority_levels[[var]]` (e.g., `match(x, levels)` minimized; if `priority_levels` is not supplied for a numeric binary indicator, defaults to `max()`).
2. **Time-Dependent Exposure ($A_m =$ `PSP_SPE_COD`):**
   * Compute the exact **overlap days** of every dispensing interval `[start, stop]` with the month window $[30(m-1), 30m)$:
     $$\text{overlap}_{m} = \max\Big(0,\; \min(\text{stop}, 30m) - \max(\text{start}, 30(m-1))\Big)$$
   * Sum `overlap_m` by `PSP_SPE_COD` within `(BEN_IDT_ANO, m)` and assign the `PSP_SPE_COD` with the **largest cumulative covered duration** in that month (breaking ties using the most recent `start`).

### Step 3: Impute Quiet Months (Zero-Fill vs. LOCF)
Expand each participant to a complete grid of $m = 1, \dots, 12$ and handle months with no new dispensing:
* **`tdc_cumul_vars`:** Set missing months to **`0`** (do **not** carry counts forward, which would artificially inflate utilization).
* **`tdc_first_vars`, `tdc_last_vars`, `tdc_priority_vars`, and Exposure ($A_m$):** Apply **Last Observation Carried Forward (LOCF)** from month $m-1$ to preserve the active regimen/clinical state across months without a new dispensing.

### Step 4: Enforce Absorbing Outcome ($Y_m$) and Post-Event / Censoring Masking
For each participant and month $m \in \{1, \dots, 12\}$:

| Participant Status | Month Condition | Covariates ($L_m$) & Exposure ($A_m$) | Outcome ($Y_m$) |
| :--- | :--- | :--- | :--- |
| **Event occurred** ($E_{\text{end}} > 0$) | $m < k_{\text{event}}$ | Populated (at risk) | `0` |
| **Event occurred** ($E_{\text{end}} > 0$) | $m = k_{\text{event}}$ | Populated (active prior to event) | $E_{\text{end}}$ (`1`, `2`, ...) |
| **Event occurred** ($E_{\text{end}} > 0$) | $m > k_{\text{event}}$ | `NA` (no longer at risk) | $E_{\text{end}}$ (absorbing state carried forward) |
| **Right-censored** ($E_{\text{end}} = 0$) | $m \le k_{\text{cens}}$ | Populated (observed event-free) | `0` |
| **Right-censored** ($E_{\text{end}} = 0$) | $m > k_{\text{cens}}$ | `NA` (censored) | `NA` |

### Step 5: Pivot to Wide Block Format
Reshape to one row per `BEN_IDT_ANO` with columns ordered strictly by causal block:  
`BEN_IDT_ANO`, `[Baseline_Vars]`, `[TDC_1, A_1, Y_1]`, `[TDC_2, A_2, Y_2]`, ..., `[TDC_12, A_12, Y_12]`.
