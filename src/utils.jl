using OpenSSH_jll

"""
    calculate_POC(v_x1, v_x2, v_y1, v_y2, L_x=1, L_y=1)

Given input voltages `v_x1, v_x2, v_y1, v_y2` and 
electrical center `L_x` and `L_y`, calculate the Position On Chip.
"""
function calculate_POC(v_x1, v_x2, v_y1, v_y2, L_x=6.82, L_y=6.82)
	# from datasheet
	v_sum = v_x1+v_x2+v_y1+v_y2
	x = (v_x2+v_y1 - (v_x1+v_y2))/v_sum * L_x/2
	y = (v_x2+v_y2 - (v_x1+v_y1))/v_sum * L_y/2
	return (x, y)
end
export calculate_POC

"""
    calculate_POC_error(pos_est, pos_true)

Given two positions, calculate the distance between them.
It is assumed that the positions store 
the positions in fields `x` and `y`, so that 
`pos_est.x`, `pos_est.y`, `pos_true.x`, `pos_true.y`
"""
function calculate_POC_error(pos_est, pos_true)
	hypot(pos_est[1]-pos_true[1], pos_est[2]-pos_true[2])
end
export calculate_POC_error

"""
    tuple_collect(gen)

Iterates over generator `gen`, collecting the elements 
into a tuple. Equivalent to tuple(gen...).

Main usecase is turning
`tuple((i for i in 1:10)...)`
into 
`collect_tuple(i for i in 1:10)`
"""
collect_tuple(gen::Base.Generator) = tuple(gen...)
export collect_tuple

import Base.empty!
"""
    empty!(c)

Empty a Channel `c`. Returns the number of elements removed.
"""
function Base.empty!(c::Channel)
    counter = 0
    while isready(c)
        take!(c)
        counter += 1
    end
    return counter
end

toggle!(t::Union{Ref{Bool}, Threads.Atomic{Bool}}, final_state=!t[]) = (t[] = final_state)
export toggle!

function define_lamps()
    lamp1 =   (f=7.5e3,   As=(1, 8, 3, 4))
    lamp1_2 = (f=15e3,    As=(1, 8, 3, 4) .* 10^-2.5)
    lamp2 =   (f=10.25e3, As=(4, 3, 8, 1) .* 10^-0.5)
    lamp2_2 = (f=20.5e3,  As=(4, 3, 8, 1) .* 10^-3.5)
    lamp_dc = (f=0     ,  As=(1, 1, 1, 1) .* 10^1)
    lamps = (lamp1, lamp1_2, lamp2, lamp2_2, lamp_dc)
    return lamps
end

# >>>>>>>>>>>>>>>> Copied code from RemoteREPL.jl begin >>>>>>>>>>>> #
# This function will be used to automatically forward a port via ssh, 
# and maybie to launch the python command from within the julia script
function comm_pipeline(cmd::Cmd)
    errbuf = IOBuffer()
    proc = run(pipeline(cmd, stdout=errbuf, stderr=errbuf),
               wait=false)
    # TODO: Kill this earlier if we need to reconnect in ensure_connected!()
    atexit() do
        kill(proc)
    end
    @async begin
        # Attempt to log any connection errors to the user
        wait(proc)
        errors = String(take!(errbuf))
        if !isempty(errors) || !success(proc)
            @warn "Tunnel output" errors=Text(errors)
        end
    end
    proc
end
export comm_pipeline

"""
	ssh_tunnel(host, port, tunnel_interface, tunnel_port; ssh_opts=``)

The command run will be `ssh -L \$tunnel_interface:\$tunnel_port:localhost:\$port \$host`,
with some extra stuff that is probably smart to have.
"""
function ssh_tunnel(host, port, tunnel_interface, tunnel_port; ssh_opts=``)
    OpenSSH_jll.ssh() do ssh_exe
        # Tunnel binds locally to $tunnel_interface:$tunnel_port
        # The other end jumps through $host using the provided identity,
        # and forwards the data to $port on *itself* (this is the localhost:$port
        # part - "localhost" being resolved relative to $host)
        ssh_cmd = `$ssh_exe $ssh_opts -o ExitOnForwardFailure=yes -o ServerAliveInterval=60
                            -N -L $tunnel_interface:$tunnel_port:localhost:$port $host`
        @debug "Connecting SSH tunnel to remote address $host via ssh tunnel to $port" ssh_cmd
        comm_pipeline(ssh_cmd)
    end
end
export ssh_tunnel
# >>>>>>>>>>>>>>>> Copied code from RemoteREPL.jl end >>>>>>>>>>>> #

#=
function launch_pluto()
	try 
		@eval using Pluto
	catch e
		@warn "Encountered error while running `using Pluto`. Rethrowing."
		rethrow()
	end
	return Pluto.run(
		launch_browser=false, 				# no point in launching browser on the pi
		dismiss_update_notification=true, 	# If not, we will get annying notification often
		threads=4, 							# Use all the Pi's 4 threads
		capture_stdout=false, 				# Prefer printing to terminal. I find it cleaner
		require_secret_for_access = false,  # Allows pasting of URL without secret. Remove for production
		host="0.0.0.0",						# Allows connections from other computers that dont run the notebook-server
	)
end
export launch_pluto
=#

# A function `errormonitor` was introduced in Julia 1.7, 
# which is very useful for working with tasks. The LongTimeSupport 
# version of Julia is currently 1.6, and the only one with 
# prebuildt binaries for the Raspberry Pi platform. 
if VERSION < v"1.7-"
	@eval PSDTools begin
		"""
			errormonitor(task)
		"""
		function errormonitor(task)
			Base.Threads.@spawn try
				wait(task)
			catch err
				bt = catch_backtrace()
				showerror(stderr, err, bt)
				rethrow()
			end
		end
		export errormonitor
	end
end

# A macro `@lock` was introduced in v1.7.
if VERSION < v"1.7-"
	@eval PSDTools begin
		"""
		    @lock l expr

		Macro version of `lock(f, l::AbstractLock)` but with `expr` instead of `f` function.
		Expands to:
		```julia
		lock(l)
		try
		    expr
		finally
		    unlock(l)
		end
		```
		This is similar to using [`lock`](@ref) with a `do` block, but avoids creating a closure
		and thus can improve the performance.
		"""
		macro lock(l, expr)
		    quote
		        temp = $(esc(l))
		        lock(temp)
		        try
		            $(esc(expr))
		        finally
		            unlock(temp)
		        end
		    end
		end
		export @lock
	end
end

