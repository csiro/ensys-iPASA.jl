using Documenter, iPASA

makedocs(
    modules = [iPASA],
    sitename = "iPASA.jl",
    authors = "CSIRO Energy Systems",
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    pages = [
        "Home" => "index.md",
        "API Reference" => "api.md",
    ],
    warnonly = true,
)

deploydocs(repo = "github.com/csiro-energy-systems/iPASA.jl.git")
