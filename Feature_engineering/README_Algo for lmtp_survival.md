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
| `TDC` (`Cumul*`, state flags) | Time-varying | Time-dependent covariates measured prior to `start`. |
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
When a participant has multiple dispensings inside the same 30-day window $[30(m-1), 30m)$, aggregate variables by type rather than dropping rows:

1. **Utilization / Count Covariates (`Cumul*` variables):**
   * Assign each row to month $m = \lfloor \text{start}/30 \rfloor + 1$.
   * Take the **sum** (`sum(..., na.rm = TRUE)`) across all rows starting in month $m$.
2. **State / Binary Covariates (non-`Cumul` TDCs, e.g., `psy_meds`):**
   * Take `max(..., na.rm = TRUE)` across rows in month $m$ to capture any co-medication/event presence during that month (or `first()` if strictly restricting to pre-dispensing status at month entry).
3. **Time-Dependent Exposure ($A_m =$ `PSP_SPE_COD`):**
   * Compute the exact **overlap days** of every dispensing interval `[start, stop]` with the month window $[30(m-1), 30m)$:
     $$\text{overlap}_{m} = \max\Big(0,\; \min(\text{stop}, 30m) - \max(\text{start}, 30(m-1))\Big)$$
   * Sum `overlap_m` by `PSP_SPE_COD` within `(BEN_IDT_ANO, m)` and assign the `PSP_SPE_COD` with the **largest cumulative covered duration** in that month (breaking ties using the most recent `start`).

### Step 3: Impute Quiet Months (Zero-Fill vs. LOCF)
Expand each participant to a complete grid of $m = 1, \dots, 12$ and handle months with no new dispensing:
* **`Cumul*` count variables:** Set missing months to **`0`** (do **not** carry counts forward, which would artificially inflate utilization).
* **State TDCs & Exposure ($A_m$):** Apply **Last Observation Carried Forward (LOCF)** from month $m-1$ to preserve the active regimen/clinical state across months without a new dispensing.

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

---

## 3. R Implementation (`dplyr` / `tidyr`)

```r
library(dplyr)
library(tidyr)

# -------------------------------------------------------------------------
# 0. Configuration: Define variable groups and time grid
# -------------------------------------------------------------------------
baseline_vars  <- c("BEN_RES_DPT", "FDEP20_quint", "Pregnant")
cumul_vars     <- c("CumulAnx", "CumulGP", "CumulOtherMed", "CumulNonMed", "CumulPsych", "CumulOtherMeds")
state_tdc_vars <- c("psy_meds") # Add any other non-Cumul state/binary TDCs here
month_len      <- 30
n_months       <- 12

# -------------------------------------------------------------------------
# 1. Sort longitudinal table (use .data$stop to avoid base::stop collision)
# -------------------------------------------------------------------------
long_sorted <- df %>%
  arrange(BEN_IDT_ANO, .data$start, .data$stop)

# -------------------------------------------------------------------------
# 2. Extract M0 (baseline) and subject-level terminal time/event
# -------------------------------------------------------------------------
subject_summary <- long_sorted %>%
  group_by(BEN_IDT_ANO) %>%
  summarise(
    across(all_of(baseline_vars), first),
    final_stop  = max(.data$stop, na.rm = TRUE),
    final_event = last(event_num),
    .groups = "drop"
  ) %>%
  mutate(
    event_month = if_else(
      final_event > 0,
      pmax(1L, as.integer(ceiling(final_stop / month_len))),
      NA_integer_
    ),
    cens_month = if_else(
      final_event == 0,
      as.integer(floor(final_stop / month_len)),
      NA_integer_
    )
  )

# -------------------------------------------------------------------------
# 3A. Aggregate TDCs within each month m = 1..12
# -------------------------------------------------------------------------
monthly_tdc <- long_sorted %>%
  mutate(m = as.integer(floor(.data$start / month_len)) + 1L) %>%
  filter(m >= 1L, m <= n_months) %>%
  group_by(BEN_IDT_ANO, m) %>%
  summarise(
    # Sum utilization/count variables within the month
    across(all_of(cumul_vars), ~ sum(.x, na.rm = TRUE)),
    # For binary/state TDCs: take max (any occurrence in month) or first() (entry state)
    across(all_of(state_tdc_vars), ~ max(.x, na.rm = TRUE)),
    .groups = "drop"
  )

# -------------------------------------------------------------------------
# 3B. Determine dominant exposure A_m (longest covered days in [30*(m-1), 30*m))
# -------------------------------------------------------------------------
monthly_exp <- long_sorted %>%
  crossing(m = 1:n_months) %>%
  mutate(
    win_start    = (m - 1L) * month_len,
    win_end      = m * month_len,
    overlap_days = pmax(0, pmin(.data$stop, win_end) - pmax(.data$start, win_start))
  ) %>%
  filter(overlap_days > 0) %>%
  group_by(BEN_IDT_ANO, m, PSP_SPE_COD) %>%
  summarise(
    tot_days   = sum(overlap_days, na.rm = TRUE),
    last_start = max(.data$start, na.rm = TRUE),
    .groups    = "drop_last"
  ) %>%
  arrange(desc(tot_days), desc(last_start), .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(BEN_IDT_ANO, m, A = PSP_SPE_COD)

# -------------------------------------------------------------------------
# 4. Assemble full 1..12 grid, apply LOCF / zero-fill, and enforce Y_m rules
# -------------------------------------------------------------------------
wide_ltmle_df <- subject_summary %>%
  crossing(m = 1:n_months) %>%
  left_join(monthly_tdc, by = c("BEN_IDT_ANO", "m")) %>%
  left_join(monthly_exp, by = c("BEN_IDT_ANO", "m")) %>%
  group_by(BEN_IDT_ANO) %>%
  arrange(BEN_IDT_ANO, m) %>%
  # Carry forward clinical state TDCs and active exposure A across quiet months
  fill(all_of(state_tdc_vars), A, .direction = "down") %>%
  ungroup() %>%
  mutate(
    # Months with no visits have 0 utilization counts (do NOT carry forward Cumul* sums)
    across(all_of(cumul_vars), ~ replace_na(.x, 0)),
    is_at_risk = case_when(
      final_event > 0  ~ m <= event_month,
      final_event == 0 ~ m <= cens_month
    ),
    # Blank out L_m and A_m after terminal event or censoring
    across(all_of(c(cumul_vars, state_tdc_vars)), ~ if_else(is_at_risk, .x, NA)),
    A = if_else(is_at_risk, A, NA),
    # Cumulative absorbing outcome Y_m
    Y = case_when(
      final_event > 0 & m < event_month  ~ 0L,
      final_event > 0 & m >= event_month ~ as.integer(final_event),
      final_event == 0 & m <= cens_month ~ 0L,
      TRUE                               ~ NA_integer_
    )
  ) %>%
  select(BEN_IDT_ANO, all_of(baseline_vars), m, all_of(cumul_vars), all_of(state_tdc_vars), A, Y) %>%
  # -----------------------------------------------------------------------
  # 5. Pivot wider in strict temporal block order: M1 -> M2 -> ... -> M12
  # -----------------------------------------------------------------------
  pivot_wider(
    id_cols     = c(BEN_IDT_ANO, all_of(baseline_vars)),
    names_from  = m,
    values_from = c(all_of(cumul_vars), all_of(state_tdc_vars), A, Y),
    names_glue  = "{.value}_{m}",
    names_vary  = "slowest"
  )

# Longitudinal-to-Discrete-Time Wide Transformation ($M_0 \rightarrow M_{12}$)

This pipeline transforms a multi-row longitudinal dataset (`BEN_IDT_ANO`, baseline covariates, time-dependent covariates `TDC`, time-dependent exposure `PSP_SPE_COD`, interval boundaries `start`/`stop`, and competing-risk outcome `event_num`) into a **one-row-per-participant discrete-time wide table** suitable for LTMLE, sequential G-computation, or pooled discrete-time survival models.

## Causal Structure & Temporal Ordering

To preserve the strict causal ordering:

$$M_0 \longrightarrow (L_1, A_1, Y_1) \longrightarrow (L_2, A_2, Y_2) \longrightarrow \dots \longrightarrow (L_{12}, A_{12}, Y_{12})$$

where:
- **$M_0$**: Time-fixed baseline covariates (`BEN_IDT_ANO` + baseline variables)
- **$L_m$ (`TDC_m`)**: Time-dependent covariates measured prior to exposure in month $m$
- **$A_m$ (`A_m` / `PSP_SPE_COD`)**: Time-dependent exposure assigned during month $m$
- **$Y_m$**: Cumulative outcome status at the end of month $m$ ($t_m = 30m$)

Each monthly block $M_m$ ($m \in \{1, \dots, 12\}$) covers the 30-day window $[30(m-1), 30m)$ ending at day $t_m = 30m$.

---

## Step-by-Step Algorithm

### 1. Sort & Extract Subject-Level Baseline ($M_0$) and Terminal Outcome
- Sort the longitudinal dataset by `BEN_IDT_ANO`, `start`, and `stop`.
- For each participant (`BEN_IDT_ANO`):
  - **Baseline ($M_0$)**: Extract the time-invariant baseline covariates from the participant's first row.
  - **Terminal Follow-Up**: Extract final follow-up time $T_{\text{end}} = \max(\text{stop})$ and final outcome $E_{\text{end}}$ (`event_num` at $T_{\text{end}}$).
  - **Terminal Month Index**:
    - If $E_{\text{end}} > 0$ (primary event `1` or competing event `2+` occurred):

      $$k_{\text{event}} = \max\left(1, \left\lceil \frac{T_{\text{end}}}{30} \right\rceil\right)$$

    - If $E_{\text{end}} = 0$ (right-censored without an event):

      $$k_{\text{cens}} = \left\lfloor \frac{T_{\text{end}}}{30} \right\rfloor$$

### 2. Map Longitudinal Rows onto Monthly Grids ($m = 1, \dots, 12$)
- Each longitudinal row represents a covariate/exposure update initiated at `start` (with `TDC` measured prior to `start` and `PSP_SPE_COD` assigned at `start`).
- Assign each row to month:

  $$m_{\text{start}} = \left\lfloor \frac{\text{start}}{30} \right\rfloor + 1$$

  *(e.g., `start = 0` maps to $M_1$; `start = 30` maps to $M_2$).*
- **Multiple rows within the same month $m$**: Keep `(TDC, PSP_SPE_COD)` paired from the **same** row so temporal precedence ($L_m \prec A_m$) is preserved—selecting either the last dispensing row in $[30(m-1), 30m)$ or the first dispensing row depending on the target estimand.
- **Months without a new dispensing (LOCF)**: If a participant remains under observation in month $m$ ($m \le k_{\text{event}}$ or $m \le k_{\text{cens}}$) with no new dispensing in $[30(m-1), 30m)$, carry forward `(TDC, PSP_SPE_COD)` from the most recent prior interval (`start < 30m`).

### 3. Assign Cumulative Outcome $Y_m$ & Enforce Absorbing / Censoring Rules

| Participant Status | Month Condition | $L_m$ (`TDC_m`) & $A_m$ (`A_m`) | Outcome $Y_m$ |
| :--- | :--- | :--- | :--- |
| **Event occurred** ($E_{\text{end}} > 0$) | $m < k_{\text{event}}$ | Populated | `0` |
| **Event occurred** ($E_{\text{end}} > 0$) | $m = k_{\text{event}}$ | Populated (active prior to $T_{\text{end}}$) | $E_{\text{end}}$ (`1`, `2`, ...) |
| **Event occurred** ($E_{\text{end}} > 0$) | $m > k_{\text{event}}$ | `NA` (no longer at risk) | $E_{\text{end}}$ (absorbing state carried forward) |
| **Right-censored** ($E_{\text{end}} = 0$) | $m \le k_{\text{cens}}$ | Populated | `0` |
| **Right-censored** ($E_{\text{end}} = 0$) | $m > k_{\text{cens}}$ | `NA` | `NA` |

### 4. Pivot to Wide Format in Strict Block Order
Arrange output columns sequentially by temporal block:

```text
BEN_IDT_ANO | [baseline_vars] | TDC_1, A_1, Y_1 | TDC_2, A_2, Y_2 | ... | TDC_12, A_12, Y_12
