module PSDTools

include("amplitude_extraction.jl")
# include("read_data_mcc.jl")
include("utils.jl")
include("kernels.jl")
include("kernels_new.jl")
include("data_collection_zmq_without_timestamps.jl")


# Notes about implementation details:

# Assumptions about data
	# We will generally store data in a `Tuple`. 
		# Tuples representing positions will assume the 
		# first element to represent x, and the 
		# second element to represent y

		# Tuples representing voltages will assume the 
		# elements to be ordered, and respectively 
		# represent v_x1, v_x2, v_y1, v_y2

# Tuple vs Vector for small numbers of elements
	# We will often do `tuple((my_expression for i in 1:4)...)`. 
	# This does not allocate up to 32 elements, so that below 
	# 32 element this is faster than the more typical 
	# `[my_expression for i in 1:4]`. To make the code more 
	# readable, we define `collect_tuple`, so that 
	# collect_tuple(i for i in 1:10) == tuple((i for i in 1:10)...)
end
