# This file is a part of LegendSpecFits.jl, licensed under the MIT License (MIT).

"""
    energy_cal_config(data::LegendData, sel::AnyValiditySelection, det::DetectorIdLike)

Get the energy calibration configuration.
"""
function energy_cal_config(data::LegendData, sel::AnyValiditySelection, detector::DetectorIdLike)
    det = DetectorId(detector)
    prodcfg = dataprod_config(data)
    ecfg = prodcfg.energy(sel)
    if haskey(ecfg, det)
        merge(ecfg.default, ecfg[det])
    else
        ecfg.default
    end
end
export energy_cal_config


"""
    ecal_peak_windows(ecal_cfg::PropDict)

Get a dictionary of gamma peak windows to be used for energy calibrations.

Returns a `Dict{Symbol,<:AbstractInterval{<:Real}}`.

Usage:

```julia
ecal_peak_windows(energy_cal_config(data, sel, detector))
```
"""
function ecal_peak_windows(ecal_cfg::PropDict)
    labels::Vector{Symbol} = Symbol.(ecal_cfg.th228_names)
    linepos::Vector{Float64} = ecal_cfg.th228_lines
    left_size::Vector{Float64} = ecal_cfg.left_window_sizes
    right_size::Vector{Float64} = ecal_cfg.right_window_sizes
    Dict([label => ClosedInterval(peak-lsz, peak+rsz) for (label, peak, lsz, rsz) in zip(labels, linepos, left_size, right_size)])
end
export ecal_peak_windows
