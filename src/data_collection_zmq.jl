using ZMQ

# reinterpret(ComplexF32, msg) is equivalent to np.frombuffer(msg, dtype=np.complex64)

# We use PUB sockets in python. 
# GNU radio says that PUB and SUB formes a socket pair

ip_addr = "tcp://127.0.0.1:9001"
create_sockets() = (Socket(SUB), Socket(SUB), Socket(SUB), Socket(SUB))
export create_sockets

activate_sockets!(socs, ips=ip_addrs) =
    for (ip, soc) in zip(ips, socs)
        connect(soc, ip)
        subscribe(soc)
    end
export activate_sockets!

"""
    kernel_read_data!(voltages_channel, sockets, reciever_buffers)
"""
function kernel_read_data!(voltages_channel, sockets,
    reciever_buffers, T_voltages_sent, read_request_size
)
    # Hoping and praying that we are reading from each socket 
    # at the same time, and able to capture all incoming data.
    @sync begin
        Threads.@spawn reciever_buffers[1] .= recv(sockets[1], Vector{T_voltages_sent})
        Threads.@spawn reciever_buffers[2] .= recv(sockets[2], Vector{T_voltages_sent})
        Threads.@spawn reciever_buffers[3] .= recv(sockets[3], Vector{T_voltages_sent})
        Threads.@spawn reciever_buffers[4] .= recv(sockets[4], Vector{T_voltages_sent})
    end

    for i in 1:read_request_size
        measurement_set = (
            reciever_buffers[2][i],
            reciever_buffers[1][i],
            reciever_buffers[3][i],
            reciever_buffers[4][i]
        )
        put!(voltages_channel, measurement_set)
    end
end
export kernel_read_data!