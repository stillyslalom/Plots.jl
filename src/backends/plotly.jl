
# https://plot.ly/javascript/getting-started

supported_args(::PlotlyBackend) = merge_with_base_supported([
    :annotations,
    :background_color_legend, :background_color_inside, :background_color_outside,
    :foreground_color_legend, :foreground_color_guide,
    # :foreground_color_grid, :foreground_color_axis,
    :foreground_color_text, :foreground_color_border,
    :foreground_color_title,
    :label,
    :seriescolor, :seriesalpha,
    :linecolor, :linestyle, :linewidth, :linealpha,
    :markershape, :markercolor, :markersize, :markeralpha,
    :markerstrokewidth, :markerstrokecolor, :markerstrokealpha, :markerstrokestyle,
    :fillrange, :fillcolor, :fillalpha,
    :bins,
    :title, :title_location, :titlefont,
    :window_title,
    :guide, :lims, :ticks, :scale, :flip, :rotation,
    :tickfont, :guidefont, :legendfont,
    :grid, :legend, :colorbar,
    :marker_z, :levels,
    :ribbon, :quiver,
    :orientation,
    # :overwrite_figure,
    :polar,
    :normalize, :weights,
    # :contours, :aspect_ratio,
    :hover,
    :inset_subplots,
  ])

supported_types(::PlotlyBackend) = [
    :path, :scatter, :bar, :pie, :heatmap,
    :contour, :surface, :path3d, :scatter3d, :shape, :scattergl,
]
supported_styles(::PlotlyBackend) = [:auto, :solid, :dash, :dot, :dashdot]
supported_markers(::PlotlyBackend) = [
    :none, :auto, :circle, :rect, :diamond, :utriangle, :dtriangle,
    :cross, :xcross, :pentagon, :hexagon, :octagon, :vline, :hline
]
supported_scales(::PlotlyBackend) = [:identity, :log10]
is_subplot_supported(::PlotlyBackend) = true
is_string_supported(::PlotlyBackend) = true


# --------------------------------------------------------------------------------------

function _initialize_backend(::PlotlyBackend; kw...)
  @eval begin
    import JSON
    JSON._print(io::IO, state::JSON.State, dt::Union{Date,DateTime}) = print(io, '"', dt, '"')

    _js_path = Pkg.dir("Plots", "deps", "plotly-latest.min.js")
    _js_code = open(@compat(readstring), _js_path, "r")

    # borrowed from https://github.com/plotly/plotly.py/blob/2594076e29584ede2d09f2aa40a8a195b3f3fc66/plotly/offline/offline.py#L64-L71 c/o @spencerlyon2
    _js_script = """
        <script type='text/javascript'>
            define('plotly', function(require, exports, module) {
                $(_js_code)
            });
            require(['plotly'], function(Plotly) {
                window.Plotly = Plotly;
            });
        </script>
    """

    # if we're in IJulia call setupnotebook to load js and css
    if isijulia()
        display("text/html", _js_script)
    end

    # if isatom()
    #     import Atom
    #     Atom.@msg evaljs(_js_code)
    # end

  end
  # TODO: other initialization
end


# ----------------------------------------------------------------

function plotly_font(font::Font, color = font.color)
    KW(
        :family => font.family,
        :size   => round(Int, font.pointsize*1.4),
        :color  => webcolor(color),
    )
end

function plotly_annotation_dict(x, y, val; xref="paper", yref="paper")
    KW(
        :text => val,
        :xref => xref,
        :x => x,
        :yref => xref,
        :y => y,
        :showarrow => false,
    )
end

function plotly_annotation_dict(x, y, ptxt::PlotText; xref="paper", yref="paper")
    merge(plotly_annotation_dict(x, y, ptxt.str; xref=xref, yref=yref), KW(
        :font => plotly_font(ptxt.font),
        :xanchor => ptxt.font.halign == :hcenter ? :center : ptxt.font.halign,
        :yanchor => ptxt.font.valign == :vcenter ? :middle : ptxt.font.valign,
        :rotation => ptxt.font.rotation,
    ))
end

# function get_annotation_dict_for_arrow(d::KW, xyprev::Tuple, xy::Tuple, a::Arrow)
#     xdiff = xyprev[1] - xy[1]
#     ydiff = xyprev[2] - xy[2]
#     dist = sqrt(xdiff^2 + ydiff^2)
#     KW(
#         :showarrow => true,
#         :x => xy[1],
#         :y => xy[2],
#         # :ax => xyprev[1] - xy[1],
#         # :ay => xy[2] - xyprev[2],
#         # :ax => 0,
#         # :ay => -40,
#         :ax => 10xdiff / dist,
#         :ay => -10ydiff / dist,
#         :arrowcolor => webcolor(d[:linecolor], d[:linealpha]),
#         :xref => "x",
#         :yref => "y",
#         :arrowsize => 10a.headwidth,
#         # :arrowwidth => a.headlength,
#         :arrowwidth => 0.1,
#     )
# end

function plotly_scale(scale::Symbol)
    if scale == :log10
        "log"
    else
        "-"
    end
end


# this method gets the start/end in percentage of the canvas for this axis direction
function plotly_domain(sp::Subplot, letter)
    figw, figh = sp.plt[:size]
    pcts = bbox_to_pcts(sp.plotarea, figw*px, figh*px)
    i1,i2 = (letter == :x ? (1,3) : (2,4))
    [pcts[i1], pcts[i1]+pcts[i2]]
end


function plotly_axis(axis::Axis, sp::Subplot)
    letter = axis[:letter]
    ax = KW(
        :title      => axis[:guide],
        :showgrid   => sp[:grid],
        :zeroline   => false,
    )

    if letter in (:x,:y)
        ax[:domain] = plotly_domain(sp, letter)
        ax[:anchor] = "$(letter==:x ? :y : :x)$(plotly_subplot_index(sp))"
    end

    rot = axis[:rotation]
    if rot != 0
        ax[:tickangle] = rot
    end

    if !(axis[:ticks] in (nothing, :none))
        ax[:titlefont] = plotly_font(axis[:guidefont], axis[:foreground_color_guide])
        ax[:type] = plotly_scale(axis[:scale])
        ax[:tickfont] = plotly_font(axis[:tickfont], axis[:foreground_color_text])
        ax[:tickcolor] = webcolor(axis[:foreground_color_border])
        ax[:linecolor] = webcolor(axis[:foreground_color_border])

        # lims
        lims = axis[:lims]
        if lims != :auto && limsType(lims) == :limits
            ax[:range] = lims
        end

        # flip
        if axis[:flip]
            ax[:autorange] = "reversed"
        end

        # ticks
        ticks = axis[:ticks]
        if ticks != :auto
            ttype = ticksType(ticks)
            if ttype == :ticks
                ax[:tickmode] = "array"
                ax[:tickvals] = ticks
            elseif ttype == :ticks_and_labels
                ax[:tickmode] = "array"
                ax[:tickvals], ax[:ticktext] = ticks
            end
        end
    else
        ax[:showticklabels] = false
        ax[:showgrid] = false
    end

    ax
end

function plotly_layout(plt::Plot)
    d_out = KW()

    w, h = plt[:size]
    d_out[:width], d_out[:height] = w, h
    d_out[:paper_bgcolor] = webcolor(plt[:background_color_outside])
    d_out[:margin] = KW(:l=>0, :b=>0, :r=>0, :t=>20)

    d_out[:annotations] = KW[]

    for sp in plt.subplots
        spidx = plotly_subplot_index(sp)

        # add an annotation for the title... positioned horizontally relative to plotarea,
        # but vertically just below the top of the subplot bounding box
        if sp[:title] != ""
            bb = plotarea(sp)
            tpos = sp[:title_location]
            xmm = if tpos == :left
                left(bb)
            elseif tpos == :right
                right(bb)
            else
                0.5 * (left(bb) + right(bb))
            end
            titlex, titley = xy_mm_to_pcts(xmm, top(bbox(sp)), w*px, h*px)
            titlefont = font(sp[:titlefont], :top, sp[:foreground_color_title])
            push!(d_out[:annotations], plotly_annotation_dict(titlex, titley, text(sp[:title], titlefont)))
        end

        d_out[:plot_bgcolor] = webcolor(sp[:background_color_inside])

        # TODO: x/y axis tick values/labels

        # if any(is3d, seriesargs)
        if is3d(sp)
            d_out[:scene] = KW(
                Symbol("xaxis$spidx") => plotly_axis(sp[:xaxis], sp),
                Symbol("yaxis$spidx") => plotly_axis(sp[:yaxis], sp),
                Symbol("zaxis$spidx") => plotly_axis(sp[:zaxis], sp),
            )
        else
            d_out[Symbol("xaxis$spidx")] = plotly_axis(sp[:xaxis], sp)
            d_out[Symbol("yaxis$spidx")] = plotly_axis(sp[:yaxis], sp)
        end

        # legend
        d_out[:showlegend] = sp[:legend] != :none
        if sp[:legend] != :none
            d_out[:legend] = KW(
                :bgcolor  => webcolor(sp[:background_color_legend]),
                :bordercolor => webcolor(sp[:foreground_color_legend]),
                :font     => plotly_font(sp[:legendfont], sp[:foreground_color_legend]),
            )
        end

        # annotations
        append!(d_out[:annotations], KW[plotly_annotation_dict(ann...; xref = "x$spidx", yref = "y$spidx") for ann in sp[:annotations]])

        # # arrows
        # for sargs in seriesargs
        #     a = sargs[:arrow]
        #     if sargs[:seriestype] in (:path, :line) && typeof(a) <: Arrow
        #         add_arrows(sargs[:x], sargs[:y]) do xyprev, xy
        #             push!(d_out[:annotations], get_annotation_dict_for_arrow(sargs, xyprev, xy, a))
        #         end
        #     end
        # end

        if ispolar(sp)
            d_out[:direction] = "counterclockwise"
        end

        d_out
    end

    # turn off hover if nothing's using it
    if all(series -> series.d[:hover] in (false,:none), plt.series_list)
        d_out[:hovermode] = "none"
    end

    d_out
end

function plotly_layout_json(plt::Plot)
    JSON.json(plotly_layout(plt))
end


function plotly_colorscale(grad::ColorGradient, alpha = nothing)
    [[grad.values[i], webcolor(grad.colors[i], alpha)] for i in 1:length(grad.colors)]
end
plotly_colorscale(c, alpha = nothing) = plotly_colorscale(default_gradient(), alpha)

const _plotly_markers = KW(
    :rect       => "square",
    :xcross     => "x",
    :utriangle  => "triangle-up",
    :dtriangle  => "triangle-down",
    :star5      => "star-triangle-up",
    :vline      => "line-ns",
    :hline      => "line-ew",
)

function plotly_subplot_index(sp::Subplot)
    spidx = sp[:subplot_index]
    spidx == 1 ? "" : spidx
end


# the Shape contructor will automatically close the shape. since we need it closed,
# we split by NaNs and then construct/destruct the shapes to get the closed coords
function plotly_close_shapes(x, y)
    xs, ys = nansplit(x), nansplit(y)
    for i=1:length(xs)
        shape = Shape(xs[i], ys[i])
        xs[i], ys[i] = shape_coords(shape)
    end
    nanvcat(xs), nanvcat(ys)
end

# get a dictionary representing the series params (d is the Plots-dict, d_out is the Plotly-dict)
function plotly_series(plt::Plot, series::Series)
    d = series.d
    sp = d[:subplot]
    d_out = KW()

    # these are the axes that the series should be mapped to
    spidx = plotly_subplot_index(sp)
    d_out[:xaxis] = "x$spidx"
    d_out[:yaxis] = "y$spidx"
    d_out[:showlegend] = should_add_to_legend(series)

    x, y = collect(d[:x]), collect(d[:y])
    d_out[:name] = d[:label]
    st = d[:seriestype]
    isscatter = st in (:scatter, :scatter3d, :scattergl)
    hasmarker = isscatter || d[:markershape] != :none
    # hasline = !isscatter
    hasline = st in (:path, :path3d)

    # set the "type"
    if st in (:path, :scatter, :scattergl)
        d_out[:type] = st==:scattergl ? "scattergl" : "scatter"
        d_out[:mode] = if hasmarker
            hasline ? "lines+markers" : "markers"
        else
            hasline ? "lines" : "none"
        end
        if d[:fillrange] == true || d[:fillrange] == 0
            d_out[:fill] = "tozeroy"
            d_out[:fillcolor] = webcolor(d[:fillcolor], d[:fillalpha])
        elseif !(d[:fillrange] in (false, nothing))
            warn("fillrange ignored... plotly only supports filling to zero. fillrange: $(d[:fillrange])")
        end
        d_out[:x], d_out[:y] = x, y

    elseif st == :shape
        # to draw polygons, we actually draw lines with fill
        d_out[:type] = "scatter"
        d_out[:mode] = "lines"
        d_out[:x], d_out[:y] = plotly_close_shapes(x, y)
        # @show map(length, (x,y,d_out[:x],d_out[:y]))
        # @show d_out[:x] d_out[:y]
        d_out[:fill] = "tozeroy"
        d_out[:fillcolor] = webcolor(d[:markercolor], d[:markeralpha])
        if d[:markerstrokewidth] > 0
            d_out[:line] = KW(
                :color => webcolor(d[:markerstrokecolor], d[:markerstrokealpha]),
                :width => d[:markerstrokewidth],
                :dash => string(d[:markerstrokestyle]),
            )
        end



    elseif st == :bar
        d_out[:type] = "bar"
        d_out[:x], d_out[:y] = x, y
        d_out[:orientation] = isvertical(d) ? "v" : "h"

    # elseif st == :histogram2d
    #     d_out[:type] = "histogram2d"
    #     d_out[:x], d_out[:y] = x, y
    #     if isa(d[:bins], Tuple)
    #         xbins, ybins = d[:bins]
    #     else
    #         xbins = ybins = d[:bins]
    #     end
    #     d_out[:nbinsx] = xbins
    #     d_out[:nbinsy] = ybins
    #     d_out[:colorscale] = plotly_colorscale(d[:fillcolor], d[:fillalpha])

    # elseif st in (:histogram, :density)
    #     d_out[:type] = "histogram"
    #     isvert = isvertical(d)
    #     d_out[isvert ? :x : :y] = y
    #     d_out[isvert ? :nbinsx : :nbinsy] = d[:bins]
    #     if st == :density
    #         d_out[:histogramnorm] = "probability density"
    #     end

    elseif st == :heatmap
        d_out[:type] = "heatmap"
        d_out[:x], d_out[:y], d_out[:z] = d[:x], d[:y], transpose_z(d, d[:z].surf, false)
        d_out[:colorscale] = plotly_colorscale(d[:fillcolor], d[:fillalpha])

    elseif st == :contour
        d_out[:type] = "contour"
        d_out[:x], d_out[:y], d_out[:z] = d[:x], d[:y], transpose_z(d, d[:z].surf, false)
        # d_out[:showscale] = d[:colorbar] != :none
        d_out[:ncontours] = d[:levels]
        d_out[:contours] = KW(:coloring => d[:fillrange] != nothing ? "fill" : "lines")
        d_out[:colorscale] = plotly_colorscale(d[:linecolor], d[:linealpha])

    elseif st in (:surface, :wireframe)
        d_out[:type] = "surface"
        d_out[:x], d_out[:y], d_out[:z] = d[:x], d[:y], transpose_z(d, d[:z].surf, false)
        d_out[:colorscale] = plotly_colorscale(d[:fillcolor], d[:fillalpha])

    elseif st == :pie
        d_out[:type] = "pie"
        d_out[:labels] = pie_labels(sp, series)
        d_out[:values] = y
        d_out[:hoverinfo] = "label+percent+name"

    elseif st in (:path3d, :scatter3d)
        d_out[:type] = "scatter3d"
        d_out[:mode] = if hasmarker
            hasline ? "lines+markers" : "markers"
        else
            hasline ? "lines" : "none"
        end
        d_out[:x], d_out[:y] = x, y
        d_out[:z] = collect(d[:z])

    else
        warn("Plotly: seriestype $st isn't supported.")
        return KW()
    end

    # add "marker"
    if hasmarker
        d_out[:marker] = KW(
            :symbol => get(_plotly_markers, d[:markershape], string(d[:markershape])),
            :opacity => d[:markeralpha],
            :size => 2 * d[:markersize],
            :color => webcolor(d[:markercolor], d[:markeralpha]),
            :line => KW(
                :color => webcolor(d[:markerstrokecolor], d[:markerstrokealpha]),
                :width => d[:markerstrokewidth],
            ),
        )

        # gotta hack this (for now?) since plotly can't handle rgba values inside the gradient
        if d[:marker_z] != nothing
            # d_out[:marker][:color] = d[:marker_z]
            # d_out[:marker][:colorscale] = plotly_colorscale(d[:markercolor], d[:markeralpha])
            # d_out[:showscale] = true
            grad = ColorGradient(d[:markercolor], alpha=d[:markeralpha])
            zmin, zmax = extrema(d[:marker_z])
            d_out[:marker][:color] = [webcolor(getColorZ(grad, (zi - zmin) / (zmax - zmin))) for zi in d[:marker_z]]
        end
    end

    # add "line"
    if hasline
        d_out[:line] = KW(
            :color => webcolor(d[:linecolor], d[:linealpha]),
            :width => d[:linewidth],
            :shape => if st == :steppre
                "vh"
            elseif st == :steppost
                "hv"
            else
                "linear"
            end,
            :dash => string(d[:linestyle]),
            # :dash => "solid",
        )
    end

    # convert polar plots x/y to theta/radius
    if ispolar(d[:subplot])
        d_out[:t] = rad2deg(pop!(d_out, :x))
        d_out[:r] = pop!(d_out, :y)
    end

    # hover text
    hover = d[:hover]
    if hover in (:none, false)
        d_out[:hoverinfo] = "none"
    elseif hover != nothing
        d_out[:hoverinfo] = "text"
        d_out[:text] = hover
    end

    d_out
end

# get a list of dictionaries, each representing the series params
function plotly_series_json(plt::Plot)
    JSON.json(map(series -> plotly_series(plt, series), plt.series_list))
end

# ----------------------------------------------------------------

function html_head(plt::Plot{PlotlyBackend})
    "<script src=\"$(Pkg.dir("Plots","deps","plotly-latest.min.js"))\"></script>"
end

function html_body(plt::Plot{PlotlyBackend}, style = nothing)
    if style == nothing
        w, h = plt[:size]
        style = "width:$(w)px;height:$(h)px;"
    end
    uuid = Base.Random.uuid4()
    html = """
        <div id=\"$(uuid)\" style=\"$(style)\"></div>
        <script>
        PLOT = document.getElementById('$(uuid)');
        Plotly.plot(PLOT, $(plotly_series_json(plt)), $(plotly_layout_json(plt)));
        </script>
    """
    html
end

function js_body(plt::Plot{PlotlyBackend}, uuid)
    js = """
          PLOT = document.getElementById('$(uuid)');
          Plotly.plot(PLOT, $(plotly_series_json(plt)), $(plotly_layout_json(plt)));
    """
end


# ----------------------------------------------------------------


function _writemime(io::IO, ::MIME"image/png", plt::Plot{PlotlyBackend})
    writemime_png_from_html(io, plt)
end

function _writemime(io::IO, ::MIME"image/svg+xml", plt::Plot{PlotlyBackend})
    write(io, html_head(plt) * html_body(plt))
end

function _display(plt::Plot{PlotlyBackend})
    standalone_html_window(plt)
end