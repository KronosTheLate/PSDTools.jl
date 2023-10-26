using PythonCall

#=
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
=#
daqhats_utils = pyimport("daqhats_utils")
channels = [2,3]
channel_mask = daqhats_utils.chan_list_to_mask(channels)
channels2 = [0,1]
channel_mask2 = daqhats_utils.chan_list_to_mask(channels2)
#num_channels = length(channels)


    input_mode = AnalogInputMode.DIFF
    input_range = AnalogInputRange.BIP_10V

    samples_per_channel = 1024

    options = OptionFlags.CONTINUOUS

    scan_rate = 50000

    # Select an MCC 128 HAT device to use.
    hat = mcc128(7)
    hat2 = mcc128(2)
   
    # Set both hats to the specified input mode and input range
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

        # Return the data    
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


#=
Python code:

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
    hat = mcc128(7)
    hat2 = mcc128(2)
   
    # Set both hats to the specified input mode and input range
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

        # Return the data    
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
