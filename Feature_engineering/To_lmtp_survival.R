library(dplyr)
library(tidyr)

# -------------------------------------------------------------------------
# 0. Configuration: Define variable groups, priority hierarchies & time grid
# -------------------------------------------------------------------------
baseline_vars <- c("BEN_RES_DPT", "FDEP20_quint")

# Partition TDCs by aggregation rule (leave any unused vector as character(0))
tdc_cumul_vars    <- c("CumulAnx", "CumulGP", "CumulOtherMed", "CumulNonMed", "CumulPsych", "CumulOtherMeds")
tdc_first_vars    <- c()               # -> earliest value in month m
tdc_last_vars     <- c()               # -> latest value in month m
tdc_priority_vars <- c("Pregnant")     # -> highest-priority value in month m

# Define ordered priority levels (highest priority first) for each variable in tdc_priority_vars
priority_levels <- list(
  psy_meds = c(1, 0) # Example: 1 overrides 0 (or e.g. c("Hospital", "Specialist", "GP", "None"))
)

all_locf_tdc_vars <- c(tdc_first_vars, tdc_last_vars, tdc_priority_vars)
all_tdc_vars      <- c(tdc_cumul_vars, all_locf_tdc_vars)

month_len <- 30
n_months  <- 12

# Helper: pick the highest-priority non-NA value in x according to ordered vector `levels`
pick_priority <- function(x, levels) {
  x_clean <- x[!is.na(x)]
  if (length(x_clean) == 0L) return(x[1]) # preserves typed NA
  ranks <- match(x_clean, levels)
  if (all(is.na(ranks))) return(x_clean[1])
  x_clean[which.min(ranks)]
}

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
# 3A. Aggregate TDCs within each month m = 1..12 by rule type
# -------------------------------------------------------------------------
monthly_tdc <- long_sorted %>%
  mutate(m = as.integer(floor(.data$start / month_len)) + 1L) %>%
  filter(m >= 1L, m <= n_months) %>%
  group_by(BEN_IDT_ANO, m) %>%
  summarise(
    across(all_of(tdc_cumul_vars), ~ sum(.x, na.rm = TRUE)),
    across(all_of(tdc_first_vars), first),
    across(all_of(tdc_last_vars),  last),
    across(
      all_of(tdc_priority_vars),
      ~ pick_priority(.x, priority_levels[[cur_column()]])
    ),
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
  # Carry forward first/last/priority TDCs and active exposure A across quiet months
  fill(all_of(all_locf_tdc_vars), A, .direction = "down") %>%
  ungroup() %>%
  mutate(
    # Months with no visits have 0 utilization counts (do NOT carry forward Cumul* sums)
    across(all_of(tdc_cumul_vars), ~ replace_na(.x, 0)),
    is_at_risk = case_when(
      final_event > 0  ~ m <= event_month,
      final_event == 0 ~ m <= cens_month
    ),
    # Blank out L_m and A_m after terminal event or censoring
    across(all_of(all_tdc_vars), ~ if_else(is_at_risk, .x, NA)),
    A = if_else(is_at_risk, A, NA),
    # Cumulative absorbing outcome Y_m
    Y = case_when(
      final_event > 0 & m < event_month  ~ 0L,
      final_event > 0 & m >= event_month ~ as.integer(final_event),
      final_event == 0 & m <= cens_month ~ 0L,
      TRUE                               ~ NA_integer_
    )
  ) %>%
  select(BEN_IDT_ANO, all_of(baseline_vars), m, all_of(all_tdc_vars), A, Y) %>%
  # -----------------------------------------------------------------------
  # 5. Pivot wider in strict temporal block order: M1 -> M2 -> ... -> M12
  # -----------------------------------------------------------------------
  pivot_wider(
    id_cols     = c(BEN_IDT_ANO, all_of(baseline_vars)),
    names_from  = m,
    values_from = c(all_of(all_tdc_vars), A, Y),
    names_glue  = "{.value}_{m}",
    names_vary  = "slowest"
  )
