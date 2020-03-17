var documenterSearchIndex = {"docs":
[{"location":"getting-started/#Getting-started-guide-1","page":"Getting started","title":"Getting started guide","text":"","category":"section"},{"location":"getting-started/#Installation-1","page":"Getting started","title":"Installation","text":"","category":"section"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"HAML.jl is a registered package and can be installed through the usual ]add HAML or using Pkg; Pkg.add(\"HAML\"). It has minimal dependencies.","category":"page"},{"location":"getting-started/#In-line-use-1","page":"Getting started","title":"In-line use","text":"","category":"section"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"The easiest way to experiment with HAML are haml\"...\" strings. This is an example of a non-standard string literal and it is implemented through the @haml_str macro. You use it like this:","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"using HAML\n\nprintln(haml\"%p Hello, world!\")","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"HAML uses indentation to mark the opening and closing of tags. This makes it possible to write HTML in a very concise way:","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"link = \"https://youtu.be/dQw4w9WgXcQ\"\n\nhaml\"\"\"\n!!! 5\n%html\n  %body\n    %a(href=link) Hello, world!\n\"\"\" |> print","category":"page"},{"location":"getting-started/#Syntax-overview-1","page":"Getting started","title":"Syntax overview","text":"","category":"section"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"Use % for tag name, # for the id attribute, . for the class attribute. Use named tuple syntax for other attributes. If % is omitted, we default to div:","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"haml\"\"\"%a(href=\"/\") Click me\"\"\" |> println\n\nhaml\"\"\"%a.nav(href=\"/\") Click me too\"\"\" |> println\n\nhaml\"\"\"%a#homelink.nav(href=\"/\") Home\"\"\" |> println\n\nhaml\"\"\"#navbar\"\"\" |> println\n\nhaml\"\"\".navitem\"\"\" |> println","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"Use indentation for nesting.\nUse - for evaluating Julia code. Use = for including the result of evaluating Julia code:","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"haml\"%p= 2 + 2\" |> println\n\nhaml\"\"\"\n%ul\n  - for i in 1:2\n    %li= i\n\"\"\" |> println","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"Use $ for interpolation of Julia values into static content:","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"haml\"%p= 2 + 2\" |> println\n\nhaml\"\"\"\n%p\n  Two and two make $(2 + 2)\n  - difficulty = \"easy\"\n  This is $(difficulty)!\n\"\"\" |> println","category":"page"},{"location":"getting-started/#Using-HAML-templates-from-files-1","page":"Getting started","title":"Using HAML templates from files","text":"","category":"section"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"Use the includehaml function to include a HAML template from a file and make it a function in a certain module.","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"mktemp() do path, io\n    write(io, raw\"\"\"\n    %p\n       Hello from this file! I am running in\n       %i= @__MODULE__\n       and I received the following parameters:\n    %dl\n      %dt foo\n      %dd= $foo\n      %dt bar\n      %dd= $bar\n    \"\"\")\n    close(io)\n\n    includehaml(Main, :my_first_template, path)\nend\n\nMain.my_first_template(foo=42, bar=43) |> print","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"Note how the keyword parameters are available through $foo and $bar.","category":"page"},{"location":"getting-started/#","page":"Getting started","title":"Getting started","text":"There is also a render function which takes a file name and immediately renders the result. However, we recommend using includehaml where possible, at the top-level of your module, because Julia will pre-compile the function in this case.","category":"page"},{"location":"api-reference/#API-reference-1","page":"API reference","title":"API reference","text":"","category":"section"},{"location":"api-reference/#Functions-and-macros-1","page":"API reference","title":"Functions and macros","text":"","category":"section"},{"location":"api-reference/#","page":"API reference","title":"API reference","text":"@haml_str\nincludehaml\nrender\n@include\n@sourcefile\n@cdatafile\n@surround\n@precede\n@succeed","category":"page"},{"location":"api-reference/#HAML.Codegen.@haml_str","page":"API reference","title":"HAML.Codegen.@haml_str","text":"@haml_str(source)\nhaml\"...\"\n\nInclude HAML source code into Julia source. The code will be executed in the context (module / function) where it appears and has access to the same variables.\n\nExample\n\njulia> using HAML\n\njulia> haml\"%p Hello, world\"\n\"<p>Hello, world</p>\"\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#HAML.Templates.includehaml","page":"API reference","title":"HAML.Templates.includehaml","text":"includehaml(mod::Module, fn::Symbol, path, indent=\"\")\nincludehaml(mod::Module, fns::Pair{Symbol}...)\n\nDefine methods for the function mod.fn that allow rendering the HAML template in the file path. These methods have the following signatures:\n\nfn(io::IO, indent=\"\"; variables...)\nfn(f::Function, indent=\"\"; variables...)\nfn(indent=\"\"; variables...)\n\nwhere the output of the template will be written to io / passed to f / returned respectively.\n\n\n\n\n\n","category":"function"},{"location":"api-reference/#HAML.Templates.render","page":"API reference","title":"HAML.Templates.render","text":"render(io, path; variables=(), indent=\"\")\n\nEvaluate HAML code in the file specified by path and write the result to io. Any variables passed as variables will be available to the resulting code as $key.\n\n\n\n\n\n","category":"function"},{"location":"api-reference/#HAML.Templates.@include","page":"API reference","title":"HAML.Templates.@include","text":"@include(relpath, args...)\n\nInclude HAML code from another file. This macro can only be used from within other HAML code. args should be key=value parameters and they will be accessible in the included code by using $key.\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#HAML.Helpers.@sourcefile","page":"API reference","title":"HAML.Helpers.@sourcefile","text":"- @sourcefile(relpath)\n\nInclude the contents of the file at relpath (relative to the current file's directory) literally into the output.\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#HAML.Helpers.@cdatafile","page":"API reference","title":"HAML.Helpers.@cdatafile","text":"- @cdatafile(relpath)\n\nInclude the contents of the file at relpath (relative to the current file's directory) as a CDATA section in the output. Any occurrences of ]]> are suitably escaped.\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#HAML.Helpers.@surround","page":"API reference","title":"HAML.Helpers.@surround","text":"- @surround(before, after) do\n  <haml block>\n\nSurround the output of <haml block> with before and after with no space in between.\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#HAML.Helpers.@precede","page":"API reference","title":"HAML.Helpers.@precede","text":"- @precede(before) do\n  <haml block>\n\nPrecede the output of <haml block> with before with no space in between.\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#HAML.Helpers.@succeed","page":"API reference","title":"HAML.Helpers.@succeed","text":"- @succeed(after) do\n  <haml block>\n\nFollow the output of <haml block> with after with no space in between.\n\n\n\n\n\n","category":"macro"},{"location":"api-reference/#Types-1","page":"API reference","title":"Types","text":"","category":"section"},{"location":"api-reference/#","page":"API reference","title":"API reference","text":"HAML.Source","category":"page"},{"location":"api-reference/#HAML.Parse.Source","page":"API reference","title":"HAML.Parse.Source","text":"HAML.Source(\"/path/to/file.hamljl\")\nHAML.Source(::LineNumberNode, ::AbstractString)\n\nRepresent Julia-flavoured HAML source code that can be parsed using the Meta.parse function.\n\n\n\n\n\n","category":"type"},{"location":"#HAML.jl-1","page":"Index","title":"HAML.jl","text":"","category":"section"},{"location":"#","page":"Index","title":"Index","text":"HTML Abstract Markup Language for Julia. Inspired by Ruby's HAML.","category":"page"},{"location":"#Getting-started-1","page":"Index","title":"Getting started","text":"","category":"section"},{"location":"#","page":"Index","title":"Index","text":"If you are already familiar with Ruby-flavoured HAML, read about the differences here. If not, the Getting started guide is the best starting point.","category":"page"},{"location":"#Syntax-1","page":"Index","title":"Syntax","text":"","category":"section"},{"location":"#","page":"Index","title":"Index","text":"The Syntax reference describes the language constructions of Julia-flavoured HAML.","category":"page"},{"location":"#Reference-1","page":"Index","title":"Reference","text":"","category":"section"},{"location":"#","page":"Index","title":"Index","text":"The API reference contains documentation on the exported functions and types that allow using HAML in your own application.","category":"page"},{"location":"syntax/#Syntax-reference-1","page":"Syntax reference","title":"Syntax reference","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"using HAML","category":"page"},{"location":"syntax/#Tags,-nesting,-and-whitespace-1","page":"Syntax reference","title":"Tags, nesting, and whitespace","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Lines starting with % indicate a tag, possibly with content. The content can either be in-line or in an indented block following.","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Examples:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"%p\" |> println\n\nhaml\"%p Hello, world!\" |> println\n\nhaml\"\"\"\n%div\n  %p First paragraph\n  %p Second paragraph\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Just % on its own is equivalent to %div:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%\n  %p First paragraph\n  %p Second paragraph\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Add / if the tag should self-close:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"%br/\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Add < to output an indented block in-line:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%p\n  Hello, world\n\"\"\" |> println\n\nhaml\"\"\"\n%p<\n  Hello, world\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"If you want to output a literal % at the start of a line, escape it with \\:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%div\n  %p this paragraph was obtained using the following code.\n  %pre<\n    \\%p this paragraph was obtained using the following code.\n\"\"\" |> println","category":"page"},{"location":"syntax/#Attributes-1","page":"Syntax reference","title":"Attributes","text":"","category":"section"},{"location":"syntax/#id-and-class-1","page":"Syntax reference","title":"id and class","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"You can add an id attribute by using the # modifier:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"%div#navigation\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Similarly, classes can be added using the . modifier:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"%span.foo.bar\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"In both cases, omitting the tag name creates a div:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"#navigation.foo.bar\" |> println\n\nhaml\".foo.bar\" |> println","category":"page"},{"location":"syntax/#Named-tuple-syntax-1","page":"Syntax reference","title":"Named tuple syntax","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Other attributes can be added using named tuple syntax:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"%a(href=\"/\", title=\"click me\") Click here!\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Any underscores in the key are replaced by dashes. If the desired attribute is not a valid Julia symbol, it can be encoded using Symbol(...) =>:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"%(foo_bar=\"foo-bar\")\"\"\" |> println\n\nhaml\"\"\"\n%html(xmlns = \"http://www.w3.org/1999/xhtml\", Symbol(\"xml:lang\") => \"en\", lang=\"en\")\n\"\"\" |> println","category":"page"},{"location":"syntax/#Collation-and-booleans-1","page":"Syntax reference","title":"Collation and booleans","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"If the value of an attribute is a boolean, its value is either attribute='attribute' (for true) or it is absent (for false):","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"%input(selected=true)\" |> println\n\nhaml\"%input(selected=false)\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"If the value of an attribute is a key/value structure, the attributes are flattened by joining the keys with -:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%a(href=\"/posts\", data=(author_id=123, category=7)) Posts By Author\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"When the value of class is a vector, its elements are joined by a space. When the value of id is a vector, its elements are joined by -.","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n- items = [\"foo\", \"bar\"]\n%(id=items)\n%(class=items)\n\"\"\" |> println","category":"page"},{"location":"syntax/#Julia-code-1","page":"Syntax reference","title":"Julia code","text":"","category":"section"},{"location":"syntax/#In-line-values-1","page":"Syntax reference","title":"In-line values","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"A line starting with = introduces a Julia expression whose value should be inserted.","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%p How much is 2 + 2?\n%p<\n  It is\n  = 2 + 2\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"The = sign can also immediately follow a tag on the same line:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%p How much is 2 + 2?\n%p= \"It is $(2 + 2)\"\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"The expression can flow over several lines as long as the last non-comment character is a ,:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%p= join([\"butter\", # popular foods\n          \"cheese\",\n          \"eggs\"], \", \", \", and \")\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"note: Note\nThis does not necessarily agree with Julia's parsing rules or its understanding of an incomplete expression. This is deliberate because HAML is more sensitive to indentation than Julia is.","category":"page"},{"location":"syntax/#Code-blocks-1","page":"Syntax reference","title":"Code blocks","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"A line starting with - introduces code that should run but not display any value.","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n- answer = 42\n%dl\n  %dt The answer to life, the universe, and everything\n  %dd= answer\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"A particular case is for, while or do syntax. These have their usual effect on the indented HAML block that follows:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%ul\n  - for i in 1:3\n    %li= i\n\"\"\" |> println\n\nhaml\"\"\"\n%ul\n  - vals = collect(1:3)\n  - while !isempty(vals)\n    %li= popfirst!(vals)\n\"\"\" |> println\n\nhaml\"\"\"\n%dl\n  - vals = Dict(:foo => 42, :bar => 43)\n  - foreach(pairs(vals)) do (key, val)\n    %dt= key\n    %dd= val\n\"\"\" |> println","category":"page"},{"location":"syntax/#Interpolations-1","page":"Syntax reference","title":"Interpolations","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"The character $ interpolates a Julia value into the template:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n- quality = \"scrumptious\"\n%p This is $quality cake!\n\"\"\" |> println\n\nhaml\"\"\"\n- quality = \"scrumptious\"\n%p= \"This is $quality cake!\"\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"Use \\ to escape it:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n- quality = \"scrumptious\"\n%p This is $quality cake!\n%p This is \\$quality cake!\n\"\"\" |> println","category":"page"},{"location":"syntax/#Comments-1","page":"Syntax reference","title":"Comments","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"The / character introduces a HTML comment: its content is part of the output but enclosed between <!-- and -->.","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%peanutbutterjelly\n  / This is the peanutbutterjelly element\n  I like sandwiches!\n\"\"\" |> println\n\nhaml\"\"\"\n/\n  %p This doesn't render...\n  %div\n    %h1 Because it's commented out!\n\"\"\" |> println","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"The combination -# introduces a HAML comment: it produces no output and performs no action.","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"\"\"\n%p foo\n-# This is a comment\n%p bar\n\"\"\" |> println","category":"page"},{"location":"syntax/#Document-type-1","page":"Syntax reference","title":"Document type","text":"","category":"section"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"The characters !!! introduce a document type specification. At the moment only !!! 5 (HTML 5 standard) is supported:","category":"page"},{"location":"syntax/#","page":"Syntax reference","title":"Syntax reference","text":"haml\"!!! 5\"","category":"page"},{"location":"fromruby/#Differences-from-Ruby-flavoured-HAML-1","page":"Coming from Ruby HAML","title":"Differences from Ruby-flavoured HAML","text":"","category":"section"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"Julia-flavoured HAML is quite close to Ruby-flavoured HAML. Below we describe the differences between the syntax for the latter and the former.","category":"page"},{"location":"fromruby/#Attributes-use-named-tuple-syntax-1","page":"Coming from Ruby HAML","title":"Attributes use named tuple syntax","text":"","category":"section"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"In Ruby-flavoured HAML the attributes are specified in a Ruby-like syntax. In the Julia-flavoured version, we use the same syntax as for named tuples. Examples:","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"- link = \"https://youtu.be/dQw4w9WgXcQ\"\n- attr = :href\n%a(href=link) Click me\n%a(attr=>link) Click me","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"Just like in the Ruby-flavoured version, nested attributes are joined by - and underscores in keys are replaced by dashes:","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"%a(href=\"/posts\", data=(author_id=123, category=7)) Posts By Author","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"If you need another special character in the attribute, it with Symbol(...) =>. For example, the attribute xml:lang:","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"%html(xmlns = \"http://www.w3.org/1999/xhtml\", Symbol(\"xml:lang\") => \"en\", lang=\"en\")","category":"page"},{"location":"fromruby/#Helper-methods-are-usually-macros-1","page":"Coming from Ruby HAML","title":"Helper methods are usually macros","text":"","category":"section"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"Many of the Ruby-flavoured helper methods are not supported (yet). The ones that are (e.g., @surround) are macros. In particular, note that you should use - and not = as in Ruby:","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"- @surround(\"(\", \")\") do\n  %span Hello","category":"page"},{"location":"fromruby/#Interpolation-expects-Julia-syntax-1","page":"Coming from Ruby HAML","title":"Interpolation expects Julia syntax","text":"","category":"section"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"Use $ for interpolation in literal text instead of #{...}. Example:","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"- quality = \"scruptious\"\n%p This is $quality cake!","category":"page"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"note: Note\nIf you need to combine this with keyword parameters to a template file, you'll need double quotes:%p This is $($quality) cake!","category":"page"},{"location":"fromruby/#Helper-macros/methods-may-need-to-be-imported-1","page":"Coming from Ruby HAML","title":"Helper macros/methods may need to be imported","text":"","category":"section"},{"location":"fromruby/#","page":"Coming from Ruby HAML","title":"Coming from Ruby HAML","text":"If you use @haml_str or HAML.includehaml the HAML code runs in a module you own. If you want to use macros or helper methods (e.g., @include or @surround then you need to either use using HAML or import them.","category":"page"}]
}
