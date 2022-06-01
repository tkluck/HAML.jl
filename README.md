# HAML.jl

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://tkluck.github.io/HAML.jl/stable/)

HTML Abstract Markup Language for Julia. Inspired by [Ruby's HAML](http://haml.info/).

| **Build Status**        | **Test coverage**                              |
|:-----------------------:|:----------------------------------------------:|
| [![][c-i-img]][c-i-url] | [![Coverage Status][codecov-img]][codecov-url] |

## Synopsis

The easiest way to use HAML in Julia is in the form of the `haml""` macro.
Just write your HAML code in-line and it will expand to a string:

```julia
julia> using HAML

julia> link = "https://youtu.be/dQw4w9WgXcQ"

julia> haml"""
       %html
         %body
           %a(href=link) Hello, world!
       """ |> print
<html>
  <body>
    <a href='https://youtu.be/dQw4w9WgXcQ'>Hello, world!</a>
  </body>
</html>
```

It is also possible to store HAML in a file and execute it from there:

```julia
julia> write("/tmp/test.hamljl", """
       %html
          %body
             %a(href=\$link)= \$greeting
       """)
47

julia> render(stdout, "/tmp/test.hamljl", variables=(link=link, greeting="Hello, world!",))
<html>
   <body>
      <a href='https://youtu.be/dQw4w9WgXcQ'>Hello, world&#33;</a>
   </body>
</html>
```
In this case, note that input variables need to be quoted with a dollar sign `$`.
This distinguishes them from file-local variables.

## Syntax

If you are already familiar with Ruby-flavoured HAML, [read about the
differences here][fromruby]. If not, either use read the [getting started guide][gettingstarted]
or the [syntax reference][syntax].

[c-i-img]: https://github.com/tkluck/HAML.jl/workflows/CI/badge.svg
[c-i-url]: https://github.com/tkluck/HAML.jl/actions?query=workflow%3ACI

[codecov-img]: https://codecov.io/gh/tkluck/HAML.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/tkluck/HAML.jl

[fromruby]: https://tkluck.github.io/HAML.jl/stable/fromruby/
[gettingstarted]: https://tkluck.github.io/HAML.jl/stable/getting-started/
[syntax]: https://tkluck.github.io/HAML.jl/stable/syntax/
