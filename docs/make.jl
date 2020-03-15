using Documenter
using HAML

makedocs(
    sitename = "HAML",
    format = Documenter.HTML(),
    modules = [HAML],
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/tkluck/HAML.jl",
)
