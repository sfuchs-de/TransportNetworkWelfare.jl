using Pkg
Pkg.develop(path=joinpath(@__DIR__, "..", "..", ".."))
Pkg.instantiate()

using AFWFSIsomorphism

output = length(ARGS) >= 1 ? abspath(ARGS[1]) :
    joinpath(@__DIR__, "..", "output", "validation.toml")
results = run_validation(output=output)
println("Wrote AFW--FS isomorphism diagnostics to: ", output)
for section in sort!(collect(keys(results)))
    println("[", section, "]")
    for (key, value) in sort!(collect(results[section]); by=first)
        println("  ", key, " = ", value)
    end
end
