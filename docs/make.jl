using Documenter
using TransportNetworkWelfare

makedocs(
    sitename="TransportNetworkWelfare.jl",
    modules=[TransportNetworkWelfare],
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://sfuchs-de.github.io/TransportNetworkWelfare.jl/",
        edit_link=nothing,
        repolink="https://github.com/sfuchs-de/TransportNetworkWelfare.jl",
    ),
    remotes=nothing,
    pages=[
        "Home" => "index.md",
        "Examples" => "examples.md",
        "Use your own data" => "own-data.md",
        "Model" => "model.md",
        "Urban commuting model" => "urban.md",
        "Data and configuration" => "data.md",
        "Outputs" => "outputs.md",
        "Welfare decomposition" => "decomposition.md",
        "RSUE replication" => "rsue.md",
        "Diagnostics" => "diagnostics.md",
        "API" => "reference/api.md",
    ],
    checkdocs=:none,
    warnonly=[:missing_docs],
)
