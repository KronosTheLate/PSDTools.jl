using ZMQ

# reinterpret(ComplexF32, msg) is equivalent to np.frombuffer(msg, dtype=np.complex64)

# We use PUB sockets in python. 
# GNU radio says that PUB and SUB formes a socket pair


ip_addrs = (
    "tcp://127.0.0.1:1234",
    "tcp://127.0.0.1:12345",
    "tcp://127.0.0.1:123456",
    "tcp://127.0.0.1:1234567",
)
create_sockets() = (Socket(SUB), Socket(SUB), Socket(SUB), Socket(SUB))
export create_sockets

activate_sockets!(socs, ips=ip_addrs) = for (ip, soc) in zip(ips, socs)
    connect(soc, ip)
    subscribe(soc)
end
export activate_sockets!

read_request_size = 2096
reciever_buffers_encoded = (
    zeros(UInt8, read_request_size*8),
    zeros(UInt8, read_request_size*8),
    zeros(UInt8, read_request_size*8),
    zeros(UInt8, read_request_size*8)
)

voltage_encoded_type = ComplexF32
voltage_decoded_type = Float32
decode(data, T_i=voltage_encoded_type, T_f=voltage_decoded_type) = T_f.(reinterpret(T_i, data))
reciever_buffers_decoded = (
    zeros(voltage_decoded_type, read_request_size),
    zeros(voltage_decoded_type, read_request_size),
    zeros(voltage_decoded_type, read_request_size),
    zeros(voltage_decoded_type, read_request_size)
)

"""
    kernel_read_data!(voltages_channel)

# Optional keyword arguments
- `reciever_buffers_encoded`
- `reciever_buffers_decoded`
"""
function kernel_read_data!(voltages_channel, sockets, 
    reciever_buffers_encoded=reciever_buffers_encoded, 
    reciever_buffers_decoded=reciever_buffers_decoded
)
    # Hoping and praying that we are reading from each socket 
    # at the same time, and able to capture all incoming data.
    @sync begin
        Threads.@spawn reciever_buffers_encoded[1] .= recv(sockets[1])
        Threads.@spawn reciever_buffers_encoded[2] .= recv(sockets[2])
        Threads.@spawn reciever_buffers_encoded[3] .= recv(sockets[3])
        Threads.@spawn reciever_buffers_encoded[4] .= recv(sockets[4])
    end
    
    @sync begin
        Threads.@spawn reciever_buffers_decoded[1] .= decode(reciever_buffers_encoded[1])
        Threads.@spawn reciever_buffers_decoded[2] .= decode(reciever_buffers_encoded[2])
        Threads.@spawn reciever_buffers_decoded[3] .= decode(reciever_buffers_encoded[3])
        Threads.@spawn reciever_buffers_decoded[4] .= decode(reciever_buffers_encoded[4])
    end

    for i in 1:read_request_size
        meas_set = (
            reciever_buffers_decoded[1][i], 
            reciever_buffers_decoded[2][i], 
            reciever_buffers_decoded[3][i], 
            reciever_buffers_decoded[4][i]
        )
        put!(voltages_channel, meas_set)
    end
end
export kernel_read_data!