using Test
using HAML

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
        @expandsto """
        <html xmlns='http://www.w3.org/1999/xhtml' xml:lang='en' lang='en'></html>
        """ haml"""
        %html(xmlns = "http://www.w3.org/1999/xhtml", Symbol("xml:lang") => "en", lang="en")
        """
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
            hash1() = Dict(:bread => "white", :filling => "peanut butter and jelly")
            hash2() = Dict(:bread => "whole wheat")
            @expandsto """
            <sandwich filling='peanut butter and jelly' bread='whole wheat' delicious='true' />
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
    end
    @testset "Whitespace" begin
        @expandsto "" haml""
        @expandsto "
        " haml"
        "
        @expandsto "

        " haml"

        "
        # no closing newline
        @expandsto "<div class='hello'></div>" haml"%div.hello"
    end
    @testset "Escaping" begin
        let motto="Let's get ready"
            @expandsto """
            <span motto='Let&#39;s get ready'></span>
            <div>Let&#39;s get ready</div>
            Let&#39;s get ready
            """ haml"""
            %span(motto=motto)
            %= motto
            = motto
            """
        end
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

#        @expandsto """
#          <div>3</div>
#          <div>2</div>
#          <div>1</div>
#        """ haml"""
#        - list = collect(1:3)
#        - while !isempty(list)
#          %= pop!(list)
#         """

        @expandsto """
          <p>All else follows</p>
        """ haml"""
        - if 2 + 2 == 4
          %p All else follows
        - else
          %p I love Big Brother
        """
    end
end
