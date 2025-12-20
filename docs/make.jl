using Documenter
using SQLSketch

makedocs(
    sitename = "SQLSketch.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    modules = [SQLSketch],
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Tutorial" => "tutorial.md",
        "API Reference" => "api.md",
        "Design" => "design.md",
    ],
    remotes = nothing,  # Disable remote source links for local development
    checkdocs = :none   # Don't check for missing docstrings
)
