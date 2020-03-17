using Documenter
using HAML

makedocs(
    sitename = "HAML",
    format = Documenter.HTML(),
    modules = [HAML],
    pages = [
        "Index"                 => "index.md",
        "Getting started"       => "getting-started.md",
        "Coming from Ruby HAML" => "fromruby.md",
        "Syntax reference"      => "syntax.md",
        "API reference"         => "api-reference.md",
    ],
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/tkluck/HAML.jl",
)
