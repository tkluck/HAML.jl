using Test
using HAML

using DataStructures: OrderedDict

macro expandsto(str1, str2)
    :( @test $(esc(str1)) == $(esc(str2)) )
end

@testset "HAML" begin
    @testset "Plain Text" begin
        @expandsto """
        <gee>
          <whiz>
            Wow this is cool!
          </whiz>
        </gee>
        """ haml"""
        %gee
          %whiz
            Wow this is cool!
        """
        @expandsto """
        <p>
          <div id="blah">Blah!</div>
        </p>
        """ haml"""
        %p
          <div id="blah">Blah!</div>
        """
        let title = "MyPage"
            @expandsto """
            <title>
              MyPage
              = title
            </title>
            """ haml"""
            %title
              = title
              \= title
            """
        end
    end
    @testset "HTML elements" begin
        @expandsto """
        <one>
          <two>
            <three>Hey there</three>
          </two>
        </one>
        """ haml"""
        %one
          %two
            %three Hey there
        """
        # pending https://github.com/JuliaLang/julia/issues/32121#issuecomment-534982081
        #@expandsto """
        #<html xmlns='http://www.w3.org/1999/xhtml' xml:lang='en' lang='en'></html>
        #""" haml"""
        #%html(xmlns = "http://www.w3.org/1999/xhtml", Symbol("xml:lang") => "en", lang="en")
        #"""
        @expandsto """
        <script type='text/javascript' src='javascripts/script_9'></script>
        """ haml"""
        %script(type = "text/javascript",
                src  = "javascripts/script_$(2 + 7)")
        """
        let sortdir = :ascending, sortcol = (id=1, _type=:numeric)
            @expandsto """
            <div class='numeric sort ascending'>Contents</div>
            <div class='numeric'>Contents</div>
            <div>Contents</div>
            """ haml"""
            - for item in [ (id=1, _type=:numeric), (id=2, _type=:numeric), (id=3, _type=nothing) ]
              %div(class = [item._type; item == sortcol && [:sort, sortdir]]) Contents
            """
        end
        begin
            hash1() = OrderedDict(:bread => "white", :filling => "peanut butter and jelly")
            hash2() = OrderedDict(:bread => "whole wheat")
            @expandsto """
            <sandwich bread='whole wheat' filling='peanut butter and jelly' delicious='true' />
            """ haml"""
            %sandwich(hash1()..., hash2()..., delicious = "true")/
            """
        end

        let item = []
            @expandsto """
            <div class='item empty'></div>
            """ haml"""
            .item(class = isempty(item) && "empty")
            """
        end

        @expandsto """
        <a href='/posts' data-author-id='123' data-category='7'>Posts By Author</a>
        """ haml"""
        %a(href="/posts", data=(author_id=123, category=7)) Posts By Author
        """

        @expandsto """
        <input selected='selected' />
        """ haml"""
        %input(selected=true)/
        """

        @expandsto """
        <input />
        """ haml"""
        %input(selected=false)/
        """

        @expandsto """
        <div id='things'>
            <span id='rice'>Chicken Fried</span>
            <p class='beans' food='true'>The magical fruit</p>
            <h1 class='class otherclass' id='id'>La La La</h1>
        </div>
        """ haml"""
        %div#things
            %span#rice Chicken Fried
            %p.beans(food = "true") The magical fruit
            %h1.class.otherclass#id La La La
        """

        @expandsto """
        <blockquote><div>
          Foo!
        </div></blockquote>
        """ haml"""
        %blockquote<
          %div
            Foo!
        """
    end
    @testset "Whitespace" begin
        @expandsto "" haml""
        # disabled while we re-work indentation handling
        #@expandsto "
        #" haml"
        #"
        #@expandsto "
#
        #" haml"
#
        #"
        # no closing newline
        @expandsto "<div class='hello'></div>" haml"%div.hello"
    end

    @testset "Julia syntax embedding" begin
        # a comment after the comma
        @expandsto """
        <a href='#' c='d'>Hello everyone!</a>
        <div>1</div>
        <div>2</div>
        """ haml"""
        %a(href="#", # set href to #
              c="d") Hello everyone!
        - array = [1, # the first element
                   2]
        - for a in array
          %= a
        """

        # the characters #"' in annoying places
        @expandsto """
        #
        &#36;
        &quot;
        &quot;
        """ haml"""
        - for s in ["#", "\$", "\\""] # correctly parse some special characters
          = s
        - for s in ['"']
          = s
        """
    end
    @testset "Escaping" begin
        let motto="Let's get ready"
            @expandsto """
            <span motto='Let&#39;s get ready'></span>
            <div>Let&#39;s get ready</div>
            Let&#39;s get ready
            The motto is Let&#39;s get ready
            <p>Let&#39;s get ready</p>
            """ haml"""
            %span(motto=motto)
            %= motto
            = motto
            The motto is $motto
            %p $motto
            """
        end
    end
    @testset "Doctype" begin
        @expandsto """
        <!DOCTYPE html>
        """ haml"""
        !!! 5
        """
    end
    @testset "Comments" begin
        @expandsto """
        <peanutbutterjelly>
          <!-- This is the peanutbutterjelly element -->
          I like sandwiches!
        </peanutbutterjelly>
        """ haml"""
        %peanutbutterjelly
          / This is the peanutbutterjelly element
          I like sandwiches!
        """
        @expandsto """
        <!--
          <p>This doesn't render...</p>
          <div>
            <h1>Because it's commented out!</h1>
          </div>
        -->
        """ haml"""
        /
          %p This doesn't render...
          %div
            %h1 Because it's commented out!
        """
        @expandsto """
        <p>foo</p>
        <p>bar</p>
        """ haml"""
        %p foo
        -# This is a comment
        %p bar
        """
        @expandsto """
        <p>foo</p>
        <p>bar</p>
        """ haml"""
        %p foo
        -#
          This won't be displayed
            Nor will this
                           Nor will this.
        %p bar
        """
    end
    @testset "Helper methods" begin
        @expandsto """
        (<a href='#'>learn more</a>)
        """ haml"""
        - @surround("(", ")") do
          %a(href="#") learn more
        """
        @expandsto """
        *<span>Required</span>
        """ haml"""
        - @precede("*") do
          %span Required
        """
        @expandsto """
        Begin by
        <a href='#'>filling out your profile</a>,
        <a href='#'>adding a bio</a>,
        and
        <a href='#'>inviting friends</a>.
        """ haml"""
        Begin by
        - @succeed(",") do
          %a(href="#") filling out your profile
        - @succeed(",") do
          %a(href="#") adding a bio
        and
        - @succeed(".") do
          %a(href="#") inviting friends
        """
    end
    @testset "Julia evaluation" begin
        @expandsto """
        <p>
          hi there reader&#33;
          yo
        </p>
        """ haml"""
        %p
          = join(["hi", "there", "reader!"], " ")
          = "yo"
        """
        @expandsto """
        &lt;script&gt;alert&#40;&quot;I&#39;m evil&#33;&quot;&#41;;&lt;/script&gt;
        """ haml"""
        = "<script>alert(\\"I'm evil!\\");</script>"
        """
        @expandsto """
        <p>hello</p>
        """ haml"""
        %p= "hello"
        """
        @expandsto """
        <p>hello there you&#33;</p>
        """ haml"""
        - foo = "hello"
        - foo *= " there"
        - foo *= " you!"
        %p= foo
        """
        let quality = "scrumptious"
            @expandsto """
            <p>This is scrumptious cake!</p>
            """ haml"""
            %p This is $quality cake!
            """
        end
        let word = "yon"
            @expandsto raw"""
            <p>
              Look at \yon lack of backslash: $foo
              And yon presence thereof: \foo
            </p>
            """ haml"""
            %p
              Look at \\$word lack of backslash: \$foo
              And yon presence thereof: \foo
            """
        end
    end
    @testset "Scoping" begin
        let a = 2
            haml"""
            - @test a == 2
            - a = 3
            """
            @test a == 3
        end
    end
    @testset "Hygiene w.r.t. internal variables" begin
        @expandsto """
        <p>42</p>
        """ haml"""
        - io = 42
        %p= io
        """
        @expandsto """
        <p>42</p>
        """ haml"""
        - writeattributes = 42
        %p= writeattributes
        """
        @expandsto """
        <p>42</p>
        """ haml"""
        - writehaml = 42
        %p= writehaml
        """
        @expandsto """
        <p>42</p>
        """ haml"""
        - forest = 42 # don't mistake this for a for loop because it starts with for
        %p= forest
        """
        @expandsto """
        1 2 3 4 5 6 7 8 9 10
        """ haml"""
        = haml"= join(1:10, ' ')"
        """
        @expandsto """
        Hi!
        Hello!
        Bye!
        """ haml"""
        Hi!
        - @output "Hello!\n"
        - @HAML.output "Bye!\n"
        """
        @expandsto """
        Using the @output macro
        """ haml"""
        - @include("hamljl/at-output.hamljl")
        """
        # pending https://github.com/JuliaLang/julia/issues/32121#issuecomment-534982081
        #let attribute = :href # hygiene of the => operator inside a named tuple
        #    @expandsto """
        #    <a class='link', href='/index.html'>Home</a>
        #    """ haml"""
        #    %a(class="link", attribute => "/index.html") Home
        #    """
        #end
    end
    @testset "Control flow" begin
        @expandsto """
        <div>1</div>
        <div>2</div>
        <div>3</div>
        """ haml"""
        - for i in 1:3
          %= i
        """

        @expandsto """
        <div>1</div>
        <div>2</div>
        <div>3</div>
        """ haml"""
        - map(1:3) do i
          %= i
        """

        @expandsto """
        <div>3</div>
        <div>2</div>
        <div>1</div>
        """ haml"""
        - list = collect(1:3)
        - while !isempty(list)
          %= pop!(list)
        """

        @expandsto """
        <p>All else follows</p>
        """ haml"""
        - if 2 + 2 == 4
          %p All else follows
        - else
          %p I love Big Brother
        """

        @expandsto """
        <p>I love Big Brother</p>
        """ haml"""
        - if 2 + 2 == 5
          %p All else follows
        - else # with a comment
          %p I love Big Brother
        """
    end

    @testset "File format" begin

        @expandsto """
        <html>
          <head>
            <title>The Hitchhiker's guide to the galaxy</title>
          </head>
          <body>
            <h1>What's the question?</h1>
            <p>What&#39;s the answer to life, the universe, and everything?</p>
            <h2>What's the answer?</h2>
            <p>42</p>
          </body>
        </html>
        """ haml"""
        - @include("hamljl/hitchhiker.hamljl", question = "What's the answer to life, the universe, and everything?", answer = 42)
        """

        @expandsto """
        <form>
          <p>Here's a little button:</p>
          <button onclick='javascript:alert&#40;Thank you for clicking&#41;'>Click me</button>
          <p>Did you see the little button?</p>
        </form>
        """ haml"""
        - @include("hamljl/form.hamljl")
        """

        let io = IOBuffer()  # test the render(...) entrypoint
            render(io, joinpath(@__DIR__, "hamljl", "hitchhiker.hamljl"),
                variables = (
                    question = "What's the answer to life, the universe, and everything?",
                    answer = "42",
                ),
            )
            @test """
            <html>
              <head>
                <title>The Hitchhiker's guide to the galaxy</title>
              </head>
              <body>
                <h1>What's the question?</h1>
                <p>What&#39;s the answer to life, the universe, and everything?</p>
                <h2>What's the answer?</h2>
                <p>42</p>
              </body>
            </html>
            """ == String(take!(io))
        end
    end

    @testset "File/line information" begin
        line = @__LINE__
        @expandsto """
        <ul>
          <li>$(line +  9)</li>
          <li>$(line + 10)</li>
          <li>$(line + 11)</li>
        </ul>
        """ haml"""
        %ul
          %li= @__LINE__
          %li= @__LINE__
          %li= @__LINE__
        """

        @test haml"= @__FILE__" == @__FILE__
    end

    @testset "Compile-time expansion where possible" begin
        @macroexpand(haml"""
        %p Hallo
        """) isa String

        @macroexpand(haml"""
        !!! 5
        %html
          %head
            %title= title
          %body
            %ul
              %li= item1
              %li= item2
        """).head == :string
    end
end
