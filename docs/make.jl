using Documenter
using TransportNetworkWelfare

makedocs(
    sitename="TransportNetworkWelfare.jl",
    modules=[TransportNetworkWelfare],
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", "false") == "true",
        edit_link=nothing,
        repolink="https://github.com/sfuchs-de/TransportNetworkWelfare.jl",
    ),
    remotes=nothing,
    pages=[
        "Home" => "index.md",
        "Model" => "model.md",
        "Data and configuration" => "data.md",
        "Welfare decomposition" => "decomposition.md",
        "RSUE replication" => "rsue.md",
        "Diagnostics" => "diagnostics.md",
        "API" => "reference/api.md",
    ],
    checkdocs=:none,
    warnonly=[:missing_docs],
)
