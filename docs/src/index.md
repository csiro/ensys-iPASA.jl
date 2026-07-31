# iPASA.jl

Integrated Probabilistic Assessment of System Adequacy for the
Australian National Electricity Market (NEM).

iPASA couples a 15-region clustered SNEM AC/DC network model with AEMO
2024 ISP *Step Change* traces and evaluates resource-adequacy metrics
(LOLE, EUE, NEUE) via sequential Monte Carlo simulation with PRAS.

See the repository [README](https://github.com/csiro-energy-systems/iPASA.jl)
for installation and quick-start instructions.

## Pipeline

1. [`build_system`](@ref) — parse the MATPOWER network case.
2. [`add_baseload!`](@ref), [`add_future_generators!`](@ref),
   [`add_future_storage!`](@ref), [`add_retirement_status!`](@ref) —
   scenario augmentation.
3. [`build_scenario_timeseries!`](@ref) — attach ISP traces.
4. [`generate_pras_model`](@ref), [`apply_storage_timeseries!`](@ref) —
   PRAS translation.
5. [`run_pras_assessment`](@ref) — sequential Monte Carlo assessment.

Or all at once with [`run_scenario`](@ref).
