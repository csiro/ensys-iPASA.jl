# API Reference

## Pipeline

```@docs
run_scenario
build_system
add_baseload!
add_future_generators!
add_future_storage!
add_retirement_status!
build_scenario_timeseries!
generate_pras_model
apply_storage_timeseries!
run_pras_assessment
default_ra_template
```

## Time series utilities

```@docs
load_scaled_data
normalise_data
normalize_to_range
build_time_series
```

## Production-cost simulation

```@docs
get_uc_template
formulate_decision_model
run_production_simulation
extract_simulation_data
```

## Results and exports

```@docs
save_shortfall_eue_metrics
save_shortfall_time_series_data
save_generator_storage_data
save_pras_lines_info
save_line_capacity
get_pras_lines
get_pras_regional_loads
flow_utilisation
save_system_snapshot
```

## Helpers

```@docs
setup_logging
default_data_dir
scenario_class
stringify_keys
find_region
```
