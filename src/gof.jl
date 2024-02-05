# This file is a part of LegendSpecFits.jl, licensed under the MIT License (MIT).
"""
`gof.jl`
several functions to calculate goodness-of-fit (gof) for fits (-> `specfits.jl`):
"""

"""
    _prepare_data(h::Histogram{<:Real,1})
aux. function to convert histogram data into bin edges, bin width and bin counts
"""
function _prepare_data(h::Histogram{<:Real,1})
    # get bin center, width and counts from histogrammed data
    bin_edges = first(h.edges)
    counts = h.weights
    bin_centers = (bin_edges[begin:end-1] .+ bin_edges[begin+1:end]) ./ 2
    bin_widths = bin_edges[begin+1:end] .- bin_edges[begin:end-1]
    return counts, bin_widths, bin_centers
end


"""
    _get_model_counts(f_fit::Base.Callable,v_ml::NamedTuple,bin_centers::StepRangeLen,bin_widths::StepRangeLen)
aux. function to get modelled peakshape based on  histogram binning and best-fit parameter
"""
function _get_model_counts(f_fit::Base.Callable,v_ml::NamedTuple,bin_centers::StepRangeLen,bin_widths::StepRangeLen)
    model_func  = Base.Fix2(f_fit, v_ml) # fix the fit parameters to ML best-estimate
    model_counts = bin_widths.*map(energy->model_func(energy), bin_centers) # evaluate model at bin center (= binned measured energies)
    return model_counts
end



""" 
    p_value(f_fit::Base.Callable, h::Histogram{<:Real,1},v_ml::NamedTuple) 
calculate p-value based on least-squares
baseline method to get goodness-of-fit (gof)
# input:
 * `f_fit`function handle of fit function (peakshape)
 * `h` histogram of data
 * `v_ml` best-fit parameters
# returns:
 * `pval` p-value of chi2 test
 * `chi2` chi2 value
 * `dof` degrees of freedom
"""
function p_value(f_fit::Base.Callable, h::Histogram{<:Real,1},v_ml::NamedTuple)
    # prepare data
    counts, bin_widths, bin_centers = _prepare_data(h)

    # get peakshape of best-fit 
    model_counts = _get_model_counts(f_fit, v_ml, bin_centers,bin_widths)
    
    # calculate chi2
    chi2    = sum((model_counts[model_counts.>0]-counts[model_counts.>0]).^2 ./ model_counts[model_counts.>0])
    npar    = length(v_ml)
    dof    = length(counts[model_counts.>0])-npar
    pval    = ccdf(Chisq(dof),chi2)
    if any(model_counts.<=5)
              @warn "WARNING: bin with <=$(round(minimum(model_counts),digits=0)) counts -  chi2 test might be not valid"
    else  
         @debug "p-value = $(round(pval,digits=2))"
    end
    return pval, chi2, dof
end
export p_value


""" 
    p_value_LogLikeRatio(f_fit::Base.Callable, h::Histogram{<:Real,1},v_ml::NamedTuple)
alternative p-value via loglikelihood ratio
"""
function p_value_LogLikeRatio(f_fit::Base.Callable, h::Histogram{<:Real,1},v_ml::NamedTuple)
    # prepare data
    counts, bin_widths, bin_centers = _prepare_data(h)

    # get peakshape of best-fit 
    model_counts = _get_model_counts(f_fit, v_ml, bin_centers,bin_widths)
    
    # calculate chi2
    chi2    = sum((model_counts[model_counts.>0]-counts[model_counts.>0]).^2 ./ model_counts[model_counts.>0])
    npar    = length(v_ml)
    dof    = length(counts[model_counts.>0])-npar
    pval    = ccdf(Chisq(dof),chi2)
    if any(model_counts.<=5)
              @warn "WARNING: bin with <=$(minimum(model_counts)) counts -  chi2 test might be not valid"
    else  
         @debug "p-value = $(round(pval,digits=2))"
    end
    chi2   = 2*sum(model_counts.*log.(model_counts./counts)+model_counts-counts)
    pval   = ccdf(Chisq(dof),chi2)
return pval, chi2, dof
end
export p_value_LogLikeRatio

"""
    p_value_MC(f_fit::Base.Callable, h::Histogram{<:Real,1},ps::NamedTuple{(:peak_pos, :peak_fwhm, :peak_sigma, :peak_counts, :mean_background)},v_ml::NamedTuple,;n_samples::Int64=1000) 
alternative p-value calculation via Monte Carlo sampling. Warning: computational more expensive than p_vaule() and p_value_LogLikeRatio()
* Create n_samples randomized histograms. For each bin, samples are drawn from a Poisson distribution with λ = model peak shape (best-fit parameter)
* Each sample histogram is fit using the model function `f_fit`
* For each sample fit, the max. loglikelihood fit is calculated
% p value --> comparison of sample max. loglikelihood and max. loglikelihood of best-fit
"""
function p_value_MC(f_fit::Base.Callable, h::Histogram{<:Real,1},ps::NamedTuple{(:peak_pos, :peak_fwhm, :peak_sigma, :peak_counts, :mean_background)},v_ml::NamedTuple,;n_samples::Int64=1000)
    counts, bin_widths, bin_centers = _prepare_data(h) # get data 
   
    # get peakshape of best-fit and maximum likelihood value
    model_func  = Base.Fix2(f_fit, v_ml) # fix the fit parameters to ML best-estimate
    model_counts = bin_widths.*map(energy->model_func(energy), bin_centers) # evaluate model at bin center (= binned measured energies)
    loglike_bf = -hist_loglike(model_func,h) 

    # draw sample for each bin
    dists = Poisson.(model_counts) # create poisson distribution for each bin
    counts_mc_vec = rand.(dists,n_samples) # randomized histogram counts
    counts_mc = [ [] for _ in 1:n_samples ] #re-structure data_samples_vec to array of arrays, there is probably a better way to do this...
    for i = 1:n_samples
        counts_mc[i] = map(x -> x[i],counts_mc_vec)
    end
    
    # fit every sample histogram and calculate max. loglikelihood
    loglike_bf_mc = NaN.*ones(n_samples)
    h_mc = h # make copy of data histogram
    for i=1:n_samples
        h_mc.weights = counts_mc[i] # overwrite counts with MC values
        result_fit_mc, report = fit_single_peak_th228(h_mc, ps ; uncertainty=false) # fit MC histogram
        fit_par_mc   = result_fit_mc[(:μ, :σ, :n, :step_amplitude, :skew_fraction, :skew_width, :background)]
        model_func_sample  = Base.Fix2(f_fit, fit_par_mc) # fix the fit parameters to ML best-estimate
        loglike_bf_mc[i] = -hist_loglike(model_func_sample,h_mc) # loglikelihood for best-fit
    end

    # calculate p-value
    pval= sum(loglike_bf_mc.<=loglike_bf)./n_samples # preliminary. could be improved e.g. with interpolation
    return pval 
end
export p_value_MC

""" 
    residuals(f_fit::Base.Callable, h::Histogram{<:Real,1},v_ml::NamedTuple)
calculate bin-wise residuals and normalized residuals 
calcualte bin-wise p-value based on poisson distribution for each bin 
# input:
 * `f_fit`function handle of fit function (peakshape)
 * `h` histogram of data
 * `v_ml` best-fit parameters
# returns:
 * `residuals` difference: model - data (histogram bin count)
 * `residuals_norm` normalized residuals: model - data / sqrt(model)
 * `p_value_binwise` p-value for each bin based on poisson distribution
"""
function get_residuals(f_fit::Base.Callable, h::Histogram{<:Real,1},v_ml::NamedTuple)
    # prepare data
    counts, bin_widths, bin_centers = _prepare_data(h)

    # get peakshape of best-fit 
    model_counts = _get_model_counts(f_fit, v_ml, bin_centers,bin_widths)
    
    # calculate bin-wise residuals 
    residuals    = model_counts[model_counts.>0]-counts[model_counts.>0]
    sigma        = sqrt.(model_counts[model_counts.>0])
    residuals_norm = residuals./sigma

    # calculate something like a bin-wise p-value (in case that makes sense)
    dist = Poisson.(model_counts) # each bin: poisson distributed 
    cdf_value_low = cdf.(dist, model_counts.-abs.(residuals)) 
    cdf_value_up  = 1 .-cdf.(dist, model_counts.+abs.(residuals))  
    p_value_binwise = cdf_value_low .+ cdf_value_up # significance of residuals -> ~proabability that residual (for a given bin) is as large as observed or larger
    return residuals, residuals_norm, p_value_binwise, bin_centers
end

