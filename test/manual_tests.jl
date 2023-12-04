try
    print("Loading packages...")
    # using Pkg
    # Pkg.activate("InCompanyProject", shared=true)
    using Revise
    using ZMQ
    using PSDTools
    using DataStructures
    using DSP
    using Dates
    using TimesDates
    println("✓")
catch
    @warn "Encountered error while loading packages. Rethrowing error."
    rethrow()
end

let
    fs = 50_000
    n_filter = 5
    n_samples = 1000
    f_center = 7_500
    f_bandwidth = 100
    T = Float64
    
    @time push!(p, (1.0, 2.0, 3.0, 4.0))
    @time amplitude(p)
end

let

    fs = 50_000
    n_filter = 5
    n_samples = 1000
    f_true = 10_000
    f_probe = f_true
    f_bandwidth = 100
    # T = Float32

    frmsps = FiltRMSProbes(fs, n_filter, n_samples, f_probe, f_bandwidth)
    
    filter_order = 8
    bandwidth = 100

    N_sig = 20960
    A = 1
    ts = range(0, step=1/fs, length=N_sig)
    sig = [collect_tuple(A * sin(2π*f_true*t) for _ in 1:4) for t in ts]
    for s in sig
        push!(frmsps, s)
    end
    amplitude(frmsps)
end

let
    f_true = 10_000
    fs = 50_000
    f_probe = 10_000
    filter_order = 8
    bandwidth = 100
    my_filter = make_filter_bandpass(f_probe, filter_order, bandwidth; fs)
    @show SecondOrderSections(my_filter)
    global my_stateful_filter = DF2TFilter(my_filter)

    N_sig = 2096
    A = 1
    ts = range(0, step=1/fs, length=N_sig)
    global sig = [A * sin(2π*f_true*t) for t in ts]

    sig_filtered = filt(my_filter, sig)
    println.(sig_filtered[1:10])
    # @edit filt(convert(SecondOrderSections, my_filter), sig)

    global output2 = Float64[0.0]
    # filt!(output2, my_stateful_filter, [1.0])
    
    # filt!(output, my_filter, sig, [1, 2, 3, 4, 5.0])
    # propertynames(my_stateful_filter)
    # my_stateful_filter.state
    # my_stateful_filter
    # coefa(my_filter)
    # coefb(my_filter)
    # sig = rand(100)
    # impresp(f, filter_order)
end
i = 1
begin
    filt!(output2, my_stateful_filter, [sig[i]])
    i += 1
    println(only(output2))
end