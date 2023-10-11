module PSDTools
include("amplitude_extraction.jl")# Write your package code here.


using Dates
const main_event = Threads.Event()
export main_event

function my_task_generator()
	Threads.@spawn begin
		while true
			wait(main_event)
			println(stdout, "Second: $(Second(now()))")
			t = time()
			while time()-t < 1
				nothing
			end
		end
	end
end
export my_task_generator

end
