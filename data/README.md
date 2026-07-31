# Data

Input data bundled with iPASA.jl.

| Folder | Contents |
| --- | --- |
| `config/` | `power_system_structs.json` (PowerSystems struct validation descriptors) and `generator_mapping.yaml` (fuel/type → device-type mapping used when parsing the MATPOWER cases) |
| `sc_data/` | SNEM network cases (`.m`, MATPOWER format with HVDC and storage extensions) and future generation/storage/base-load CSVs for the ISP Step Change scenarios |
| `isp/input/` | NEM bus information used by the pre-processing notebook |
| `isp/output/` | Scaled ISP Step Change demand/solar/wind/hydro traces produced by `notebooks/pre-processing_ISP_data.ipynb` |
| `output/` | Exported system tables (bus/line/GIS geometries, base-case summaries) produced by `save_system_snapshot` and friends |

Generated simulation results are written to
`data/pras_metrics_output/shortfall_data/<SCENARIO>/` (git-ignored).

## Network cases (`sc_data`)

| File | Purpose |
| --- | --- |
| `snem_step_change_base_case_2044-final.m` | LT base case (also used for ST/MT/SUM_ED) |
| `snem2000_v2.m` | SNEM2000 case carrying bus coordinates for GIS exports |
| `snem2000dcline_Oct2025.m`, `nw_2044_v1.m`, `nw_2044_prod_v1.m` | Development/production network variants |

Not bundled (regenerate or obtain separately):

* `2024_ISP_Step_Change_20yrs_scaled.csv` — 20-year LT trace (too large
  for git; regenerate with the pre-processing notebook);
* `snem_step_change_typical_case_2044.m`, `..._best_...`, `..._worst_...`
  — LT variant cases (`run_scenario` falls back to the base case with a
  warning when missing).
