function add_entry!(names, values, entry; default)
    i = findfirst(==(entry), names)
    if isnothing(i)
        push!(names, entry)
        push!(values, default)
        i = lastindex(names)
    end
    return values[i]
end

struct LegendSection
    title::String
    names::Vector{String}
    plots::Vector{Vector{AbstractPlot}}
end
LegendSection(title::String="") = LegendSection(title, String[], Vector{AbstractPlot}[])

# Add an empty trace list with name `entry` to the legend section
function add_entry!(legendsection::LegendSection, entry::String)
    names, plots = legendsection.names, legendsection.plots
    return add_entry!(names, plots, entry; default=AbstractPlot[])
end

struct Legend
    names::Vector{String}
    sections::Vector{LegendSection}
end
Legend() = Legend(String[], LegendSection[])

# Add an empty section with name `entry` and title `title` to the legend
function add_entry!(legend::Legend, entry::String; title::String="")
    names, sections = legend.names, legend.sections
    return add_entry!(names, sections, entry; default=LegendSection(title))
end

function create_entrygroups(legend::Legend)
    legend = remove_duplicates(legend)
    sections = legend.sections
    create_entrygroups(
        getproperty.(sections, :plots),
        getproperty.(sections, :names),
        # LLegend needs `nothing` to remove the space for a missing title
        [t == " " ? nothing : t for t in getproperty.(sections, :title)]
    )
end

function remove_duplicates(legend)
    sections = legend.sections
    titles = getproperty.(sections, :title)
    # check if there are duplicate titles
    unique_inds = unique_indices(titles; keep = " ")
    has_duplicates = length(unique_inds) < length(titles)
    # if so: remove duplicates, generate new names
    if has_duplicates
        sections_new = sections[unique_inds]
        names_new = legend.names[unique_inds]
        return Legend(names_new, sections_new)
    else
        return legend
    end
end

function unique_indices(x; keep)
    first_inds = indexin(x, x)
    inds_keep = findall(==(keep), x)
    sort!(union!(inds_keep, first_inds))
end

using AbstractPlotting.MakieLayout: Optional, LegendEntry, EntryGroup
function create_entrygroups(contents::AbstractArray,
    labels::AbstractArray{String},
    title::Optional{String} = nothing)
    
    if length(contents) != length(labels)
        error("Number of elements not equal: $(length(contents)) content elements and $(length(labels)) labels.")
    end

    entries = [LegendEntry(label, content) for (content, label) in zip(contents, labels)]
    entrygroups = Vector{EntryGroup}([(title, entries)])
end

function create_entrygroups(contentgroups::AbstractArray{<:AbstractArray},
    labelgroups::AbstractArray{<:AbstractArray},
    titles::AbstractArray{<:Optional{String}})

    if !(length(titles) == length(contentgroups) == length(labelgroups))
    error("Number of elements not equal: $(length(titles)) titles,     $(length(contentgroups)) content groups and $(length(labelgroups)) label     groups.")
    end

    entries = [[LegendEntry(l, pg) for (l, pg) in zip(labelgroup, contentgroup)]
        for (labelgroup, contentgroup) in zip(labelgroups, contentgroups)]

    entrygroups = Vector{EntryGroup}([(t, en) for (t, en) in zip(titles, entries)])
end

function repl(d, pair)
    d[pair[1]] = pair[2]
    d
end

scatter_defaults = Dict(
     :marker => :circle, :strokecolor => :transparent, :markerstrokewidth => 1, :color => :black, :markersize => 10 * AbstractPlotting.px)
     
defaults_with_replacement(::Type{AbstractPlotting.Scatter}, pair) = repl(scatter_defaults, pair)

defaults_with_replacement(::Type{AbstractPlotting.Lines}, pair) = @error "not yet defined"

legendelement(::Type{AbstractPlotting.Scatter}; kwargs...) = MakieLayout.MarkerElement(; kwargs...)

legendelement(::Type{AbstractPlotting.Lines}; kwargs...) = MakieLayout.LineElement(; kwargs...)

function entry_group(::Type{AbstractPlotting.Scatter}, k, name, min, max) 
    ticks = MakieLayout.locateticks(min, max, 4)
    
    legend_elements = [MakieLayout.MarkerElement(; repl(defaults, k => tick)...) for tick in ticks]
    
    create_entrygroups([legend_elements], [string.(ticks)], [string(name)])
end

