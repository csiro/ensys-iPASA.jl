# Notebooks

Jupyter notebooks for data preparation and result analysis. The Julia
simulations themselves are run with the scripts in [`scripts/`](../scripts);
these notebooks sit before (pre-processing) and after (analysis) that step.

| Notebook | Kernel | Purpose |
| --- | --- | --- |
| `pre-processing_ISP_data.ipynb` | Python | Build the scaled ISP Step Change demand/solar/wind traces from the raw AEMO 2024 ISP trace downloads (writes the CSVs in `data/isp/output`) |
| `pras_simulation_analysis.ipynb` | Python | Visualise and analyse PRAS shortfall/EUE results (ST/MT scenarios) |
| `pras_simulation_SC_LT_analysis.ipynb` | Python | Long-term (20-year) Step Change scenario analysis, seasonal NEUE statistics |
| `power_simulation_res.ipynb` | Python | Production-cost simulation results, network/GIS plots |

The Julia notebook workflow of the original repository
(`system_pras_simulation_jl.ipynb`) is superseded by the package API —
see the Quick Start in the top-level [README](../README.md).

## Setup

```bash
pip install -r ../helper_py/requirements.txt
jupyter lab
```

## Path notes (repository reorganisation)

These notebooks were migrated unchanged from the original research
repository, which used different relative paths. When running them from
this folder, adjust:

* `sys.path.append("src")` → `sys.path.append("../helper_py")`
* PRAS metrics input dir: results are now written to
  `../data/pras_metrics_output/shortfall_data/<SCENARIO>` by default
  (or wherever `IPASA_OUTPUT_DIR` points).
* ISP trace output dir: `../data/isp/output` (was
  `ISP_data_processing/data/output`); bus info input is
  `../data/isp/input/nem_bus_info.csv`.
* `pre-processing_ISP_data.ipynb` additionally expects the raw AEMO 2024
  ISP trace download (several GB, not included in this repository); set
  `scenario_dem_path` / `scenario_ren_path` to your local copy.

The 20-year LT trace `2024_ISP_Step_Change_20yrs_scaled.csv` is not
committed (too large for git); regenerate it with
`pre-processing_ISP_data.ipynb` before running LT scenarios.
