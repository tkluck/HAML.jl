# HAML.jl

HTML Abstract Markup Language for Julia. Inspired by [Ruby's HAML](http://haml.info/).

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

We don't have a syntax reference for `HAML.jl` yet. It mostly follows
[Ruby's syntax document](http://haml.info/docs/yardoc/file.REFERENCE.html) with
the following exceptions:

 - use named tuple syntax for attributes
 - use `:include` for including `.hamljl` files.

 See the [test cases](test/runtests.jl) for examples.
