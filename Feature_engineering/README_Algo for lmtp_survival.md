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
