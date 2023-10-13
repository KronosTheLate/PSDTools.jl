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