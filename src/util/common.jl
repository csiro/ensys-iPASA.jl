#############################################################################
# Generic helpers
#############################################################################

"""
    stringify_keys(d::AbstractDict)

Return a `Dict{String, Any}` copy of `d` with all keys converted to
`String`, recursing into nested dictionaries. Used when exporting
PowerModels data structures whose tables are keyed by `Int`.
"""
function stringify_keys(d::AbstractDict)
    return Dict{String, Any}(
        string(k) => (v isa AbstractDict ? stringify_keys(v) : v)
        for (k, v) in d
    )
end

"""
    find_region(ren_dist_dict, area_no::Integer)

Return the state key of `ren_dist_dict` (e.g. `"NSW"`) whose region list
contains `area_no`, or `nothing` if no state contains it.
"""
function find_region(ren_dist_dict::AbstractDict, area_no::Integer)
    for (k, value) in ren_dist_dict
        if in(area_no, value)
            return k
        end
    end
    return nothing
end

"""
    _timestamps_column(timestamps)

Convert a vector/range of `ZonedDateTime` timestamps into a plain column
of UTC `DateTime`s. Relies on `DataFrame(::Vector{ZonedDateTime})`
splitting the struct fields into columns (`utc_datetime`, `timezone`, ...).
"""
function _timestamps_column(timestamps)
    return DataFrame(collect(timestamps))[!, "utc_datetime"]
end
