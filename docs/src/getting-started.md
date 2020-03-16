# Getting started guide

## Installation

`HAML.jl` is a registered package and can be installed through the usual `]add HAML`
or `using Pkg; Pkg.add("HAML")`. It has minimal dependencies.

## In-line use

The easiest way to experiment with HAML are `haml"..."` strings. This
is an example of a [non-standard string literal](https://docs.julialang.org/en/v1/manual/strings/#non-standard-string-literals-1)
and it is implemented through the [`@haml_str`](@ref) macro. You use it like
this:

```@repl getting-started
using HAML

println(haml"%p Hello, world!")
```

HAML uses indentation to mark the opening and closing of tags. This makes it possible
to write HTML in a very concise way:

```@repl getting-started
link = "https://youtu.be/dQw4w9WgXcQ"

haml"""
!!! 5
%html
  %body
    %a(href=link) Hello, world!
""" |> print
```

## Syntax overview

 * Use `%` for tag name, `#` for the `id` attribute, `.` for the `class` attribute. Use
   named tuple syntax for other attributes. If `%` is omitted, we default to `div`:

```@repl getting-started
haml"""%a(href="/") Click me""" |> println

haml"""%a.nav(href="/") Click me too""" |> println

haml"""%a#homelink.nav(href="/") Home""" |> println

haml"""#navbar""" |> println

haml""".navitem""" |> println
```

 * Use indentation for nesting.

 * Use `-` for evaluating Julia code. Use `=` for including the result of evaluating
   Julia code:

```@repl getting-started
haml"%p= 2 + 2" |> println

haml"""
%ul
  - for i in 1:2
    %li= i
""" |> println
```

 * Use `$` for interpolation of Julia values into static content:

```@repl getting-started
haml"%p= 2 + 2" |> println

haml"""
%p
  Two and two make $(2 + 2)
  - difficulty = "easy"
  This is $(difficulty)!
""" |> println
```

## Using HAML templates from files

Use the [`includehaml`](@ref) function to include a HAML template from a file
and make it a function in a certain module.

```@repl getting-started
mktemp() do path, io
    write(io, raw"""
    %p
       Hello from this file! I am running in
       %i= @__MODULE__
       and I received the following parameters:
    %dl
      %dt foo
      %dd= $foo
      %dt bar
      %dd= $bar
    """)
    close(io)

    includehaml(Main, :my_first_template, path)
end

Main.my_first_template(foo=42, bar=43) |> print
```

Note how the keyword parameters are available through `$foo` and `$bar`.

There is also a [`render`](@ref) function which takes a file name and
immediately renders the result. However, we recommend using `includehaml` where
possible, at the top-level of your module, because Julia will pre-compile
the function in this case.
