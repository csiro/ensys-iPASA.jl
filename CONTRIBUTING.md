# Contributing to iPASA.jl

Thanks for your interest in improving iPASA! Contributions of all kinds
are welcome: bug reports, documentation, tests, new features and data
corrections.

## Getting started

1. Fork and clone the repository.
2. Instantiate the environment: `julia --project -e 'using Pkg; Pkg.instantiate()'`.
3. Run the test suite before and after your changes:

   ```julia
   using Pkg; Pkg.test("iPASA")
   ```

   For quick iteration on non-simulation code you can skip the slow
   integration tests with `IPASA_TEST_SKIP_SYSTEM=true`.

## Pull request guidelines

- Open an issue first for substantial changes so the approach can be
  discussed.
- Keep PRs focused; separate refactoring from behaviour changes.
- Every new function needs a docstring describing arguments, behaviour
  and return values, and unit tests where practical.
- Follow the existing style: 4-space indentation, lowercase functions
  with underscores, a trailing `!` for mutating functions, `_` prefix
  for internal helpers.
- Use `@info`/`@warn`/`@error` logging rather than `println`, and throw
  `ArgumentError` with actionable messages for invalid input.
- Update `CHANGELOG.md` under an "Unreleased" heading.
- CI must pass (`Pkg.test`) before merge.

## Reporting issues

Please include:

- Julia version (`versioninfo()`) and iPASA version/commit,
- the scenario and script/function being run,
- the full error message and stack trace,
- whether the bundled or external data was used.

## Data contributions

Large traces (> 50 MB) should not be committed to git; document how to
regenerate them (see `notebooks/pre-processing_ISP_data.ipynb`) instead.

## Code of conduct

Be respectful and constructive. We follow the
[Julia Community Standards](https://julialang.org/community/standards/).
