using DataStructures


"""
kernel_estimate_POCs!(voltages_channel::Channel, voltages_buffer::CircularBuffer, POCs_channel::Channel, amplitudes_minibuffer, estimate_amplitudes_electrode_i!)
"""
function kernel_estimate_POCs_new!(timestamps_channel::Channel, voltages_channel::Channel, voltages_buffer::CircularBuffer, POCs_channel, amplitudes_minibuffer, freqs_probe, amplitude_estimator = dft_probe; fs)
    # We need a full input buffer to use as many samples for each estimate
    # This protects against estimates based on e.g. 2 samples, i.e. garbage.
    # while !isfull(voltages_buffer)
    #     push!(voltages_buffer, take!(voltages_channel))
    # end

    sample_period = Nanosecond(10^9//fs)
    n_new_samples = 0
    # Put any available samples into input buffer, so that 
    # they are included in next processing loop
    while !isempty(voltages_channel)
        push!(voltages_buffer, take!(voltages_channel))
        n_new_samples += 1
    end
    timestamp = take!(timestamps_channel) + n_new_samples*sample_period

    # Spawn tasks that process each electrode in parallel
    Threads.@threads for i in 1:4
        sig_i = getindex.(voltages_buffer, i)
        result_from_channel_i = collect_tuple(amplitude_estimator(sig_i, f_probe, fs) for f_probe in freqs_probe)
        amplitudes_minibuffer[i] = result_from_channel_i
    end

    calculated_POCs = collect_tuple(calculate_POC(getindex.(amplitudes_minibuffer, i)...) for i in eachindex(freqs_probe))
    
    put!(POCs_channel, timestamp=>calculated_POCs)
    if isempty(timestamps_channel)
        # This means that no new block has been processed, and we put 
        # the old timestamp back in the channel, so that 
        # a) the process does not get stuck waiting for new timestamp.
        # b) the timestamp can correctly be incremented further as we process the block
        push!(timestamps_channel, timestamp)
    end
end
export kernel_estimate_POCs_new!