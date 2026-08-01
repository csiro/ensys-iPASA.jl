# iPASA.jl

*Integrated Projected Assessment of System Adequacy for the Australian National Electricity Market (NEM)*

[![Julia](https://img.shields.io/badge/julia-%E2%89%A5%201.10-9558B2?logo=julia)](https://julialang.org/)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE.md)
[![Status](https://img.shields.io/badge/status-research--grade-orange.svg)]()
[![CSIRO Energy](https://img.shields.io/badge/CSIRO-Energy-009e8d.svg)](https://www.csiro.au/en/research/technology-space/energy)
[![AR-PST](https://img.shields.io/badge/AR--PST-Stage%205-009e8d.svg)](https://www.csiro.au/en/research/technology-space/energy/electricity-transition/ar-pst)
[![CSIRO DAP](https://img.shields.io/badge/CSIRO-DAP-009e8d.svg)](https://doi.org/10.25919/h7py-3f46)
[![DOI](https://img.shields.io/badge/DOI-10.25919%2Fh7py--3f46-blue.svg)](https://doi.org/10.25919/h7py-3f46)

iPASA is a Julia package for projected assessment of system adequacy assessment of the NEM. It couples an open [Synthetic NEM](https://github.com/csiro-energy-systems/Synthetic-NEM-2000bus-Data) network model, clustered into 15 ISP sub-regions, with AEMO 2024 Integrated System Plan (ISP) data, and evaluates adequacy metrics (LOLE, EUE, NEUE) with sequential Monte Carlo simulation via [PRAS](https://github.com/NREL/PRAS). It also enables detailed production cost modelling based on sequential unit commitment and economic dispatch simulations, supporting comprehensive assessment of operational strategies and system performance. The system modelling is built on the [Sienna](https://www.nrel.gov/analysis/sienna.html) ecosystem ([PowerSystems.jl](https://github.com/NREL-Sienna/PowerSystems.jl), [PowerSimulations.jl](https://github.com/NREL-Sienna/PowerSimulations.jl)) and [PowerModels.jl](https://github.com/lanl-ansi/PowerModels.jl) data parsing.

## Scenarios

Four study horizons are supported, all derived from the ISP Step Change scenario:

| Scenario | Horizon | Resolution |
| --- | --- | --- |
| `ST` | Jul 2024 – Jun 2025 (1 year) | 30 min |
| `MT` | Jul 2024 – Jun 2030 (6 years) | 30 min |
| `LT` (`LT_BASE`, `LT_TYP`, `LT_BEST`, `LT_WORST`) | Jul 2024 – Jun 2044 (20 years) | 60 min |
| `SUM_ED` | Summer extreme days, 2024–2030 (Dec–Feb daily maxima) | 3-day sampling |

The `LT_*` variants select different step-change network cases (base / typical / best / worst outlooks).

## Installation

iPASA is not yet registered. Clone the repository and instantiate its environment:

```bash
git clone https://github.com/csiro-energy-systems/iPASA.jl.git
cd iPASA.jl
julia --project -e 'using Pkg; Pkg.instantiate()'
```

Requires Julia ≥ 1.10 (developed on 1.11). The Python analysis notebooks are optional; see [`helper_py/README.md`](helper_py/README.md).

## Quick start

```julia
using iPASA

# Optional: timestamped file logging
setup_logging("log/pras_simulation.log")

# Fast smoke run: short-term scenario, 5 Monte Carlo samples
out = run_scenario("ST"; samples = 5)

# Production run: long-term base case, 100 samples (slow — HPC recommended)
out = run_scenario("LT_BASE"; samples = 100)

out.results.shortfall   # PRAS ShortfallResult
out.gps                 # PRAS SystemModel
out.sys                 # PowerSystems System
```

Or from the command line:

```bash
julia --project --threads auto scripts/pras_simulation.jl ST 5        # smoke test
julia --project --threads auto scripts/pras_simulation.jl LT_BASE 100 # production
```

Results (shortfall EUE metrics, flow/utilisation time series, storage energy and generator availability samples) are written as CSV/NPY to `data/pras_metrics_output/shortfall_data/<SCENARIO>/`.

The pipeline can also be driven step by step:

```julia
sys, pm_data, storage_data = build_system(iPASA.default_case_file("ST"))
add_baseload!(sys)
add_future_generators!(sys, "ST")
add_future_storage!(sys, "ST")
add_retirement_status!(sys, "ST", joinpath(default_data_dir(), "sc_data", "future_gen_thermal_exp_pp.csv"), "gen")
add_retirement_status!(sys, "ST", joinpath(default_data_dir(), "sc_data", "future_storage_pp.csv"), "storage")
build_scenario_timeseries!(sys, "ST")

gps = generate_pras_model(sys)
apply_storage_timeseries!(gps, sys)
results = run_pras_assessment(gps; samples = 100, seed = 123)
```

## Architecture

The layout follows the conventions of PowerModels.jl:

```
iPASA.jl/
├── src/
│   ├── iPASA.jl              # module definition and exports
│   ├── core/                 # constants (regions, scenarios), logging
│   ├── io/                   # MATPOWER case parsing, component builders,
│   │                         #   system augmentation (future gen/storage)
│   ├── data/                 # ISP trace ingestion and time-series attachment
│   ├── prob/                 # problem specifications:
│   │   ├── pras.jl           #   PRAS adequacy assessment pipeline
│   │   └── production_cost.jl#   PowerSimulations unit-commitment runs
│   └── util/                 # result extraction, CSV/GIS exports, helpers
├── scripts/                  # CLI drivers + SLURM job script
├── data/
│   ├── config/               # PowerSystems descriptors, generator mapping
│   ├── sc_data/              # network cases (.m) and future gen/storage CSVs
│   ├── isp/                  # ISP scaled traces (input/output)
│   └── output/               # exported system tables (bus/line/GIS)
├── notebooks/                # Python pre-processing & analysis notebooks
├── helper_py/                # Python analysis utilities (pandas/matplotlib)
├── test/                     # unit + integration tests (Pkg.test)
└── docs/                     # Documenter.jl skeleton
```

Pipeline: **network case (.m)** → `build_system` → **augmentation** (`add_baseload!`, `add_future_generators!`, `add_future_storage!`, `add_retirement_status!`) → **traces** (`build_scenario_timeseries!`) → **PRAS translation** (`generate_pras_model`, `apply_storage_timeseries!`) → **Monte Carlo assessment** (`run_pras_assessment`) → **CSV/NPY outputs** → Python notebooks for visualisation.

## Data notes

* The 20-year LT trace (`2024_ISP_Step_Change_20yrs_scaled.csv`) is too large for git and is not bundled; regenerate it with `notebooks/pre-processing_ISP_data.ipynb`.
* The `LT_TYP` / `LT_BEST` / `LT_WORST` network cases are not bundled; if missing, `run_scenario` falls back to the base case with a warning.
* Raw AEMO ISP trace downloads (several GB) are required only for the pre-processing notebook.

## Testing

```julia
using Pkg; Pkg.test("iPASA")
```

The suite runs fast unit tests plus an integration test that builds the full SNEM system and runs a 2-sample PRAS assessment. Environment switches: `IPASA_TEST_SKIP_SYSTEM=true` skips the slow integration tests; `IPASA_TEST_SAMPLES=<n>` changes the Monte Carlo sample count (default 2 — production studies use ≥ 100 via the scripts).

## Citing iPASA

If you use iPASA in your research, please cite:

```bibtex
@misc{iPASA2026,
  title        = {iPASA.jl: Integrated Projected Assessment of System Adequacy for the Australian NEM},
  author       = {{Biswajit Bala, Ghulam Mohy-ud-din}},
  year         = {2026},
  howpublished = {\url{https://github.com/csiro-internal/ensys-iPASA.jl}}
}
```

Please also cite the underlying tools: PRAS ([Stephen et al., 2021](https://doi.org/10.11578/dc.20190814.1)).


## Development

Lead developer: Mr Bala Biswajit (Senior Engineer, Energy Systems Transition, Energy, CSIRO)  
Co-developer: Dr Ghulam Mohy-ud-din (Senior Power System Research Engineer, Energy Systems Transition, Energy, CSIRO)

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

BSD 3-Clause — see [LICENSE](LICENSE).
