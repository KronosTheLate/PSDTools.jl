using DataStructures
using PythonCall
using Dates

try
    global daqhats = pyimport("daqhats")
    global daqhats_utils = pyimport("daqhats_utils")
catch e
    @warn "Encountered error while importing 'daqhats' and 'daqhats_utils'. Ensure that you can launch python and call 'import daqhats' and 'import daqhats_utils' without errors.\n\nData-collection functionality will error until this is fixed."
end

function aquire_data!(data_channel::Channel, controlling_event::Threads.Event)
    channels = [2,3]
    channel_mask = daqhats_utils.chan_list_to_mask(channels)
    num_channels = length(channels)
    channels2 = [0,1]
    channel_mask2 = daqhats_utils.chan_list_to_mask(channels2)


    input_mode = daqhats.AnalogInputMode.DIFF
    input_range = daqhats.AnalogInputRange.BIP_10V

    samples_per_channel = 1024

    options = daqhats.OptionFlags.CONTINUOUS

    
    # Select an MCC 128 HAT device to use.
    #address = select_hat_device(HatIDs.MCC_128)
    hat = daqhats.mcc128(7)
    hat2 = daqhats.mcc128(2)
    # print(adress)
    hat.a_in_mode_write(input_mode)
    hat.a_in_range_write(input_range)
    
    hat2.a_in_mode_write(input_mode)
    hat2.a_in_range_write(input_range)
    
    scan_rate = 50_000

    # Actual scan rate seems to be calculated inside `read_and_put_data` call.
    #actual_scan_rate = hat.a_in_scan_actual_rate(num_channels, scan_rate)
    #actual_scan_rate2 = hat2.a_in_scan_actual_rate(num_channels, scan_rate)

    try
        hat.a_in_scan_start(channel_mask, samples_per_channel, scan_rate, options)
        hat2.a_in_scan_start(channel_mask2, samples_per_channel, scan_rate, options)
        read_and_put_data!(data_channel, controlling_event, scan_rate, hat, hat2, num_channels)
    catch
        @warn "Encountered an error when when starting HAT-scans. Call `errormonitor` on the relevant task to see the full error."
        rethrow()
    end
end
export aquire_data!

"""
    Reads data from the specified channels on the specified DAQ HAT devices
    and updates the data on the terminal display.  The reads are executed in a
    loop that continues until the user stops the scan or an overrun error is
    detected.

    Args:
        hat (mcc128): The mcc128 HAT device object.
        num_channels (int): The number of channels to display.

    Returns:
        None 
"""
function read_and_put_data!(data_channel, controlling_event, scan_rate, hat, hat2, num_channels)
    #total_samples_read = 0
    read_request_size = 2096

    # When doing a continuous scan, the timeout value will be ignored in the
    # call to a_in_scan_read because we will be requesting that all available
    # samples (up to the default buffer size) be returned.
    timeout = 5.0
    actual_scan_rate = hat.a_in_scan_actual_rate(num_channels, scan_rate)
    actual_scan_rate2 = hat2.a_in_scan_actual_rate(num_channels, scan_rate)

    #fstep = actual_scan_rate/read_request_size
    #f = np.linspace(0, (read_request_size-1)*fstep,read_request_size)

    Threads.@spawn try  # Start loop as a task that can move between threads
        while true
            
            # Pause here untill we call `notify(controlling_event)`
            # This is what allows a pausable `while true` loop.
            wait(controlling_event)

            read_result = hat.a_in_scan_read(read_request_size, timeout)
            read_result2 = hat2.a_in_scan_read(read_request_size, timeout)

            samples_read_per_channel = round(Int, length(read_result.data) / num_channels)
            
            #sanity-check. This should be removed if the warning is never printed.
            samples_read_per_channel2 = round(Int, length(read_result2.data) / num_channels)
            if samples_read_per_channel != samples_read_per_channel2
                @warn "A different number of samples was read for channel1 and channel2"
            end
            
            if samples_read_per_channel > 0
                
                for i in 0:samples_read_per_channel-1
                    # We collect a sample from each electrode into a `sample_set`
                    sample_set_python = (read_result.data[i], read_result.data[i+1], read_result.data2[i], read_result.data2[i+1])
                    
                    # We convert the data from python datatypes to julia datatypes
                    sample_set_julia = Base.Fix1(pyconvert, Float32).(sample_set_python)
                    
                    # We put individual sample-sets into `data_channel`, 
                    # for consuption by another thread/task
                    put!(data_channel, sample_set_julia)
                end

                # Original implementation:
                # socket.send(np.array(read_result2.data[0::2], dtype= np.complex64))
                
                # Why do we send the measured voltages as complex values?
                
            end
        end
    catch 
        @warn "Encountered an error during data collection loop. Call `errormonitor` on the relevant task to see the full error."
        rethrow()
    finally  # Perform cleanup no matter how infinite loop exits
        hat.a_in_scan_stop()
        hat.a_in_scan_cleanup()       
        hat2.a_in_scan_stop()
        hat2.a_in_scan_cleanup() 
    end 
end

# Original Python Script:

#=
#!/usr/bin/env python
#  -*- coding: utf-8 -*-

"""
    MCC 128 Functions Demonstrated:
        mcc128.a_in_scan_start
        mcc128.a_in_scan_read
        mcc128.a_in_scan_stop
        mcc128_a_in_scan_cleanup
        mcc128.a_in_mode_write
        mcc128.a_in_range_write

    Purpose:
        Perform a continuous acquisition on 1 or more channels.

    Description:
        Continuously acquires blocks of analog input data for a
        user-specified group of channels until the acquisition is
        stopped by the user.  The last sample of data for each channel
        is displayed for each block of data received from the device.
"""
from __future__ import print_function
from sys import stdout
from scipy import signal
from time import sleep
from daqhats import mcc128, mcc152, OptionFlags, HatIDs, HatError, AnalogInputMode, \
    AnalogInputRange
from daqhats_utils import select_hat_device, enum_mask_to_string, \
    chan_list_to_mask, input_mode_to_string, input_range_to_string
import matplotlib.pyplot as plt
import numpy as np
import datetime;
import zmq


READ_ALL_AVAILABLE =-1

CURSOR_BACK_2 = '\x1b[2D'
ERASE_TO_END_OF_LINE = '\x1b[0K'


def x_position(x1, x2, y1, y2):
    return ((x2+y1)-(x1+y2))/(x1+x2+y1+y2)*6.82

def y_position(x1, x2, y1, y2):
    return ((x2+y2)-(x1+y1))/(x1+x2+y1+y2)*6.82 



def column(matrix, i):
    return [row[i] for row in matrix]
idk = []

context = zmq.Context()
socket = context.socket(zmq.PUB)
socket.bind("tcp://127.0.0.1:1234")
socket2 = context.socket(zmq.PUB)
socket2.bind("tcp://127.0.0.1:12345")
socket3 = context.socket(zmq.PUB)
socket3.bind("tcp://127.0.0.1:123456")
socket4 = context.socket(zmq.PUB)
socket4.bind("tcp://127.0.0.1:1234567")


def main():
    """
    This function is executed automatically when the module is run directly.
    """

    # Store the channels in a list and convert the list to a channel mask that
    # can be passed as a parameter to the MCC 128 functions.
    channels = [2,3]
    channel_mask = chan_list_to_mask(channels)
    num_channels = len(channels)
    channels2 = [0,1]
    channel_mask2 = chan_list_to_mask(channels2)


    input_mode = AnalogInputMode.DIFF
    input_range = AnalogInputRange.BIP_10V

    samples_per_channel = 1024

    options = OptionFlags.CONTINUOUS

    scan_rate = 50000

        # Select an MCC 128 HAT device to use.
    #address = select_hat_device(HatIDs.MCC_128)
    hat = mcc128(7)
    hat2 = mcc128(2)
   # print(adress)
    hat.a_in_mode_write(input_mode)
    hat.a_in_range_write(input_range)



    hat2.a_in_mode_write(input_mode)
    hat2.a_in_range_write(input_range)

    actual_scan_rate = hat.a_in_scan_actual_rate(num_channels, scan_rate)
    actual_scan_rate2 = hat2.a_in_scan_actual_rate(num_channels, scan_rate)

    


        # Configure and start the scan.
        # Since the continuous option is being used, the samples_per_channel
        # parameter is ignored if the value is less than the default internal
        # buffer size (10000 * num_channels in this case). If a larger internal
        # buffer size is desired, set the value of this parameter accordingly.

        # Display the header row for the data table.    
    try:
            hat.a_in_scan_start(channel_mask, samples_per_channel, scan_rate,
                            options)
            hat2.a_in_scan_start(channel_mask2, samples_per_channel, scan_rate,
                            options)
                            
            read_and_display_data(channel_mask, channel_mask2, samples_per_channel, scan_rate,
                            options, hat,hat2,num_channels)

    except KeyboardInterrupt:
            # Clear the '^C' from the display.
            print(CURSOR_BACK_2, ERASE_TO_END_OF_LINE, '\n')
            print('Stopping')
            hat.a_in_scan_stop()
            hat.a_in_scan_cleanup()       
            hat2.a_in_scan_stop()
            hat2.a_in_scan_cleanup() 




def read_and_display_data(channel_mask, channel_mask2, samples_per_channel, scan_rate,
                            options, hat,hat2,num_channels):
    """
    Reads data from the specified channels on the specified DAQ HAT devices
    and updates the data on the terminal display.  The reads are executed in a
    loop that continues until the user stops the scan or an overrun error is
    detected.

    Args:
        hat (mcc128): The mcc128 HAT device object.
        num_channels (int): The number of channels to display.

    Returns:
        None

    """

    total_samples_read = 0
    read_request_size = 2096

    # When doing a continuous scan, the timeout value will be ignored in the
    # call to a_in_scan_read because we will be requesting that all available
    # samples (up to the default buffer size) be returned.
    timeout = 5.0
    actual_scan_rate = hat.a_in_scan_actual_rate(num_channels, scan_rate)

    actual_scan_rate2 = hat2.a_in_scan_actual_rate(num_channels, scan_rate)

    fstep = actual_scan_rate/read_request_size
    f = np.linspace(0, (read_request_size-1)*fstep,read_request_size)


    while True:
        
        read_result = hat.a_in_scan_read(read_request_size, timeout)
        read_result2 = hat2.a_in_scan_read(read_request_size, timeout)

        samples_read_per_channel = int(len(read_result.data) / num_channels)

        if samples_read_per_channel > 0:

            socket.send(np.array(read_result2.data[0::2], dtype= np.complex64))
           
            socket2.send(np.array(read_result2.data[1::2], dtype= np.complex64))

            
            socket3.send(np.array(read_result.data[0::2], dtype= np.complex64))
              
            
            socket4.send(np.array(read_result.data[1::2], dtype= np.complex64))
        
                #print(idk)
                #print(t1-t2)
                

     


if __name__ == '__main__':
    main()


=#

# No need to split this into two functions
#=
function aquire_data_dummy!(data_channel::Channel, controlling_event::Threads.Event, freqs, fs)
    # No setup required for dummy :)
    try
        read_and_put_data_dummy!(data_channel, controlling_event, freqs, fs)
    catch
        @warn "Encountered an error when when starting HAT-scans. Call `errormonitor` on the relevant task to see the full error."
        rethrow()
    end
end
export aquire_data_dummy!
=#

function schedule_data_collector_dummy!(data_channel, controlling_event, lamps, fs)
    k = 0  # Fake discrete time index
    Ts = 1/fs  # Sample period
    A_rand = 1
    Threads.@spawn try
        while true  # Start loop as a task that can move between threads
            t0 = time_ns()
            # Pause here untill we call `notify(controlling_event)`
            # This is what allows a pausable `while true` loop.
            wait(controlling_event)
            t = Ts*k
            electrode_measurements = collect_tuple(sum(
                    lamps[lamp_ind].As[electrode_ind]*sin(2π*lamps[lamp_ind].f*t) + A_rand*rand()
                for lamp_ind in eachindex(lamps)) 
                for electrode_ind in 1:4
            )
            # electrode_measurements = collect_tuple(sum(A*sin(2π*freq*t) for freq in freqs) for A in rel_amplitudes)
            put!(data_channel, electrode_measurements)
            k += 1

            while (time_ns()-t0)/1e9 < Ts
                # waiting for 1 sample period to elapse, 
            end
        end
    catch
        @info "Encountered an error in the data collection loop. Call `errormonitor` on the relevant task to see the full error."
        println(e)
        rethrow()
        #No cleanup for dummy-data
    end 
end
export schedule_data_collector_dummy!

function schedule_data_processor!(voltages_channel::Channel, controlling_event::Base.Event, input_buffer::CircularBuffer, output_channel::Channel, processing_function, freqs_probe)
    # `processing_function` should take as it's only argument a signal from a single electrode, 
    # and return a tuple of estimated RMS voltages, with one element per frequency
    
    # The minibuffer needs to be a vector to allow changing its values.
    # It contains tuples because tuples are cheap (no allocations)
    
    amplitudes_minibuffer = Vector{NTuple{length(freqs_probe), eltype(eltype(voltages_channel))}}(undef, 4)

    # We define a function that processes the data from electrode `i`
    # It will be used to spawn tasks
    function processing_task!(i, minibuf=amplitudes_minibuffer)
        result_from_channel_i = processing_function(getindex.(input_buffer, i))
        minibuf[i] = result_from_channel_i
        return nothing
    end

    # We want to 
    # 1) Accumulate as many samples as can fit into `input_buffer`
    # 2) Process all samples, getting `length(freqs_probe)` position estimates
    # 3) Get new samples
    # 4) Go to step 2

    # We spawn a single task that runs in a `while true` loop. 
    # This function will remain inside this loop forever.
    # In each loop, this task will create 4 tasks that process data mulithreaded
    time_initial = time_ns()
    Threads.@spawn try
        while true
            if !controlling_event.set
                # If the controlling event is not set, we are about to wait.
                # This means that the next samples will be taken later, breaking 
                # continuity with the samples we have. We therefore discard 
                # the samples currently in `input_buffer`
                empty!(input_buffer)
            end
            wait(controlling_event)
            time_started_processing = time_ns()-time_initial # We will attach timestamp to each position
            while !isfull(input_buffer)
                push!(input_buffer, take!(voltages_channel))
            end
            tasks = [Threads.@spawn processing_task!(i) for i in eachindex(amplitudes_minibuffer)]
            
            # Wait until all processing is finnished
            foreach(wait, tasks)  # Calls `wait` on each element in `tasks`
            calculated_POCs = collect_tuple(calculate_POC(getindex.(amplitudes_minibuffer, i)...) for i in eachindex(freqs_probe))
            
            put!(output_channel, time_started_processing=>calculated_POCs)

            # Put any available samples into input buffer, so that 
            # they are included in next processing loop
            while !isempty(voltages_channel) > 0
                push!(input_buffer, take!(voltages_channel))
            end
        end
    catch
        @info "Encountered an error in the data processing loop. Call `errormonitor` on the relevant task to see the full error."
        rethrow()
    end
end
export schedule_data_processor!


function schedule_data_consumer!(controlling_event::Base.Event, output_channel::Channel, positions_buffer::CircularBuffer)
    Threads.@spawn try
        while true
            wait(controlling_event)
            while !isempty(output_channel)
                push!(positions_buffer, take!(output_channel))
            end
            # `result` will be a
            # result = take!(output_channel)
            # @assert length(result)==length(freqs_probe)
            # estimates = zip(freqs_probe, result)
            # println.(estimates)
        end
    catch
        @info "Encountered an error in the data consumer loop. Call `errormonitor` on the relevant task to see the full error."
        rethrow()
    end
end
export schedule_data_consumer!