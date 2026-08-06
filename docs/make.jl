using Documenter, iPASA

makedocs(
    modules = [iPASA],
    sitename = "iPASA.jl",
    authors = "Biswajit Bala, Ghulam Mohy-ud-din",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://csiro-internal.github.io/ensys-iPASA.jl",
    ),
    pages = [
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
    warnonly = true,
)

deploydocs(
    repo = "github.com/csiro-internal/ensys-iPASA.jl.git",
    devbranch = "main",
    push_preview = true,
)
