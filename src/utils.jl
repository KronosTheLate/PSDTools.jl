"""
    calculate_POC(v_x1, v_x2, v_y1, v_y2, L_x=1, L_y=1)

Given input voltages `v_x1, v_x2, v_y1, v_y2` and 
electrical center `L_x` and `L_y`, calculate the Position On Chip.
"""
function calculate_POC(v_x1, v_x2, v_y1, v_y2, L_x=1, L_y=1)
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

toggle!(x::Ref{Bool}) = (x[] = !x[]; x[])
export toggle!

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

