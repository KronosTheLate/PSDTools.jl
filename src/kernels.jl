using DataStructures

let k=0  # Essentially allows `k` to be an internal state in the function
    """
        kernel_get_raw_data_dummy!(data_channel, fs, lamps, A_rand=1)

    Compute signal from lamps in `lamps`. Increment "time" by 1/fs each call.
    """
    global function kernel_get_raw_data_dummy!(voltages_channel, fs, lamps, A_rand=1)
        t0 = time_ns()
        
        Ts = 1/fs  # Sample period
        t = k*Ts

        electrode_measurements = collect_tuple(sum(
                lamps[lamp_ind].As[electrode_ind]*sin(2π*lamps[lamp_ind].f*t) + A_rand*rand()
            for lamp_ind in eachindex(lamps)) 
            for electrode_ind in 1:4
        )
        put!(voltages_channel, electrode_measurements)
        k += 1

        while (time_ns()-t0)/1e9 < Ts
            # waiting for 1 sample period to elapse, 
        end
    end
end
export kernel_get_raw_data_dummy!


"""
kernel_estimate_POCs!(voltages_channel::Channel, voltages_buffer::CircularBuffer, POCs_channel::Channel, amplitudes_minibuffer, estimate_amplitudes_electrode_i!)
"""
function kernel_estimate_POCs!(voltages_channel::Channel, voltages_buffer::CircularBuffer, POCs_channel, amplitudes_minibuffer, freqs_probe, amplitude_estimator = dft_probe; timefunc, fs)
    # We need a full input buffer to use as many samples for each estimate
    # This protects against estimates based on e.g. 2 samples, i.e. garbage.
    # while !isfull(voltages_buffer)
    #     push!(voltages_buffer, take!(voltages_channel))
    # end

    # Put any available samples into input buffer, so that 
    # they are included in next processing loop
    while !isempty(voltages_channel)
        push!(voltages_buffer, take!(voltages_channel))
    end

    # Spawn tasks that process each electrode in parallel
    Threads.@threads for i in 1:4
        sig_i = getindex.(voltages_buffer, i)
        result_from_channel_i = collect_tuple(amplitude_estimator(sig_i, f_probe, fs) for f_probe in freqs_probe)
        amplitudes_minibuffer[i] = result_from_channel_i
    end

    calculated_POCs = collect_tuple(calculate_POC(getindex.(amplitudes_minibuffer, i)...) for i in eachindex(freqs_probe))
    
    put!(POCs_channel, timefunc()=>calculated_POCs)
end
export kernel_estimate_POCs!


function kernel_store_POCs_in_buffer!(POCs_channel::Channel, POCs_buffer::CircularBuffer)
    while !isempty(POCs_channel)
        push!(POCs_buffer, take!(POCs_channel))
    end
end
export kernel_store_POCs_in_buffer!