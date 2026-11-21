library(dplyr)
library(tidyr)

# Define variable groups
baseline_vars  <- c("BEN_RES_DPT", "FDEP20_quint", "Pregnant")
cumul_vars     <- c("CumulAnx", "CumulGP", "CumulOtherMed", "CumulNonMed", "CumulPsych", "CumulOtherMeds")
state_tdc_vars <- c("psy_meds") # add any non-Cumul TDCs here
month_len      <- 30
n_months       <- 12

# 1. Sort longitudinal table
long_sorted <- df %>%
  arrange(BEN_IDT_ANO, .data$start, .data$stop)

# 2. Extract M0 (baseline) and subject-level terminal time/event
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

# 3A. Aggregate TDCs within each month m = 1..12
monthly_tdc <- long_sorted %>%
  mutate(m = as.integer(floor(.data$start / month_len)) + 1L) %>%
  filter(m >= 1L, m <= n_months) %>%
  group_by(BEN_IDT_ANO, m) %>%
  summarise(
    # Sum utilization/count variables within the month
    across(all_of(cumul_vars), ~ sum(.x, na.rm = TRUE)),
    # For binary/state TDCs: take max (any occurrence in month) or first() (state entering month)
    across(all_of(state_tdc_vars), ~ max(.x, na.rm = TRUE)),
    .groups = "drop"
  )

# 3B. Determine dominant exposure A_m (PSP_SPE_COD with longest covered days inside [30*(m-1), 30*m))
#     (Alternative: replace 3B with `summarise(A = last(PSP_SPE_COD))` or a specialist-priority rule)
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
  # Pick PSP_SPE_COD with most covered days in month m (tie-break by most recent start)
  arrange(desc(tot_days), desc(last_start), .by_group = TRUE) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(BEN_IDT_ANO, m, A = PSP_SPE_COD)

# 4. Assemble full 1..12 monthly grid, apply type-specific LOCF / zero-fill, and enforce Y_m
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
  pivot_wider(
    id_cols     = c(BEN_IDT_ANO, all_of(baseline_vars)),
    names_from  = m,
    values_from = c(all_of(cumul_vars), all_of(state_tdc_vars), A, Y),
    names_glue  = "{.value}_{m}",
    names_vary  = "slowest"
  )
