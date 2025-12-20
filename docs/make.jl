using Documenter
using SQLSketch

makedocs(; sitename = "SQLSketch.jl",
         format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true",
                                  canonical = "https://daikichiba9511.github.io/SQLSketch.jl",
                                  assets = String[]),
         modules = [SQLSketch],
         pages = ["Home" => "index.md",
                  "Getting Started" => "getting-started.md",
                  "Tutorial" => "tutorial.md",
                  "API Reference" => "api.md",
                  "Design" => "design.md"],
         repo = "https://github.com/daikichiba9511/SQLSketch.jl/blob/{commit}{path}#{line}",
         checkdocs = :none)

deploydocs(; repo = "github.com/daikichiba9511/SQLSketch.jl.git",
           devbranch = "main",
           push_preview = true)
