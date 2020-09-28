function apply_alpha_transparency!(attrs::Attributes)
    # manually implement alpha values
    c = get(attrs, :color, Observable(:black))
    alpha = get(attrs, :alpha, Observable(1))
    attrs[:color] = c[] isa Union{Tuple, AbstractArray} ? c : lift(tuple, c, alpha)
end

function set_axis_labels!(ax, names)
    for (nm, prop) in zip(names, (:xlabel, :ylabel, :zlabel))
        s = string(nm)
        if hasproperty(ax, prop) && getproperty(ax, prop)[] == " "
            getproperty(ax, prop)[] = s
        end
    end
end

function set_axis_ticks!(ax, ticks)
    for (tick, prop) in zip(ticks, (:xticks, :yticks, :zticks))
        if hasproperty(ax, prop) && getproperty(ax, prop)[] == automatic
            getproperty(ax, prop)[] = tick
        end
    end
end

function add_facet_labels!(scene, axs, layout_levels;
    facetlayout, axis, spanned_label)

    isnothing(layout_levels) && return

    @assert size(axs) == size(facetlayout)

    Ny, Nx = size(axs)

    positive_rotation = axis == :x ? 0.0 : π/2
    # Facet labels
    lxl = string.(layout_levels)
    for i in eachindex(lxl)
        pos = axis == :x ? (1, i, Top()) : (i, Nx, Right())
        facetlayout[pos...] = LRect(
            scene, color = :gray85, strokevisible = true
        ) 
        facetlayout[pos...] = LText(scene, lxl[i],
            rotation = -positive_rotation, padding = (3, 3, 3, 3)
        )
    end

    # Shared xlabel
    itr = axis == :x ? axs[end, :] : axs[:, 1]
    group_protrusion = lift(
        (xs...) -> maximum(x -> axis == :x ? x.bottom : x.left, xs),
        (MakieLayout.protrusionsobservable(ax) for ax in itr)...
    )

    single_padding = @lift($group_protrusion + 10)
    padding = lift(single_padding) do val
        axis == :x ? (0, 0, 0, val) : (0, val, 0, 0)
    end

    label = LText(scene, spanned_label, padding = padding, rotation = positive_rotation)
    pos = axis == :x ? (Ny, :, Bottom()) : (:, 1, Left())
    facetlayout[pos...] = label
end

# Return the only unique value of the collection if it exists, `nothing` otherwise.
function unique_value(labels)
    l = first(labels)
    return all(==(l), labels) ? l : nothing
end

function spannable_xy_labels(axs)
    nonempty_axs = filter(ax -> !isempty(ax.scene.plots), axs)
    xlabels = [ax.xlabel[] for ax in nonempty_axs]
    ylabels = [ax.ylabel[] for ax in nonempty_axs]
    
    # if layout has multiple columns, check if `xlabel` is spannable
    xlabel = size(axs, 2) > 1 ? unique_value(xlabels) : nothing

    # if layout has multiple rows, check if `ylabel` is spannable
    ylabel = size(axs, 1) > 1 ? unique_value(ylabels) : nothing

    return xlabel, ylabel
end

function replace_categorical(v::AbstractArray)
    labels = string.(levels(v))
    rg = axes(labels, 1)
    return levelcode.(v), (rg, labels)
end

import GeometryBasics 
const Geometry = Union{GeometryBasics.AbstractGeometry, GeometryBasics.MultiPolygon}

replace_categorical(v::AbstractArray{<:Union{Number, Geometry}}) = (v, automatic)
replace_categorical(v::Any) = (v, automatic)

function layoutplot!(scene, layout, ts::ElementOrList)
    facetlayout = layout[1, 1] = GridLayout()
    speclist = run_pipeline(ts)
    Nx, Ny, Ndodge = 1, 1, 1
    for spec in speclist
        Nx = max(Nx, rank(to_value(get(spec.options, :layout_x, Nx))))
        Ny = max(Ny, rank(to_value(get(spec.options, :layout_y, Ny))))
        # dodge may need to be done separately per each subplot
        Ndodge = max(Ndodge, rank(to_value(get(spec.options, :dodge, Ndodge))))
    end
    axs = facetlayout[1:Ny, 1:Nx] = [LAxis(scene) for i in 1:Ny, j in 1:Nx]
    for i in 1:Nx
        linkxaxes!(axs[:, i]...)
    end
    for i in 1:Ny
        linkyaxes!(axs[i, :]...)
    end
    hidexdecorations!.(axs[1:end-1, :], grid = false)
    hideydecorations!.(axs[:, 2:end], grid = false)
    
    for_colormap = []
    colorname = nothing

    for_markersize = []
    markersizename = nothing
    
    legend = Legend()
    level_dict = Dict{Symbol, Any}()
    encountered_pkey = Set()
    style_dict = Dict{Symbol, Any}()
    for trace in speclist
        pkeys, style, options = trace.pkeys, trace.style, trace.options
        P = plottype(trace)
        P isa Symbol && (P = getproperty(AbstractPlotting, P))
        args, kwargs = split(options)
        names, args = extract_names(args)
        kwnames, _ = extract_names(kwargs)
        allnames = merge(NamedTuple{Tuple(Symbol.(1:length(names)))}(names), kwnames)

        attrs = Attributes(kwargs)
        apply_alpha_transparency!(attrs)
        x_pos = pop!(attrs, :layout_x, 1) |> to_value |> rank
        y_pos = pop!(attrs, :layout_y, 1) |> to_value |> rank
        ax = axs[y_pos, x_pos]
        args_and_ticks = map(replace_categorical, args)
        args, ticks = map(first, args_and_ticks), map(last, args_and_ticks)
        dodge = pop!(attrs, :dodge, nothing) |> to_value
        if !isnothing(dodge)
            width = pop!(attrs, :width, automatic) |> to_value
            arg, w = compute_dodge(first(args), rank(dodge), Ndodge, width=width)
            args = (arg, Base.tail(args)...)
            attrs.width = w
        end
        current = AbstractPlotting.plot!(ax, P, attrs, args...)
        if hasproperty(style.value, :color)
            push!(for_colormap, current)
            if isnothing(colorname)
                colorname = kwnames.color
            else
                @assert colorname == kwnames.color
            end
        end
        if hasproperty(style.value, :markersize)
            push!(for_markersize, extrema(current[:markersize][]))
            if isnothing(markersizename)
                markersizename = kwnames.markersize
            else
                @assert markersizename == kwnames.markersize
            end
        end
        set_axis_labels!(ax, names)
        set_axis_ticks!(ax, ticks)
        
        # prepare the legends for categorical variables
        for (k, v) in pairs(pkeys)
            name = get_name(v)
            val = strip_name(v)
            val isa CategoricalArray && get!(level_dict, k, levels(val))
            if k ∉ (:layout_x, :layout_y, :side, :dodge, :group) # position modifiers do not take part in the legend
                legendsection = add_entry!(legend, string(k); title=string(name))
                # here `val` will often be a NamedDimsArray, so we call `only` below
                entry = string(only(val))
                entry_traces = add_entry!(legendsection, entry)
                # make sure to write at most once on a legend entry per plot type
                if (P, k, entry) ∉ encountered_pkey
                    push!(entry_traces, current)
                    push!(encountered_pkey, (P, k, entry))
                end
            end
        end
        # prepare the legends for continuous variables
        for (k, dta) in pairs(style.value)
            name = getproperty(allnames, k)
            if haskey(style_dict, k) # encountered
                name₀, P₀, min₀, max₀ = style_dict[k]
                min₁, max₁ = extrema_or_Inf(dta)
                min_, max_ = min(min₀, min₁), max(max₀, max₁)
                @assert name₀ == name
                @assert P₀ == P
            else
                min_, max_ = extrema_or_Inf(dta)
            end
            style_dict[k] = (name, P, min_, max_)
        end
        style_dict
    end

    # this holds the legends (one entrygroup for markersize, one for color, ...)
    entrygroups = Vector{EntryGroup}()
    
    # for (k, (name, P, min, max)) in pairs(style_dict)
    #     if k ∉ (Symbol(1), Symbol(2), :color)
    #         append!(entrygroups, entry_group(P, k, name, min, max))
    #     end
    # end

    legend_layout = layout[1, end+1] = GridLayout(tellheight = false)

    if !isempty(legend.sections)
        try
            append!(entrygroups, create_entrygroups(legend))
        catch e
            @warn "Automated legend was not possible due to $e"
        end
    end
    #@show entrygroups
    haslegend = length(entrygroups) > 0
    if haslegend
        leg = legend_layout[1, 1] = MakieLayout.LLegend(scene, Node(entrygroups))
        leg.framevisible[] = false
        leg.tellheight[] = true
    end

    if length(for_colormap) > 0
        T = typeof(for_colormap[1])
        cbar_index = haslegend + 1
        cbar = legend_layout[cbar_index, 1] = MakieLayout.LColorbar(scene, T[for_colormap...], title=string(colorname), titlevisible=false, width=30, height=120)
        legend_layout[cbar_index, 1, Top()] = LText(scene, string(colorname), padding = (15,15,15,15))
    end
    
    MakieLayout.trim!(legend_layout)
    MakieLayout.trim!(layout)
    
    layout_x_levels = get(level_dict, :layout_x, nothing)
    layout_y_levels = get(level_dict, :layout_y, nothing)
    
    # Check if axis labels are spannable (i.e., the same across all panels)
    spanned_xlab, spanned_ylab = spannable_xy_labels(axs)
    
    # faceting: hide x and y labels
    for ax in axs
        ax.xlabelvisible[] &= isnothing(spanned_xlab)
        ax.ylabelvisible[] &= isnothing(spanned_ylab)
    end

    add_facet_labels!(scene, axs, layout_x_levels;
        facetlayout = facetlayout, axis = :x, spanned_label = spanned_xlab)

    add_facet_labels!(scene, axs, layout_y_levels;
        facetlayout = facetlayout, axis = :y, spanned_label = spanned_ylab)

    return scene
end

function layoutplot(s; kwargs...)
    scene, layout = MakieLayout.layoutscene(; kwargs...)
    return layoutplot!(scene, layout, s)
end
layoutplot(; kwargs...) = t -> layoutplot(t; kwargs...)

draw(args...; kwargs...) = layoutplot(args...; kwargs...)

