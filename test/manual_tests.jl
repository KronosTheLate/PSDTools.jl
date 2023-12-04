try
    print("Loading packages...")
    # using Pkg
    # Pkg.activate("InCompanyProject", shared=true)
    using Revise
    using ZMQ
    using PSDTools
    using DataStructures
    using Dates
    using TimesDates
    println("✓")
catch
    @warn "Encountered error while loading packages. Rethrowing error."
    rethrow()
end

