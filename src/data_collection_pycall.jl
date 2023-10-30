"""
	setup_mcc128(fs, daqhats, daqhats_utils)  -->  setup_params
"""
function setup_mcc128(daqhats, daqhats_utils; 
    fs=25_000, 
    samples_per_channel=1024, 
    read_request_size=2096,
    options=daqhats.OptionFlags.CONTINUOUS
)
    channels = [2,3]
    channel_mask = daqhats_utils.chan_list_to_mask(channels)
    num_channels = length(channels)
    channels2 = [0,1]
    channel_mask2 = daqhats_utils.chan_list_to_mask(channels2)
   
    hat = daqhats.mcc128(7)
    hat2 = daqhats.mcc128(2)
   
    input_mode = daqhats.AnalogInputMode.DIFF
    input_range = daqhats.AnalogInputRange.BIP_10V
    
    hat.a_in_mode_write(input_mode)
    hat.a_in_range_write(input_range)
   
    hat2.a_in_mode_write(input_mode)
    hat2.a_in_range_write(input_range)
    
    scan_rate = fs

    # When doing a continuous scan, the timeout value will be ignored in the
    # call to a_in_scan_read because we will be requesting that all available
    # samples (up to the default buffer size) be returned.
    timeout = 5.0
	
    actual_scan_rate = hat.a_in_scan_actual_rate(num_channels, scan_rate)
    actual_scan_rate2 = hat2.a_in_scan_actual_rate(num_channels, scan_rate)

	# Because we start the scan here, every 
	# `setup_mcc128` has to be matched by a 
	# `teardown_mcc128` to snap out of the scan
	hat.a_in_scan_start(channel_mask, samples_per_channel, scan_rate, options)
	hat2.a_in_scan_start(channel_mask2, samples_per_channel, scan_rate, options)
	
	setup_parameters = (;daqhats, daqhats_utils, hat, hat2, read_request_size, timeout, options, num_channels, channel_mask, channel_mask2, samples_per_channel, scan_rate)
	return setup_parameters
end
export setup_mcc128

function teardown_mcc128(setup_parameters)
	setup_parameters.hat.a_in_scan_stop()
    setup_parameters.hat.a_in_scan_cleanup()       
    setup_parameters.hat2.a_in_scan_stop()
    setup_parameters.hat2.a_in_scan_cleanup() 
end
export teardown_mcc128

function get_single_measurement(daqhats, daqhats_utils;
    fs=25_000, 
    samples_per_channel=1024, 
    read_request_size=2096,
    options=daqhats.OptionFlags.CONTINUOUS
)
    channels = [2,3]
    channel_mask = daqhats_utils.chan_list_to_mask(channels)
    num_channels = length(channels)
    channels2 = [0,1]
    channel_mask2 = daqhats_utils.chan_list_to_mask(channels2)


    input_mode = daqhats.AnalogInputMode.DIFF
    input_range = daqhats.AnalogInputRange.BIP_10V

    hat = daqhats.mcc128(7)
    hat2 = daqhats.mcc128(2)

    hat.a_in_mode_write(input_mode)
    hat.a_in_range_write(input_range)

    hat2.a_in_mode_write(input_mode)
    hat2.a_in_range_write(input_range)

    scan_rate = fs

    # When doing a continuous scan, the timeout value will be ignored in the
    # call to a_in_scan_read because we will be requesting that all available
    # samples (up to the default buffer size) be returned.
    timeout = 5.0


    local read_result, read_result2  # Try block introduces new cope, need to declare here
    try
        hat.a_in_scan_start(channel_mask, samples_per_channel, scan_rate, options)
        hat2.a_in_scan_start(channel_mask2, samples_per_channel, scan_rate, options)
        read_result = hat.a_in_scan_read(read_request_size, timeout)
        read_result2 = hat2.a_in_scan_read(read_request_size, timeout)
    finally
        print("\n Starting daqhat-cleanup ... ")
        hat.a_in_scan_stop()
        hat.a_in_scan_cleanup()       
        hat2.a_in_scan_stop()
        hat2.a_in_scan_cleanup()
        print("finnished\n")
    end
    return read_result, read_result2#pyconvert(Vector{Float32}, read_result.data)
end
export get_single_measurement

function kernel_single_measurement!(voltages_channel, daqhats, daqhats_utils, PythonCall)
    read_result, read_result2 = get_single_measurement(daqhats, daqhats_utils)
    @info "Data read"
    if length(read_result.data) != length(read_result.data)
        @warn "The two hats have different length data"
    end
    N = length(read_result.data)
    for i in 0:2:N-2  # -1 for 0-based index, -1 because we take 2 elements at a time.
        sample_set_python = (read_result.data[i], read_result.data[i+1], read_result2.data[i], read_result2.data[i+1])
        sample_set_julia = Base.Fix1(PythonCall.pyconvert, Float32).(sample_set_python)
        put!(voltages_channel, sample_set_julia)
    end
    @info "Finnished"
end
export kernel_single_measurement!

#! This is broken ATM
function schedule_data_producer!(voltages_channel, keep_running, daqhats, daqhats_utils, PythonCall; 
    fs=25_000, 
    samples_per_channel=1024, 
    read_request_size=2096,
    options=daqhats.OptionFlags.CONTINUOUS
)
    pyconvert = PythonCall.pyconvert
    # Perform teardown and setup again if inner loop breaks, 
    # as long as `keep_running` is true.
    Threads.@spawn while keep_running[]
        p = setup_mcc128(daqhats, daqhats_utils, fs, samples_per_channel, read_request_size, options)

        try
            while true
                read_result = p.hat.a_in_scan_read(p.read_request_size, p.timeout)
                if !pyconvert(Bool, read_result.running)
                    pyconvert(Bool, read_result.buffer_overrun)     &&  (@warn "Buffer overrun on hat 1.")
                    pyconvert(Bool, read_result.hardware_overrun)   &&  (@warn "Hardware overrun on hat 1.")
                    @warn "Hat 1 is not running. Breaking data collection loop."
                    break
                end

                read_result2 = p.hat2.a_in_scan_read(p.read_request_size, p.timeout)
                if !parse(Bool, read_result2.running|>string|>lowercase)
                    parse(Bool, read_result2.buffer_overrun|>string|>lowercase)  &&  (@warn "Buffer overrun on hat 2.")
                    parse(Bool, read_result2.hardware_overrun|>string|>lowercase)  &&  (@warn "Hardware overrun on hat 2.")
                    @warn "Hat 2 is not running. Breaking data collection loop."
                    break
                end
                samples_read_per_channel = length(read_result.data) / p.num_channels |> round |> Int

                #sanity-check. This should be removed if the warning is never printed.
                samples_read_per_channel2 = length(read_result2.data) / p.num_channels |> round |> Int
                if samples_read_per_channel != samples_read_per_channel2
                    @warn "A different number of samples was read for channel1 and channel2"
                end

                if samples_read_per_channel > 0
                    for i in 0:samples_read_per_channel-1  
                        #! BUG: Code written assuming we iterate over samples_read, not per channel!
                        # We collect a sample from each electrode into a `sample_set`
                        sample_set_python = (read_result.data[i], read_result.data[i+1], read_result2.data[i], read_result2.data[i+1])
                        
                        # We convert the data from python datatypes to julia datatypes
                        sample_set_julia = Base.Fix1(pyconvert, Float32).(sample_set_python)
                        
                        # We put individual sample-sets into `data_channel`, 
                        # for consuption by another thread/task
                        
                        put!(voltages_channel, sample_set_julia)
                    end
                end
            end
        finally
            teardown_mcc128(p)
        end
    end
    @info "Finnished with data producer loop."
end
export schedule_data_producer!


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
