using LinearAlgebra
using DataStructures
using Base.Iterators
using EasyFFTs
using DSP

import Base.push!
export amplitude
#rms(x) = √(sum(x->x^2, x)/length(x))
#export rms

time_function(f, repetitions) = minimum(@elapsed(f()) for _ in 1:repetitions)
export time_function

function make_filter_bandpass(f_center, filter_order, bandwidth; fs)
	f_center > 0 || throw(ArgumentError("f_center is not greater than 0"))
	f_center < fs/2 || throw(ArgumentError("f_center=$f_center is not smaller than the Nyquist frequency $(fs/2)"))
	min_freq = if f_center-bandwidth/2 > 0.0
		f_center-bandwidth/2
	else
		@warn "f_center - bandwidth/2 is smaller than or equal to zero.
		Setting the lower edge of passband to `nextfloat(0.0)`"
		nextfloat(0.0)
	end

	max_freq = if f_center+bandwidth/2 < fs/2
		f_center+bandwidth/2
	else
		@warn "f_center + bandwidth/2 is greater than or equal to fs/2.
		Setting the upper edge of passband to `prevfloat(fs/2)`"
		prevfloat(fs/2)
	end

    responsetype = Bandpass(min_freq, max_freq; fs)

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


##!====================================================================================!##
##!====================================================================================!##
##!====================================================================================!##
#
struct FiltRMSProbes{T}
	fs::Int
	n_filter::Int
	n_samples::Int
	stateful_filters::NTuple{4, DF2TFilter{SecondOrderSections{:z, T, T}}}  # Reversed, as this is what is used in dot product. From convolution
	buffers_filtered_samples::NTuple{4, CircularBuffer{T}}
	internal_buffer_input_samples::Vector{Vector{T}}
	internal_buffer_filtered_samples::Vector{Vector{T}}
end
export FiltRMSProbes

function FiltRMSProbes(fs, n_filter, n_samples, f_probe, f_bandwidth, T=typeof(1.0))
	f = make_filter_bandpass(f_probe, n_filter, f_bandwidth; fs)
	stateful_filters = (
		DF2TFilter(SecondOrderSections(f)), 
		DF2TFilter(SecondOrderSections(f)), 
		DF2TFilter(SecondOrderSections(f)), 
		DF2TFilter(SecondOrderSections(f)), 
	)
	buffers_filtered_samples = (
		CircularBuffer{T}(n_samples),
		CircularBuffer{T}(n_samples),
		CircularBuffer{T}(n_samples),
		CircularBuffer{T}(n_samples)
	)
	internal_buffer_input_samples = [zeros(T, 1), zeros(T, 1), zeros(T, 1), zeros(T, 1)]
	internal_buffer_filtered_samples = [zeros(T, 1), zeros(T, 1), zeros(T, 1), zeros(T, 1)]
	return FiltRMSProbes{T}(fs, n_filter, n_samples, stateful_filters, buffers_filtered_samples, internal_buffer_input_samples, internal_buffer_filtered_samples)
end

function push!(x::FiltRMSProbes, datapoints::NTuple{4, <:Number})
	for i in eachindex(datapoints)
		x.internal_buffer_input_samples[i][1] = datapoints[i]
		filt!(x.internal_buffer_filtered_samples[i], x.stateful_filters[i], x.internal_buffer_input_samples[i])
		push!(x.buffers_filtered_samples[i], x.internal_buffer_filtered_samples[i][1])
	end
	return nothing
end

function amplitudes(x::FiltRMSProbes)
	# We intentionally do not divide by √2, as the position estiamtes are the same
	return rms.(x.buffers_filtered_samples)
end
##!====================================================================================!##
##!====================================================================================!##
##!====================================================================================!##
# k is the number of periods a signal of f=f_probe has 
# inside the full signal duration
# With the DFT, we restrict n_oscillations to an integer. 
# We are now free of that constraint!

# DFT: sum(signal(n+1)*cis(-2π*k*n/N) for n in eachindex(signal))
function dft_probe_old(sig, f_probe, fs)
	blocksize = length(sig)
	signal_duration = 1/fs * length(sig)
	T_probe = 1/f_probe
	n_oscillations = signal_duration/T_probe
	k = n_oscillations
	return abs(sum(sig[n]*cis(-2π*k*(n-1)/blocksize) for n in eachindex(sig))/N*2)
end
export dft_probe_old

# DFT: sum(signal(n+1)*cis(-2π*k*n/N) for n in eachindex(signal))
function dft_probe(sig, f_probe, fs)
	N_osc_of_f_probe_per_sample_period = f_probe/fs
	the_sum = sum(sig[n]*cispi(-2*N_osc_of_f_probe_per_sample_period*(n-1)) for n in eachindex(sig))
	return abs(the_sum/length(sig)*2)
end
export dft_probe

# We need this version of DFTProbe to fulfill the API that will be 
# required by the new OnlineDFTProbe
mutable struct DFTProbe{T}
	fs::Int
	f_probe::Int
	blocksize::Int
	dft_exps::Vector{T}
	datapoints::CircularBuffer{T}
end
export DFTProbe

function DFTProbe(fs, f_probe, blocksize, T=ComplexF32)
	N_osc_of_f_probe_per_fs_period = f_probe//fs
	dft_exps = T[cispi(-2*N_osc_of_f_probe_per_fs_period*j) for j in 0:blocksize-1]
	datapoints = CircularBuffer{T}(blocksize)

	# Initialize to zeros. Means first few measurements are trash
	# but it means we do not have to deal with edge-case of semi-full buffer
	# Edge-case needs handling in hot-loop --> performance hit
	foreach(_->push!(datapoints, zero(T)), 1:blocksize)
	return DFTProbe{T}(fs, f_probe, blocksize, dft_exps, datapoints)
end

push!(fp::DFTProbe, datapoint) = push!(fp.datapoints, datapoint)
push!(fp::DFTProbe, datapoints::AbstractVector) = foreach(datapoints) do datapoint
	push!(fp.datapoints, datapoint)
end

amplitude(fp::DFTProbe) = abs(sum(fp.datapoints[i] * fp.dft_exps[i] for i in 1:fp.blocksize)) / fp.blocksize * 2

# Requires new samples as input
mutable struct OnlineDFTProbe{T}
	fs::Int
	f_probe::Int
	blocksize::Int  		# Used for getting amplitude
	#signal_duration # computed from fs and blocksize
	#n_oscillations
	dft_exps::Vector{T}
	dft_exps_ind::Int
	terms_in_sum_buffer::CircularBuffer{T}  # constructed from blocksize
	sum_of_terms::T
end
export OnlineDFTProbe

import Base.show
function show(io::IO, ofp::OnlineDFTProbe)
	print(io, string("Online DFT probe. fs = ", ofp.fs, ", f_probe = ", ofp.f_probe, " blocklength = ", ofp.blocksize))
end

function OnlineDFTProbe(fs::Int, f_probe::Int, blocksize::Int, T=ComplexF32)

	N_osc_of_f_probe_per_fs_period = f_probe//fs
	N_osc_of_fs_per_f_probe_period = inv(N_osc_of_f_probe_per_fs_period)
	dft_exponentials_periodicity_in_samples = N_osc_of_fs_per_f_probe_period.num * N_osc_of_fs_per_f_probe_period.den
	
	dft_exps = T[cispi(-2*N_osc_of_f_probe_per_fs_period*j) for j in 0:dft_exponentials_periodicity_in_samples-1]

	dft_exps_ind = 1
	terms_in_sum_buffer = CircularBuffer{T}(blocksize)

	# Initialize to zeros. Means first few measurements are trash
	# but it means we do not have to deal with edge-case of semi-full buffer
	# Edge-case needs handling in hot-loop --> performance hit
	foreach(_->push!(terms_in_sum_buffer, zero(T)), 1:blocksize)

	sum_of_terms = zero(T)
	#return typeof(sum_of_terms)
	return OnlineDFTProbe{T}(fs, f_probe, blocksize, dft_exps, dft_exps_ind, terms_in_sum_buffer, sum_of_terms)
end

function push!(ofp::OnlineDFTProbe, datapoint::Number)
	ofp.sum_of_terms -= first(ofp.terms_in_sum_buffer)
	
	new_term = datapoint * ofp.dft_exps[ofp.dft_exps_ind]
	
	# Perhaps length(ofp.dft_exps) should be stored in field in struct
	ofp.dft_exps_ind = ofp.dft_exps_ind % length(ofp.dft_exps) + 1

	push!(ofp.terms_in_sum_buffer, new_term)
	ofp.sum_of_terms += new_term
	return nothing
end

function push!(ofp::OnlineDFTProbe, datapoints::AbstractVector)
	for datapoint in datapoints
		push!(ofp, datapoint)
	end
end

amplitude(ofp::OnlineDFTProbe) = abs(ofp.sum_of_terms) / ofp.blocksize * 2

## A version of OnlineDFTProbe that takes 4 voltages, looking for the same freq in all
mutable struct OnlineDFTProbes{T}
	fs::Int
	f_probe::Int
	blocksize::Int  		# Used for getting amplitude
	#signal_duration # computed from fs and blocksize
	#n_oscillations
	dft_exps::Vector{Complex{T}}
	dft_exps_ind::Int
	terms_in_sum_buffers::NTuple{4, CircularBuffer{Complex{T}}}
	sums_of_terms::Vector{Complex{T}}
	lock_sums_of_terms::ReentrantLock
end
export OnlineDFTProbes

function show(io::IO, ofp::OnlineDFTProbes)
	print(io, string("Set of 4 Online DFT probes. fs = ", ofp.fs, ", f_probe = ", ofp.f_probe, " blocklength = ", ofp.blocksize))
end

function OnlineDFTProbes(fs::Int, f_probe::Int, blocksize::Int, T=Float32)

	N_osc_of_f_probe_per_fs_period = f_probe//fs
	N_osc_of_fs_per_f_probe_period = inv(N_osc_of_f_probe_per_fs_period)
	dft_exponentials_periodicity_in_samples = N_osc_of_fs_per_f_probe_period.num * N_osc_of_fs_per_f_probe_period.den
	
	dft_exps = Complex{T}[cispi(-2*N_osc_of_f_probe_per_fs_period*j) for j in 0:dft_exponentials_periodicity_in_samples-1]

	dft_exps_ind = 1
	terms_in_sum_buffers = (
		CircularBuffer{Complex{T}}(blocksize),
		CircularBuffer{Complex{T}}(blocksize),
		CircularBuffer{Complex{T}}(blocksize),
		CircularBuffer{Complex{T}}(blocksize)
	)

	# Initialize to zeros. Means first few measurements are trash
	# but it means we do not have to deal with edge-case of semi-full buffer
	# Edge-case needs handling in hot-loop --> performance hit
	for terms_in_sum_buffer in terms_in_sum_buffers
		foreach(_->push!(terms_in_sum_buffer, zero(Complex{T})), 1:blocksize)
	end

	sums_of_terms = [zero(Complex{T}), zero(Complex{T}), zero(Complex{T}), zero(Complex{T})]
	lock_sums_of_terms = ReentrantLock()
	#return typeof(sum_of_terms)
	return OnlineDFTProbes{T}(fs, f_probe, blocksize, dft_exps, dft_exps_ind, terms_in_sum_buffers, sums_of_terms, lock_sums_of_terms)
end

function push!(ofp::OnlineDFTProbes{T}, datapoints::NTuple{4, T}) where {T<:AbstractFloat}
	new_terms = datapoints .* ofp.dft_exps[ofp.dft_exps_ind]
	ofp.dft_exps_ind = ofp.dft_exps_ind % length(ofp.dft_exps) + 1

	lock(ofp.lock_sums_of_terms) do
		ofp.sums_of_terms .+= new_terms
		for i in eachindex(ofp.sums_of_terms)
			ofp.sums_of_terms[i] -= first(ofp.terms_in_sum_buffers[i])
		end
	end

	push!.(ofp.terms_in_sum_buffers, new_terms)
	return nothing
end

function push!(ofp::OnlineDFTProbes, datapointss::AbstractVector{NTuple{4, A}}) where {A<:Number}
	lock(ofp.lock_sums_of_terms)
	for datapoints in datapointss
		
		new_terms = datapoints .* ofp.dft_exps[ofp.dft_exps_ind]
		ofp.dft_exps_ind = ofp.dft_exps_ind % length(ofp.dft_exps) + 1

		ofp.sums_of_terms .+= new_terms
		for i in eachindex(ofp.sums_of_terms)
			ofp.sums_of_terms[i] -= first(ofp.terms_in_sum_buffers[i])
		end

		push!.(ofp.terms_in_sum_buffers, new_terms)
	end
	unlock(ofp.lock_sums_of_terms)
	return nothing
end

function amplitudes(ofp::OnlineDFTProbes)
	lock(ofp.lock_sums_of_terms)
	return_val = (
		abs(ofp.sums_of_terms[1]) / ofp.blocksize * 2,
		abs(ofp.sums_of_terms[2]) / ofp.blocksize * 2,
		abs(ofp.sums_of_terms[3]) / ofp.blocksize * 2,
		abs(ofp.sums_of_terms[4]) / ofp.blocksize * 2
	)
	unlock(ofp.lock_sums_of_terms)
	return return_val
end
export amplitudes


##!=============================================================================================================!##
##!==============================================               ================================================!##
##!=============================================================================================================!##

## A version of DFTProbe that takes 4 voltages, looking for the same freq in all
mutable struct DFTProbes{T}
	fs::Int
	f_probe::Int
	blocksize::Int  		# Used for getting amplitude
	#signal_duration # computed from fs and blocksize
	#n_oscillations
	dft_exps::Vector{Complex{T}}
	voltages_buffers::NTuple{4, CircularBuffer{T}}
	lock_voltages_buffers::ReentrantLock
end
export DFTProbes

function show(io::IO, ofp::DFTProbes)
	print(io, string("Set of 4 DFT probes. fs = ", ofp.fs, ", f_probe = ", ofp.f_probe, " blocklength = ", ofp.blocksize))
end

function DFTProbes(fs::Int, f_probe::Int, blocksize::Int, T=Float32)

	N_osc_of_f_probe_per_fs_period = f_probe//fs
	
	dft_exps = Complex{T}[cispi(-2*N_osc_of_f_probe_per_fs_period*j) for j in 0:blocksize-1]

	voltages_buffers = (
		CircularBuffer{T}(blocksize),
		CircularBuffer{T}(blocksize),
		CircularBuffer{T}(blocksize),
		CircularBuffer{T}(blocksize)
	)

	# Initialize to zeros. Means first few measurements are trash
	# but it means we do not have to deal with edge-case of semi-full buffer
	# Edge-case needs handling in hot-loop --> performance hit
	for voltages_buffer in voltages_buffers
		foreach(_->push!(voltages_buffer, zero(Complex{T})), 1:blocksize)
	end
	lock_voltages_buffers = ReentrantLock()
	return DFTProbes{T}(fs, f_probe, blocksize, dft_exps, voltages_buffers, lock_voltages_buffers)
end

function push!(dftps::DFTProbes{T}, datapoints::NTuple{4, T}) where {T<:Number}
	lock(dftps.lock_voltages_buffers)
	push!.(dftps.voltages_buffers, datapoints)
	unlock(dftps.lock_voltages_buffers)
	return nothing
end

function push!(dftps::DFTProbes, datapointss::AbstractVector)
	lock(dftps.lock_voltages_buffers)
	for datapoints in datapointss
		push!(dftps, datapoints)
	end
	unlock(dftps.lock_voltages_buffers)
	return nothing
end

function amplitudes(dftps::DFTProbes)
	lock(dftps.lock_voltages_buffers) do
		return (
			abs(dftps.voltages_buffers[1] ⋅ dftps.dft_exps) / dftps.blocksize * 2,
			abs(dftps.voltages_buffers[2] ⋅ dftps.dft_exps) / dftps.blocksize * 2,
			abs(dftps.voltages_buffers[3] ⋅ dftps.dft_exps) / dftps.blocksize * 2,
			abs(dftps.voltages_buffers[4] ⋅ dftps.dft_exps) / dftps.blocksize * 2
		)
	end
end