# helper_py — Python analysis utilities

This folder contains the Python helpers used by the analysis notebooks in
[`notebooks/`](../notebooks). They post-process and visualise the CSV/NPY
outputs written by the Julia PRAS simulations (see `iPASA.run_scenario`),
so they are intentionally kept in Python rather than ported to Julia:
they are plotting/reporting code built on pandas + matplotlib and are not
needed by the Julia package itself.

## Setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

The notebooks import this module with:

```python
import sys
sys.path.append("../helper_py")   # from inside notebooks/
from utility import get_shortfall_data, load_eue_shortfall, ...
```

## `utility.py` overview

Input loading (reads the CSVs written by `iPASA.run_scenario`):

| Function | Purpose |
| --- | --- |
| `load_eue_shortfall(area_code_region, scenario, IDIR)` | Load `shortfall_eue.csv` and map region codes to names |
| `get_shortfall_data(data_file, area_code_region)` | Load a `pras_results.json` shortfall export |
| `load_scenario_data(scenario, IDIR, area_code_region)` | Load all result files for one scenario |
| `flow_result(scenario, area_code_region, IDIR)` | Load `pras_flow_timeseries.csv` for a scenario |
| `load_flow_util(area_code_region, flow_file_name)` | Load flow/utilisation series |

Reshaping / statistics:

| Function | Purpose |
| --- | --- |
| `reg_load_gen(shortfall_data)` / `get_reg_load_gen(...)` | Regional load, generation and storage tables |
| `load_gen_summary(region_load)` | Regional summary statistics |
| `get_rel_data(...)` | Reliability data for a target region and window |
| `mean_shortfall_period(...)` | Mean shortfall over an event period |
| `seasonal_ppmm_stats(...)` | Seasonal NEUE (parts-per-million) statistics |
| `find_max_eue_regions(...)` | Regions with maximum EUE |
| `util_flow(pras_flow, area_code_region)` | Interface utilisation table |
| `get_data_simu(shortfall_data)` / `get_all_info(...)` | Case-study extraction helpers |
| `extract_load_gen_case_study(...)` | Load/generation snapshot for an event |

Plotting (matplotlib):

`plot_shortfall_eue`, `plot_yearly_rlg_v1`, `plot_flow`, `plot_EUE_lgs`,
`plot_metrics`, `plot_special_case`, `plot_mean_values`,
`plot_std_error`, `set_bold`.

## Notes

* The region code mapping used throughout is the same 15-region SNEM
  representation as the Julia package (`iPASA.AREA_CODE_REGION`).
* `utility.py` was migrated unchanged from the original research
  repository (`analysis/src/utility.py`); function signatures are stable
  with the notebooks committed in `notebooks/`.
