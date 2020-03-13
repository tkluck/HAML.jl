import .Templates: revisehook, _includehaml

revisehook(mod::Module, fn::Symbol, path, indent) = begin
    Revise.add_callback([path]) do
        _includehaml(mod, fn, path, indent)
    end
end
