@doc """
    HAML.Genie

Optional integration with the Genie web framework
"""
module GenieTools

import ..Genie
import ..Genie.Renderer: @vars

import ..Templates: includehaml

module DefaultContext
    import ...Genie.Renderer: @vars
end

function html(resource :: Genie.Renderer.ResourcePath,
              action   :: Genie.Renderer.ResourcePath;
              layout   :: Genie.Renderer.ResourcePath = Genie.Renderer.Html.DEFAULT_LAYOUT_FILE,
              context  :: Module = DefaultContext,
              status   :: Int = 200,
              headers  :: Genie.Renderer.HTTPHeaders = Genie.Renderer.HTTPHeaders(),
              vars...) :: Genie.Renderer.HTTP.Response
    viewpath = joinpath(
        Genie.config.path_resources,
        string(resource),
        Genie.Renderer.VIEWS_FOLDER,
        string(action),
    )
    layoutpath = joinpath(
        Genie.config.path_app,
        Genie.Renderer.Html.LAYOUTS_FOLDER,
        string(layout),
    )
    return html(
        Genie.Renderer.Path(viewpath);
        layout = Genie.Renderer.Path(layoutpath),
        context = context,
        status = status,
        headers = headers,
        vars...,
    )
end

function html(viewfile :: Genie.Renderer.FilePath;
              layout   :: Union{Nothing, Genie.Renderer.FilePath} = nothing,
              context  :: Module = DefaultContext,
              status   :: Int = 200,
              headers  :: Genie.Renderer.HTTPHeaders = Genie.Renderer.HTTPHeaders(),
              vars...) :: Genie.Renderer.HTTP.Response

    fn = Symbol(viewfile)
    if !hasproperty(context, fn)
        includehaml(context, fn, convert(String, viewfile))
    end
    try
        Genie.Renderer.registervars(vars...)
        body = Base.invokelatest(getproperty(context, fn))
        renderable = Genie.Renderer.WebRenderable(body = body, status = status, headers = headers)
        return Genie.Renderer.respond(renderable)
    finally
        # don't take any risk of leaking variables (e.g. session cookies,
        # cc numbers) between requests.
        empty!(@vars)
    end
end

end # module
