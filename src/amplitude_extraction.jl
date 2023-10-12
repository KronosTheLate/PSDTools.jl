using EasyFFTs
using DSP

#rms(x) = √(sum(x->x^2, x)/length(x))
#export rms

time_function(f, repetitions) = minimum(@elapsed(f()) for _ in 1:repetitions)
export time_function

function make_filter_bandpass(f_center, filter_order, bandwidth; fs)
	f_center > 0 || throw(ArgumentError("f_center is not greater than 0"))
	f_center < fs/2 || throw(ArgumentError("f_center=$f_center is not smaller than the Nyquist frequency $(fs/2)"))
    responsetype = Bandpass(
		max(f_center-bandwidth/2, 1e-10), 
		min(f_center+bandwidth/2, prevfloat(fs/2)); 
		fs
	)
    designmethod = Butterworth(filter_order)
    filter = digitalfilter(responsetype, designmethod)
	return filter
end
export make_filter_bandpass

# It is important to split up making the estimator and 
# calculating the estimate, to allow accurate timings.
function make_estimator_filter_and_RMS(f_probe, filter_order, bandwidth, filter_function=filt; fs)
	filter = make_filter_bandpass(f_probe, filter_order, bandwidth; fs)
	function f(signal)
		signal_filtered = filter_function(filter, signal)
	    A_est = rms(signal_filtered) * √2
		return A_est
	end
	return f
end
export make_estimator_filter_and_RMS

function make_estimator_filter_and_RMS_corrected(signal, f_probe, filter_order, bandwidth, filter_function=filt; fs)
	filter = make_filter_bandpass(f_probe, filter_order, bandwidth; fs)
	
	ts = range(0, step=1/fs, length=length(signal))
	dummy_signal = sin.(2π * f_probe * ts)  # Known amplitude 1
	dummy_signal_filtered = filter_function(filter, dummy_signal)
	unwanted_factor = rms(dummy_signal_filtered) * √2  # 1 for zero attenuation, less in practice
	
	function f(signal)
		signal_filtered = filter_function(filter, signal)
		A_est = rms(signal_filtered) * √2 / unwanted_factor
		return A_est
	end
	return f
end
export make_estimator_filter_and_RMS_corrected

# k is the number of periods a signal of f=f_probe has 
# inside the full signal duration
# With the DFT, we restrict n_oscillations to an integer. 
# We are now free of that constraint!

# DFT: sum(signal(n+1)*cis(-2π*k*n/N) for n in eachindex(signal))
function dft_probe(sig, f_probe, fs)
	N = length(sig)
	signal_duration = 1/fs * length(sig)
	T_probe = 1/f_probe
	n_oscillations = signal_duration/T_probe
	k = n_oscillations
	return abs(sum(sig[n]*cis(-2π*k*(n-1)/N) for n in eachindex(sig))/N*2)
end
export dft_probe