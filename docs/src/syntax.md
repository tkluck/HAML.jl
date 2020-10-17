# Syntax reference

```@setup syntax-reference
using HAML
```

## Tags, nesting, and whitespace

Lines starting with `%` indicate a tag, possibly with content.
The content can either be in-line or in an indented block following.

Examples:

```@repl syntax-reference
haml"%p" |> println

haml"%p Hello, world!" |> println

haml"""
%div
  %p First paragraph
  %p Second paragraph
""" |> println
```

Just `%` on its own is equivalent to `%div`:

```@repl syntax-reference
haml"""
%
  %p First paragraph
  %p Second paragraph
""" |> println
```

Add `/` if the tag should self-close:

```@repl syntax-reference
haml"%br/" |> println
```

Add `<` to output an indented block in-line:

```@repl syntax-reference
haml"""
%p
  Hello, world
""" |> println

haml"""
%p<
  Hello, world
""" |> println
```

If you want to output a literal `%` at the start of a line, escape it with `\`:

```@repl syntax-reference
haml"""
%div
  %p this paragraph was obtained using the following code.
  %pre<
    \%p this paragraph was obtained using the following code.
""" |> println
```

## Attributes

### `id` and `class`

You can add an `id` attribute by using the `#` modifier:

```@repl syntax-reference
haml"%div#navigation" |> println
```

Similarly, classes can be added using the `.` modifier:

```@repl syntax-reference
haml"%span.foo.bar" |> println
```

In both cases, omitting the tag name creates a `div`:

```@repl syntax-reference
haml"#navigation.foo.bar" |> println

haml".foo.bar" |> println
```

### Named tuple syntax

Other attributes can be added using named tuple syntax:

```@repl syntax-reference
haml"""%a(href="/", title="click me") Click here!""" |> println
```

Any underscores in the key are replaced by dashes. If the desired attribute
is not a valid Julia symbol, use the `var"..."` syntax:

```@repl syntax-reference
haml"""%(foo_bar="foo-bar")""" |> println

haml"""
%html(xmlns = "http://www.w3.org/1999/xhtml", var"xml:lang"="en", lang="en")
""" |> println
```

### Collation and booleans

If the value of an attribute is a boolean, its value is either `attribute='attribute'`
(for `true`) or it is absent (for `false`):

```@repl syntax-reference
haml"%input(selected=true)" |> println

haml"%input(selected=false)" |> println
```

If the value of an attribute is a key/value structure, the attributes are flattened by
joining the keys with `-`:

```@repl syntax-reference
haml"""
%a(href="/posts", data=(author_id=123, category=7)) Posts By Author
""" |> println
```

When the value of `class` is a vector, its elements are joined by a space.
When the value of `id` is a vector, its elements are joined by `-`.

```@repl syntax-reference
haml"""
- items = ["foo", "bar"]
%(id=items)
%(class=items)
""" |> println
```

## Julia code

### In-line values

A line starting with `=` introduces a Julia expression whose value should be inserted.

```@repl syntax-reference
haml"""
%p How much is 2 + 2?
%p<
  It is
  = 2 + 2
""" |> println
```

The `=` sign can also immediately follow a tag on the same line:

```@repl syntax-reference
haml"""
%p How much is 2 + 2?
%p= "It is $(2 + 2)"
""" |> println
```

The expression can flow over several lines as long as the last non-comment character is a `,`:

```@repl syntax-reference
haml"""
%p= join(["butter", # popular foods
          "cheese",
          "eggs"], ", ", ", and ")
""" |> println
```

!!! note

    This does not necessarily agree with Julia's parsing rules or its understanding
    of an incomplete expression. This is deliberate because HAML is more sensitive to
    indentation than Julia is.

### Code blocks

A line starting with `-` introduces code that should run but not display any value.

```@repl syntax-reference
haml"""
- answer = 42
%dl
  %dt The answer to life, the universe, and everything
  %dd= answer
""" |> println
```

A particular case is `for`, `while` or `do` syntax. These have their usual effect
on the indented HAML block that follows:

```@repl syntax-reference
haml"""
%ul
  - for i in 1:3
    %li= i
""" |> println

haml"""
%ul
  - vals = collect(1:3)
  - while !isempty(vals)
    %li= popfirst!(vals)
""" |> println

haml"""
%dl
  - vals = Dict(:foo => 42, :bar => 43)
  - foreach(pairs(vals)) do (key, val)
    %dt= key
    %dd= val
""" |> println
```

### Interpolations

The character `$` interpolates a Julia value into the template:

```@repl syntax-reference
haml"""
- quality = "scrumptious"
%p This is $quality cake!
""" |> println

haml"""
- quality = "scrumptious"
%p= "This is $quality cake!"
""" |> println
```

Use `\` to escape it:
```@repl syntax-reference
haml"""
- quality = "scrumptious"
%p This is $quality cake!
%p This is \$quality cake!
""" |> println
```

## Comments

The `/` character introduces a HTML comment: its content is part of the output
but enclosed between `<!--` and `-->`.

```@repl syntax-reference
haml"""
%peanutbutterjelly
  / This is the peanutbutterjelly element
  I like sandwiches!
""" |> println

haml"""
/
  %p This doesn't render...
  %div
    %h1 Because it's commented out!
""" |> println
```

The combination `-#` introduces a HAML comment: it produces no output and
performs no action.

```@repl syntax-reference
haml"""
%p foo
-# This is a comment
%p bar
""" |> println
```

## Document type

The characters `!!!` introduce a document type specification. At the moment
only `!!! 5` (HTML 5 standard) is supported:

```@repl syntax-reference
haml"!!! 5"
```
