classdef MySVG < handle
    % MySVG__Saves a figure as a clean, editable SVG file.
    %   MATLAB's own vector export (print, saveas, exportgraphics) turns text
    %   into outlines or scattered fragments and tessellates filled shapes.
    %   MySVG bypasses it: it walks the figure's scene graph and writes the
    %   SVG itself, so every text object becomes one live <text> element and
    %   every line, polygon, and marker becomes one clean shape.
    %
    %   The page is written in points (1 SVG unit = 1 pt), so font sizes and
    %   line widths show up in Illustrator / Inkscape / Affinity exactly as
    %   they were set in MATLAB.
    %
    %   Supported: 2D axes (linear / log / reversed / yyaxis / datetime /
    %   categorical rulers), grid, lines, scatter, bars, histograms, areas,
    %   patches, error bars, stairs, stems, contours, quiver, rectangles,
    %   images, text (TeX subset), xline / yline, legends, colorbars,
    %   subplots, tiledlayout, and annotations.
    %
    %   Limitations: 3D axes get a simplified box (back-wall grid, three axis
    %   lines, ticks, labels) and each object is depth-sorted on its own, not
    %   against the others; LaTeX-interpreter text is exported as plain text
    %   with the TeX subset applied; interpolated shading is flattened to one
    %   colour per face; polar and geographic axes export their content
    %   without the axes decorations.
    %
    %   Example
    %       plot(rand(10, 3)); legend; title("Demo")
    %       MySVG.save(gcf, fullfile(tempdir, "demo.svg"));

    properties (Constant, Access = private)
        % classes the scene-graph walk never descends into
        SKIP = ["matlab.ui.container.Menu", "matlab.ui.container.Toolbar", ...
            "matlab.ui.container.ContextMenu", "matlab.ui.control.", ...
            "matlab.ui.container.toolbar", "matlab.graphics.interactor.", ...
            "matlab.graphics.interaction.", "matlab.graphics.axestoolbar", ...
            "matlab.graphics.controls.", "matlab.graphics.chart.interaction.", ...
            "matlab.graphics.primitive.world.LightSource", ...
            "matlab.graphics.shape.internal.ScribeGrid"]
        WORLD = "matlab.graphics.primitive.world."
        TOL = 0.05              % clipping tolerance [pt]
        MAX_UNION = 4000        % max triangles merged into an outline
    end

    properties (Access = private)
        buf (1,:) string = strings(1, 0)    % emitted elements, one per entry
        defs (1,:) string = strings(1, 0)   % <defs> content
        stack = struct("idx", {}, "attrs", {}, "needClip", {})
        k (1,1) double = 0.75               % points per pixel
        dpi (1,1) double = 96
        figH (1,1) double = 0               % figure height [px]
        clipBox = []                        % [xmin ymin xmax ymax] in pt, [] = no clipping
        clipRef (1,1) string = ""           % id of the clip-path for clipBox
        offset (1,2) double = [0 0]         % origin of the current container [px]
        axBoxPx = []                        % current axes plot box [x y w h] in viewer px
        axColor = [1 1 1]
        is3D (1,1) logical = false
        cmap (:,3) double = gray(256)
        clim (1,2) double = [0 1]
        logColor (1,1) logical = false
        pageColor = [1 1 1]
        legend = []
        consumed = {}                       % primitives already folded into another element
        layered (1,1) logical = false       % true while xline / xregion objects are drawn by layer
        counters
        metrics
        metricsFig = []
        metricsText = []
        notes (1,:) string = strings(1, 0)
        debug (1,1) logical = false
    end

    %% ------------------------------------------------------------ public
    methods (Static)
        function filename = save(fig, filename, opts)
            % save__Writes a figure to an SVG file with live text and unsplit shapes.
            %
            %   Options
            %       Background (string or RGB, default "none"): Page background;
            %           "none" (transparent), "figure" (the figure colour), or
            %           a colour.
            %       Verbose (logical, default false): Print notes about
            %           anything that could not be exported faithfully.
            %       Debug (logical, default false): Rethrow errors raised
            %           while exporting an object instead of falling back.
            %
            %   Example
            %       MySVG.save(gcf, fullfile(tempdir, "figure1.svg"));
            arguments
                fig (1,1) matlab.ui.Figure
                filename (1,1) string
                opts.Background = "none"
                opts.Verbose (1,1) logical = false
                opts.Debug (1,1) logical = false
            end
            if ~endsWith(filename, ".svg", IgnoreCase=true)
                filename = filename + ".svg";
            end
            w = MySVG();
            w.debug = opts.Debug;
            cleanup = onCleanup(@() w.dispose());
            drawnow;
            pos = getpixelposition(fig);
            w.dpi = get(groot, "ScreenPixelsPerInch");
            w.k = 72 / w.dpi;
            w.figH = pos(4);
            pageSize = pos(3:4) * w.k;
            %% background
            bg = opts.Background;
            if (ischar(bg) || isstring(bg)) && string(bg) == "figure"
                bg = fig.Color;
            end
            if ~((ischar(bg) || isstring(bg)) && string(bg) == "none")
                bg = validatecolor(bg);
                w.pageColor = bg;
                w.add(sprintf("<rect id=""background"" width=""%.2f"" height=""%.2f"" fill=""%s""/>", ...
                    pageSize(1), pageSize(2), MySVG.hex(bg)));
            end
            try
                w.cmap = colormap(fig);
            catch
            end
            %% content
            w.walkChildren(fig);
            %% write
            w.write(filename, pageSize);
            if opts.Verbose && ~isempty(w.notes)
                fprintf("MySVG: %s\n", unique(w.notes, "stable"));
            end
        end

        function filename = test()
            % test__Exports a demo figure covering the common plot types.
            %
            %   Example
            %       winopen(MySVG.test())   % or: open in a browser / Illustrator
            fig = figure(Visible="off", Units="pixels", Position=[100 100 900 600]);
            cleanup = onCleanup(@() delete(fig));
            tl = tiledlayout(fig, 2, 2);
            title(tl, "MySVG demo");
            ax = nexttile(tl); hold(ax, "on");
            x = linspace(0, 2*pi, 60);
            fill(ax, [x fliplr(x)], [sin(x)+0.2 fliplr(sin(x)-0.2)], [0.2 0.4 0.9], ...
                FaceAlpha=0.2, EdgeColor="none", DisplayName="band");
            plot(ax, x, sin(x), LineWidth=1.5, DisplayName="sin(\theta)");
            plot(ax, x(1:5:end), cos(x(1:5:end)), "o--", DisplayName="cos(\theta)");
            xline(ax, pi, ":", "\pi");
            xlabel(ax, "\theta [rad]"); ylabel(ax, "f(\theta)"); title(ax, "Lines"); legend(ax);
            ax = nexttile(tl); hold(ax, "on");
            bar(ax, 1:4, [3 5 2 4]); errorbar(ax, 1:4, [3 5 2 4], [0.5 0.4 0.6 0.3], "k.");
            xticks(ax, 1:4); xticklabels(ax, ["A", "B", "C", "D"]); title(ax, "Bars");
            ax = nexttile(tl);
            scatter(ax, randn(1, 80), randn(1, 80), 30, rand(1, 80), "filled", MarkerFaceAlpha=0.7);
            colorbar(ax); title(ax, "Scatter"); grid(ax, "on");
            ax = nexttile(tl);
            imagesc(ax, peaks(20)); axis(ax, "image"); colorbar(ax); title(ax, "Image");
            filename = MySVG.save(fig, fullfile(tempdir, "MySVG_test.svg"));
        end
    end

    %% ---------------------------------------------------------- lifecycle
    methods (Access = private)
        function self = MySVG()
            self.counters = configureDictionary("string", "double");
            self.metrics = configureDictionary("string", "struct");
        end

        function dispose(self)
            if ~isempty(self.metricsFig) && isvalid(self.metricsFig)
                delete(self.metricsFig);
            end
        end

        function write(self, filename, pageSize)
            out = strings(1, 0);
            out(end+1) = "<?xml version=""1.0"" encoding=""UTF-8""?>";
            out(end+1) = sprintf("<svg xmlns=""http://www.w3.org/2000/svg"" " + ...
                "xmlns:xlink=""http://www.w3.org/1999/xlink"" version=""1.1"" " + ...
                "width=""%.2fpt"" height=""%.2fpt"" viewBox=""0 0 %.2f %.2f"">", ...
                pageSize(1), pageSize(2), pageSize(1), pageSize(2));
            if ~isempty(self.defs)
                out = [out, "<defs>", self.defs, "</defs>"];
            end
            %% indent
            depth = 0;
            body = self.buf;
            for i = 1:numel(body)
                s = body(i);
                if startsWith(s, "</g>"), depth = depth - 1; end
                body(i) = string(repmat(' ', 1, 2 * max(depth, 0))) + s;
                if startsWith(s, "<g") && ~endsWith(s, "/>"), depth = depth + 1; end
            end
            out = [out, body, "</svg>"];
            fid = fopen(filename, "w", "n", "UTF-8");
            if fid < 0
                error("MySVG:cannotWrite", "Cannot write to '%s'.", filename);
            end
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, "%s\n", out);
        end
    end

    %% ------------------------------------------------------ emit helpers
    methods (Access = private)
        function add(self, s)
            self.buf = [self.buf, reshape(string(s), 1, [])];
        end

        function note(self, msg)
            self.notes(end+1) = msg;
        end

        function id = uid(self, name)
            name = regexprep(string(name), "[^A-Za-z0-9_-]", "");
            if name == "", name = "object"; end
            n = 1;
            if isKey(self.counters, name), n = self.counters(name) + 1; end
            self.counters(name) = n;
            id = name + "-" + n;
        end

        function openGroup(self, id, attrs)
            arguments
                self
                id (1,1) string = ""
                attrs (1,1) string = ""
            end
            if id ~= "", attrs = " id=""" + id + """" + attrs; end
            self.buf(end+1) = "<g>";
            self.stack(end+1) = struct("idx", numel(self.buf), "attrs", attrs, "needClip", false);
        end

        function closeGroup(self)
            fr = self.stack(end);
            self.stack(end) = [];
            n = numel(self.buf) - fr.idx;
            if n == 0                               % nothing was drawn
                self.buf(end) = [];
                return
            end
            attrs = fr.attrs;
            if fr.needClip
                attrs = attrs + " clip-path=""url(#" + self.clipId() + ")""";
            end
            child = self.buf(end);
            isLeaf = n == 1 && ~startsWith(child, "<g") && ~startsWith(child, "</");
            idClash = contains(attrs, " id=""") && contains(child, " id=""");
            if isLeaf && ~idClash && ~(fr.needClip && contains(child, "transform="))
                % a group around a single element: fold it into the element
                self.buf(fr.idx) = regexprep(child, "^<(\w+)", "<$1" + MySVG.reEscape(attrs), "once");
                self.buf(end) = [];
            else
                self.buf(fr.idx) = "<g" + attrs + ">";
                self.buf(end+1) = "</g>";
            end
        end

        function id = clipId(self)
            if self.clipRef == ""
                self.clipRef = self.uid("clip");
                b = self.clipBox;
                self.defs(end+1) = sprintf("<clipPath id=""%s""><rect x=""%.2f"" y=""%.2f"" " + ...
                    "width=""%.2f"" height=""%.2f""/></clipPath>", self.clipRef, ...
                    b(1), b(2), b(3) - b(1), b(4) - b(2));
            end
            id = self.clipRef;
        end

        function markClip(self, p)
            % flags the enclosing group for clipping when p leaves the plot box
            if isempty(self.clipBox) || isempty(p) || isempty(self.stack), return; end
            b = self.clipBox;
            p = p(:, all(isfinite(p), 1));
            if any(p(1,:) < b(1)) || any(p(1,:) > b(3)) || any(p(2,:) < b(2)) || any(p(2,:) > b(4))
                self.stack(end).needClip = true;
            end
        end

        function p = page(self, px)
            % viewer pixels (origin bottom-left, 1-based) -> page points (origin top-left)
            p = [(px(1,:) + self.offset(1) - 1) * self.k; (self.figH + 1 - px(2,:) - self.offset(2)) * self.k];
        end
    end

    %% -------------------------------------------------------------- walk
    methods (Access = private)
        function walkChildren(self, node)
            try
                ch = node.NodeChildren;
            catch
                return
            end
            for i = numel(ch):-1:1                  % children are listed top-first
                self.walk(ch(i));
            end
        end

        function walk(self, node)
            cls = string(class(node));
            if startsWith(cls, MySVG.SKIP), return; end
            if ~MySVG.isOn(node) && cls ~= "matlab.graphics.axis.Axes", return; end
            if startsWith(cls, MySVG.WORLD)
                switch extractAfter(cls, MySVG.WORLD)
                    case "LineStrip", self.drawStrip(node, false);
                    case "LineLoop", self.drawStrip(node, true);
                    case {"Quadrilateral", "TriangleStrip"}, self.drawFaces(node);
                    case "Marker", self.drawMarkerPrim(node);
                    case "CompositeMarker", self.drawCompositeMarker(node);
                    case {"Text", "LegendTextPrimitive"}, self.drawTextPrim(node);
                    otherwise, self.walkChildren(node);
                end
            elseif cls == "matlab.graphics.axis.decorator.DecorationContainer"
                self.drawBaselines(node);
            else
                self.drawObject(node, cls);
            end
        end

        function drawObject(self, node, cls)
            name = MySVG.typeName(node, cls);
            if name ~= "", self.openGroup(self.uid(name)); end
            mark = numel(self.buf);
            depth = numel(self.stack);
            try
                switch cls
                    case "matlab.graphics.axis.Axes"
                        self.drawAxes(node);
                    case {"matlab.graphics.chart.primitive.Line", "matlab.graphics.primitive.Line"}
                        self.drawLine(node);
                    case "matlab.graphics.chart.primitive.Scatter"
                        self.drawScatter(node);
                    case "matlab.graphics.primitive.Patch"
                        self.drawPatch(node);
                    case "matlab.graphics.primitive.Image"
                        self.drawImage(node);
                    case "matlab.graphics.primitive.Text"
                        self.drawTextObject(node);
                    case "matlab.graphics.chart.decoration.ConstantLine"
                        if ~self.layered, self.drawConstantLine(node); end
                    case "matlab.graphics.chart.decoration.ConstantRegion"
                        if ~self.layered, self.drawConstantRegion(node); end
                    case "matlab.graphics.illustration.ColorBar"
                        self.drawColorbar(node);
                    case "matlab.graphics.illustration.Legend"
                        self.drawLegend(node);
                    case {"matlab.ui.container.Panel", "matlab.ui.container.Tab"}
                        self.drawPanel(node);
                    otherwise
                        self.walkChildren(node);
                end
            catch err
                if self.debug, rethrow(err); end
                % fall back to the generic primitive walk for this object
                self.buf(mark+1:end) = [];
                self.stack(depth+1:end) = [];
                self.note(sprintf("%s exported generically (%s)", cls, err.message));
                try
                    self.walkChildren(node);
                catch
                    self.buf(mark+1:end) = [];
                    self.stack(depth+1:end) = [];
                end
            end
            if name ~= "", self.closeGroup(); end
        end
    end

    %% -------------------------------------------------------------- axes
    methods (Access = private)
        function drawAxes(self, ax)
            saved = struct("cmap", self.cmap, "clim", self.clim, "log", self.logColor, ...
                "box", self.axBoxPx, "color", self.axColor, "is3D", self.is3D);
            restore = onCleanup(@() self.restoreAxes(saved));
            try
                self.cmap = colormap(ax);
                self.clim = double(ax.CLim);
                self.logColor = string(ax.ColorScale) == "log";
            catch
            end
            visible = MySVG.isOn(ax);
            self.is3D = ~isequal(ax.View, [0 90]);
            if self.is3D
                self.note("3D axes: simplified axes box; objects are depth-sorted individually, not against each other");
                self.clipBox = [];
                if visible
                    try
                        self.drawBox3D(ax);
                    catch err
                        if self.debug, rethrow(err); end
                        self.note(sprintf("3D axes box skipped (%s)", err.message));
                    end
                end
                self.walkChildren(ax);
            else
                ry = ax.YAxis;
                active = 1 + (numel(ry) == 2 && string(ax.YAxisLocation) == "right");
                xl = MySVG.limits(ax.XAxis(1));
                yl = MySVG.limits(ry(active));
                px = MySVG.data2px(ax, [xl; yl; 0 0]);
                self.axBoxPx = [min(px(1,:)), min(px(2,:)), abs(diff(px(1,:))), abs(diff(px(2,:)))];
                p = self.page(px);
                box = [min(p(1,:)), min(p(2,:)), max(p(1,:)), max(p(2,:))];
                %% background
                if visible && isnumeric(ax.Color)
                    self.axColor = ax.Color;
                    if any(abs(ax.Color - self.pageColor) > 1e-3)
                        self.add(sprintf("<rect x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f"" fill=""%s""/>", ...
                            box(1), box(2), box(3) - box(1), box(4) - box(2), MySVG.hex(ax.Color)));
                    end
                end
                onTop = string(ax.Layer) == "top";
                if visible && ~onTop
                    self.drawGrid(ax, box);
                    self.drawRulers(ax, box);
                end
                %% content
                if string(ax.Clipping) == "on"
                    self.clipBox = box + [-1 -1 1 1] * MySVG.TOL;
                    self.clipRef = "";
                end
                % xline / xregion objects sit below or above everything else
                marks = findall(ax, "Type", "constantline", "-or", "Type", "constantregion");
                isTop = arrayfun(@(h) string(h.Layer) == "top", marks);
                for i = flip(find(~isTop))', self.walk(marks(i)); end
                self.layered = ~isempty(marks);
                self.walkChildren(ax);
                self.layered = false;
                for i = flip(find(isTop))', self.walk(marks(i)); end
                self.clipBox = [];
                if visible && onTop
                    self.drawGrid(ax, box);
                    self.drawRulers(ax, box);
                end
            end
            %% labels and titles (each has its own Visible state)
            texts = {};
            names = strings(1, 0);
            dims = ["x", "y", "z"];
            rulers = {ax.XAxis, ax.YAxis, ax.ZAxis};
            for d = 1:3 - ~self.is3D
                for r = reshape(rulers{d}, 1, [])
                    texts{end+1} = r.Label; names(end+1) = dims(d) + "label"; %#ok<AGROW>
                    try
                        if ~self.is3D && MySVG.isOn(r)
                            texts{end+1} = r.SecondaryLabel; names(end+1) = dims(d) + "exponent"; %#ok<AGROW>
                        end
                    catch
                    end
                end
            end
            texts{end+1} = ax.Title; names(end+1) = "title";
            try
                texts{end+1} = ax.Subtitle; names(end+1) = "subtitle";
            catch
            end
            for i = 1:numel(texts)
                t = texts{i};
                if isempty(t) || ~isvalid(t) || ~MySVG.isOn(t), continue; end
                self.openGroup(self.uid(names(i)));
                try
                    self.drawTextObject(t);
                catch err
                    if self.debug, rethrow(err); end
                    self.note(sprintf("%s skipped (%s)", names(i), err.message));
                end
                self.closeGroup();
            end
        end

        function restoreAxes(self, saved)
            self.cmap = saved.cmap; self.clim = saved.clim; self.logColor = saved.log;
            self.axBoxPx = saved.box; self.axColor = saved.color; self.is3D = saved.is3D;
            self.clipBox = [];
            self.layered = false;
        end

        function drawGrid(self, ax, box)
            specs = {"X", ax.XAxis(1), "x"; "Y", ax.YAxis(1 + (numel(ax.YAxis) == 2 && string(ax.YAxisLocation) == "right")), "y"};
            lw = ax.LineWidth;
            if isprop(ax, "GridLineWidth"), lw = ax.GridLineWidth; end
            kinds = {"Grid", "GridColor", "GridAlpha", "GridLineStyle", false; ...
                "MinorGrid", "MinorGridColor", "MinorGridAlpha", "MinorGridLineStyle", true};
            d = "";
            attrs = "";
            self.openGroup(self.uid("grid"));
            for kd = 1:size(kinds, 1)
                for s = 1:size(specs, 1)
                    if string(ax.(specs{s, 1} + string(kinds{kd, 1}))) ~= "on", continue; end
                    r = specs{s, 2};
                    color = ax.(kinds{kd, 2});
                    if ~isnumeric(color), continue; end
                    if kinds{kd, 5}
                        tv = r.MinorTickValues;
                    else
                        tv = r.TickValues;
                    end
                    f = MySVG.rulerFrac(r, tv);
                    f = f(f > 1e-6 & f < 1 - 1e-6);
                    if isempty(f), continue; end
                    if specs{s, 3} == "x"
                        x = box(1) + f * (box(3) - box(1));
                        part = MySVG.trim(sprintf("M%.2f,%.2f V%.2f ", [x; repmat(box([4 2])', 1, numel(x))]));
                    else
                        y = box(4) - f * (box(4) - box(2));
                        part = MySVG.trim(sprintf("M%.2f,%.2f H%.2f ", [repmat(box(1), 1, numel(y)); y; repmat(box(3), 1, numel(y))]));
                    end
                    a = MySVG.lineAttrs([color(:)', ax.(kinds{kd, 3})], lw, ax.(kinds{kd, 4}));
                    if attrs ~= "" && a ~= attrs
                        self.add("<path d=""" + strtrim(d) + """" + attrs + "/>");
                        d = "";
                    end
                    attrs = a;
                    d = d + part;
                end
            end
            if d ~= ""
                self.add("<path d=""" + strtrim(d) + """" + attrs + "/>");
            end
            self.closeGroup();
        end

        function drawRulers(self, ax, box)
            tickLen = ax.TickLength(1) * max(box(3) - box(1), box(4) - box(2));
            boxOn = string(ax.Box) == "on";
            rx = ax.XAxis(1);
            ry = ax.YAxis;
            two = numel(ry) == 2;
            %% where the rulers sit
            xLoc = string(ax.XAxisLocation);
            yLoc = string(ax.YAxisLocation);
            yPos = box(4); xPos = box(1);
            if xLoc == "top", yPos = box(2); end
            if yLoc == "right" && ~two, xPos = box(3); end
            if xLoc == "origin"
                f = MySVG.rulerFrac(ry(1), 0);
                if f > 0 && f < 1, yPos = box(4) - f * (box(4) - box(2)); else, xLoc = "bottom"; end
            end
            if yLoc == "origin"
                f = MySVG.rulerFrac(rx, 0);
                if f > 0 && f < 1, xPos = box(1) + f * (box(3) - box(1)); else, yLoc = "left"; end
            end
            self.drawRuler(ax, rx, "x", xLoc, yPos, box, tickLen, boxOn && xLoc ~= "origin");
            if two
                self.drawRuler(ax, ry(1), "y", "left", box(1), box, tickLen, false);
                self.drawRuler(ax, ry(2), "y", "right", box(3), box, tickLen, false);
            else
                self.drawRuler(ax, ry, "y", yLoc, xPos, box, tickLen, boxOn && yLoc ~= "origin");
            end
        end

        function drawRuler(self, ax, r, dim, loc, pos, box, tickLen, mirror)
            if ~MySVG.isOn(r), return; end
            isX = dim == "x";
            if isX
                lo = box(1); span = box(3) - box(1);
                other = box(2) + box(4) - pos;          % the opposite side
                inward = -1 + 2 * (loc == "top");       % page direction into the plot
            else
                lo = box(4); span = box(2) - box(4);
                other = box(1) + box(3) - pos;
                inward = 1 - 2 * (loc == "right");
            end
            toPage = @(f) lo + f * span;
            self.openGroup(self.uid(dim + "axis"));
            %% axle
            color = r.Color;
            if isnumeric(color)
                stroke = MySVG.lineAttrs([color(:)' 1], r.LineWidth, "-") + " stroke-linecap=""square""";
                ends = toPage([0 1]);
                d = MySVG.axisLine(isX, ends, pos);
                if mirror, d = d + " " + MySVG.axisLine(isX, ends, other); end
                self.add("<path d=""" + d + """" + stroke + "/>");
                %% ticks
                dirn = string(ax.TickDir);
                try
                    dirn = string(r.TickDirection);
                catch
                end
                d = "";
                sets = {r.TickValues, tickLen};
                if string(r.MinorTick) == "on", sets(2, :) = {r.MinorTickValues, tickLen / 2}; end
                for s = 1:size(sets, 1)
                    f = MySVG.rulerFrac(r, sets{s, 1});
                    c = toPage(f(f >= -1e-6 & f <= 1 + 1e-6));
                    len = sets{s, 2};
                    if isempty(c) || dirn == "none" || len <= 0, continue; end
                    a = pos - inward * len * (dirn ~= "in");
                    b = pos + inward * len * (dirn ~= "out");
                    d = d + MySVG.tickPath(isX, c, a, b);
                    if mirror
                        d = d + MySVG.tickPath(isX, c, other + inward * len * (dirn ~= "in"), ...
                            other - inward * len * (dirn ~= "out"));
                    end
                end
                if d ~= ""
                    self.add("<path d=""" + strtrim(d) + """" + strrep(stroke, "square", "butt") + "/>");
                end
            else
                dirn = "in";
            end
            %% tick labels
            tv = r.TickValues;
            labels = string(r.TickLabels);
            f = MySVG.rulerFrac(r, tv);
            if ~isempty(labels) && ~isempty(f)
                labels = labels(mod(0:numel(f) - 1, numel(labels)) + 1);
                keep = f >= -1e-6 & f <= 1 + 1e-6 & reshape(strlength(labels) > 0, 1, []);
                c = toPage(f(keep));
                labels = labels(keep);
                font = MySVG.fontOf(r);
                try
                    font.rgba = [r.TickLabelColor(:)' 1];
                catch
                end
                gap = 1.5 + 0.2 * font.size;
                try
                    gap = r.TickLabelGapOffset + r.TickLabelGapMultiplier * font.size;
                catch
                end
                edge = pos - inward * (tickLen * (dirn == "out" || dirn == "both") + gap);
                rot = 0;
                try
                    rot = r.TickLabelRotation;
                catch
                end
                outSign = -inward;                      % direction pointing away from the plot
                if isX
                    if outSign > 0, va = "top"; else, va = "bottom"; end
                    ha = "center";
                    if mod(rot, 180) ~= 0
                        va = "middle";
                        if (sind(rot) > 0) == (outSign > 0), ha = "right"; else, ha = "left"; end
                    end
                else
                    if outSign < 0, ha = "right"; else, ha = "left"; end
                    va = "middle";
                    if mod(rot, 180) == 90, ha = "center"; if (outSign < 0) == (sind(rot) > 0), va = "bottom"; else, va = "top"; end, end
                end
                o = struct("ha", ha, "va", va, "rot", rot, "interp", "tex", "inherit", true, "box", []);
                try
                    o.interp = string(r.TickLabelInterpreter);
                catch
                end
                self.openGroup(self.uid(dim + "ticklabels"), MySVG.fontAttrs(font, ha));
                for i = 1:numel(labels)
                    if isX, xy = [c(i); edge]; else, xy = [edge; c(i)]; end
                    self.emitText(xy, splitlines(labels(i)), font, o);
                end
                self.closeGroup();
            end
            self.closeGroup();
        end

        function drawBox3D(self, ax)
            % back-wall grid, the three axis lines, ticks, and tick labels of a 3D axes
            rulers = {ax.XAxis(1), ax.YAxis(1), ax.ZAxis(1)};
            names = ["x", "y", "z"];
            grids = [string(ax.XGrid), string(ax.YGrid), string(ax.ZGrid)] == "on";
            lim = zeros(3, 2);
            for d = 1:3, lim(d, :) = MySVG.limits(rulers{d}); end
            cam = double(ax.CameraPosition);
            back = zeros(3, 1); front = zeros(3, 1);
            for d = 1:3
                far = 1 + (cam(d) <= mean(lim(d, :)));  % the wall away from the camera
                back(d) = lim(d, far); front(d) = lim(d, 3 - far);
            end
            proj = @(D) self.page(MySVG.data2px(ax, D));
            ticks = cell(1, 3);
            for d = 1:3
                tv = MySVG.num(rulers{d}.TickValues, rulers{d});
                f = MySVG.rulerFrac(rulers{d}, tv);
                ticks{d} = tv(f >= -1e-6 & f <= 1 + 1e-6);
            end
            %% walls and grid
            self.openGroup(self.uid("grid"));
            gridPath = "";
            for d = 1:3
                others = setdiff(1:3, d);
                if isnumeric(ax.Color) && any(abs(ax.Color - self.pageColor) > 1e-3)
                    Q = repmat(back, 1, 4);
                    Q(others(1), :) = lim(others(1), [1 2 2 1]);
                    Q(others(2), :) = lim(others(2), [1 1 2 2]);
                    self.add("<path d=""" + MySVG.pathData(proj(Q), true) + """" + MySVG.fillAttrs([ax.Color 1]) + "/>");
                end
                for e = others
                    if ~grids(e), continue; end
                    g = setdiff(others, e);
                    for t = ticks{e}
                        L = repmat(back, 1, 2);
                        L(e, :) = t;
                        L(g, :) = lim(g, :);
                        q = proj(L);
                        if all(isfinite(q), "all"), gridPath = gridPath + MySVG.pathData(q, false) + " "; end
                    end
                end
            end
            if gridPath ~= "" && isnumeric(ax.GridColor)
                lw = ax.LineWidth;
                if isprop(ax, "GridLineWidth"), lw = ax.GridLineWidth; end
                self.add("<path d=""" + strtrim(gridPath) + """" + ...
                    MySVG.lineAttrs([ax.GridColor(:)' ax.GridAlpha], lw, ax.GridLineStyle) + "/>");
            end
            self.closeGroup();
            %% where each axis line runs: x and y along the near bottom edges,
            % z along the vertical edge that is leftmost on the page
            fixed = repmat(back, 1, 3);
            fixed(2, 1) = front(2);
            fixed(1, 2) = front(1);
            a = [front(1); back(2); mean(lim(3, :))];
            b = [back(1); front(2); mean(lim(3, :))];
            pa = proj(a); pb = proj(b);
            if pa(1) <= pb(1), fixed(1:2, 3) = a(1:2); else, fixed(1:2, 3) = b(1:2); end
            centre = proj(mean(lim, 2));
            extent = 0;
            ends = cell(1, 3);
            for d = 1:3
                E = repmat(fixed(:, d), 1, 2);
                E(d, :) = lim(d, :);
                ends{d} = proj(E);
                extent = max(extent, norm(diff(ends{d}, 1, 2)));
            end
            tickLen = ax.TickLength(min(2, end)) * extent;
            for d = 1:3
                r = rulers{d};
                if ~MySVG.isOn(r) || ~isnumeric(r.Color) || ~all(isfinite(ends{d}), "all"), continue; end
                self.openGroup(self.uid(names(d) + "axis"));
                stroke = MySVG.lineAttrs([r.Color(:)' 1], r.LineWidth, "-");
                self.add("<path d=""" + MySVG.pathData(ends{d}, false) + """" + stroke + " stroke-linecap=""square""/>");
                tv = ticks{d};
                if ~isempty(tv)
                    B = repmat(fixed(:, d), 1, numel(tv));
                    B(d, :) = tv;
                    p0 = proj(B);
                    %% outward direction on the page
                    if d < 3
                        e = 3 - d;
                        O = B;
                        O(e, :) = front(e) + 0.1 * (front(e) - back(e));
                        u = proj(O) - p0;
                    else
                        u = repmat([sign(p0(1, 1) - centre(1)); 0], 1, numel(tv));
                    end
                    u = u ./ max(vecnorm(u), eps);
                    ok = all(isfinite(p0), 1) & all(isfinite(u), 1);
                    p0 = p0(:, ok); u = u(:, ok);
                    p1 = p0 + u * tickLen;
                    self.add("<path d=""" + MySVG.trim(strtrim(sprintf("M%.2f,%.2f L%.2f,%.2f ", [p0; p1]))) + """" + stroke + "/>");
                    %% labels
                    labels = string(r.TickLabels);
                    f = MySVG.rulerFrac(r, MySVG.num(r.TickValues, r));
                    if ~isempty(labels)
                        labels = labels(mod(0:numel(f) - 1, numel(labels)) + 1);
                        labels = labels(f >= -1e-6 & f <= 1 + 1e-6);
                        labels = labels(ok);
                        font = MySVG.fontOf(r);
                        try
                            font.rgba = [r.TickLabelColor(:)' 1];
                        catch
                        end
                        gap = 1.5 + 0.2 * font.size;
                        o = struct("ha", "center", "va", "middle", "rot", 0, "interp", "tex", "inherit", true, "box", []);
                        try
                            o.interp = string(r.TickLabelInterpreter);
                        catch
                        end
                        if d == 3
                            if u(1, 1) < 0, o.ha = "right"; else, o.ha = "left"; end
                            at = p0 + u * (tickLen + gap);
                        else
                            at = p0 + u * (tickLen + gap + 0.55 * font.size);
                        end
                        self.openGroup(self.uid(names(d) + "ticklabels"), MySVG.fontAttrs(font, o.ha));
                        for i = 1:numel(labels)
                            if labels(i) == "", continue; end
                            self.emitText(at(:, i), splitlines(labels(i)), font, o);
                        end
                        self.closeGroup();
                    end
                end
                self.closeGroup();
            end
        end

        function drawBaselines(self, container)
            % bar / stem / area baselines live among the axes decorations
            try
                ch = container.NodeChildren;
            catch
                return
            end
            for i = 1:numel(ch)
                b = ch(i);
                if ~isa(b, "matlab.graphics.axis.decorator.Baseline") || ~MySVG.isOn(b), continue; end
                if isempty(self.axBoxPx) || self.is3D || ~isnumeric(b.Color), continue; end
                try
                    ax = ancestor(b, "axes");
                    horizontal = true;
                    try
                        horizontal = ~any(string(b.Axis) == ["0", "x", "X"]);
                    catch
                    end
                    if horizontal
                        px = MySVG.data2px(ax, [MySVG.limits(ax.XAxis(1)); b.BaseValue b.BaseValue; 0 0]);
                    else
                        px = MySVG.data2px(ax, [b.BaseValue b.BaseValue; MySVG.limits(ax.YAxis(1)); 0 0]);
                    end
                    p = self.page(px);
                    if ~all(isfinite(p), "all"), continue; end
                    box = self.clipBox;
                    if ~isempty(box) && (any(p(1,:) < box(1)) || any(p(1,:) > box(3)) || any(p(2,:) < box(2)) || any(p(2,:) > box(4)))
                        continue
                    end
                    self.add("<path id=""" + self.uid("baseline") + """ d=""" + MySVG.pathData(p, false) + """" + ...
                        MySVG.lineAttrs([b.Color(:)' 1], b.LineWidth, b.LineStyle) + "/>");
                catch err
                    if self.debug, rethrow(err); end
                end
            end
        end
    end

    %% ------------------------------------------------- semantic handlers
    methods (Access = private)
        function drawLine(self, h)
            edge = h.Edge;
            ax = ancestor(h, "axes");
            x = h.XData; y = h.YData; z = h.ZData;
            if ~isempty(ax)
                x = MySVG.num(x, ax.XAxis(1)); y = MySVG.num(y, ax.YAxis(1));
            end
            if isempty(z), z = zeros(size(x)); end
            if ~isempty(edge) && MySVG.isOn(edge) && string(edge.LineStyle) ~= "none" && ~isempty(x)
                c = self.colors(edge.ColorData, edge.ColorBinding, edge.ColorType);
                if ~isempty(c)
                    p = self.page(MySVG.data2px(h, double([x(:)'; y(:)'; z(:)'])));
                    d = self.polylineData(p, false);
                    if d ~= ""
                        self.add("<path d=""" + d + """" + MySVG.lineAttrs(mean(c, 2)', edge.LineWidth, ...
                            edge.LineStyle, edge.LineJoin, edge.LineCap) + "/>");
                    end
                end
            end
            mk = h.MarkerHandle;
            if ~isempty(mk) && MySVG.isOn(mk)
                self.drawMarkerPrim(mk);
            end
        end

        function drawScatter(self, h)
            ax = ancestor(h, "axes");
            x = h.XData; y = h.YData; z = h.ZData;
            if ~isempty(ax)
                x = MySVG.num(x, ax.XAxis(1)); y = MySVG.num(y, ax.YAxis(1));
            end
            if isempty(z), z = zeros(size(x)); end
            n = numel(x);
            if n == 0, return; end
            p = self.page(MySVG.data2px(h, double([x(:)'; y(:)'; z(:)'])));
            try                                         % swarm charts jitter at draw time
                if string(h.XJitter) ~= "none" || string(h.YJitter) ~= "none"
                    valid = find(all(isfinite(p), 1));
                    ch = h.NodeChildren;
                    for i = 1:numel(ch)
                        if isa(ch(i), "matlab.graphics.primitive.world.Marker") && size(ch(i).VertexData, 2) == numel(valid)
                            p(:, valid) = self.page(MySVG.vert2px(ch(i), ch(i).VertexData));
                            break
                        end
                    end
                end
            catch
            end
            %% colours
            C = double(h.CData);
            if size(C, 2) == 3 && ismember(size(C, 1), [1 n])
                flat = C;
            else
                flat = self.mapColors(C(:), "scaled");
            end
            if size(flat, 1) == 1, flat = repmat(flat, n, 1); end
            face = MySVG.scatterColor(h.MarkerFaceColor, flat, self.axColor, MySVG.alphaOf(h, "MarkerFaceAlpha"));
            edge = MySVG.scatterColor(h.MarkerEdgeColor, flat, self.axColor, MySVG.alphaOf(h, "MarkerEdgeAlpha"));
            sz = sqrt(double(h.SizeData(:)'));
            if isscalar(sz), sz = repmat(sz, 1, n); end
            %% keep the drawable points
            keep = all(isfinite(p), 1) & isfinite(sz) & all(isfinite(flat), 2)';
            keep = keep & self.insideClip(p);
            if size(face, 2) > 1, face = face(:, keep); end
            if size(edge, 2) > 1, edge = edge(:, keep); end
            if self.is3D
                [p, sz, face, edge] = MySVG.depthSort(h, [x(:)'; y(:)'; z(:)'], keep, p, sz, face, edge);
            else
                p = p(:, keep); sz = sz(keep);
            end
            self.emitMarkers(p, MySVG.markerStyle(h.Marker), sz, edge, face, h.LineWidth);
        end

        function drawPatch(self, h)
            V = double(h.Vertices);
            F = double(h.Faces);
            if isempty(V) || isempty(F), return; end
            if size(V, 2) < 3, V(:, 3) = 0; end
            p = self.page(MySVG.data2px(h, V'));
            nF = size(F, 1);
            %% face colours
            fa = MySVG.alphaOf(h, "FaceAlpha");
            ea = MySVG.alphaOf(h, "EdgeAlpha");
            fc = h.FaceColor;
            ec = h.EdgeColor;
            flat = [];
            if ~isnumeric(fc) || ~isnumeric(ec)
                flat = self.patchFaceColors(h, F, size(V, 1));
            end
            fill = MySVG.patchColor(fc, flat, nF);
            edge = MySVG.patchColor(ec, flat, nF);
            order = 1:nF;
            if self.is3D && nF > 1
                order = MySVG.faceOrder(h, V, F);
            end
            uniform = size(fill, 1) <= 1 && size(edge, 1) <= 1;
            common = "";
            if uniform
                common = MySVG.fillAttrs(MySVG.rgba(fill, fa)) + ...
                    MySVG.strokeAttrs(MySVG.rgba(edge, ea), h.LineWidth, h.LineStyle, "miter");
            end
            if isempty(fill) && (isempty(edge) || string(h.LineStyle) == "none")
                items = strings(1, 0);
            else
                items = strings(1, nF);
            end
            for i = 1:numel(items)
                f = order(i);
                idx = F(f, :);
                idx = idx(~isnan(idx));
                q = p(:, idx);
                q = q(:, all(isfinite(q), 1));
                if size(q, 2) < 2, continue; end
                a = "";
                if ~uniform
                    a = MySVG.fillAttrs(MySVG.rgba(fill, fa, f)) + ...
                        MySVG.strokeAttrs(MySVG.rgba(edge, ea, f), h.LineWidth, h.LineStyle, "miter");
                end
                items(i) = "<path d=""" + MySVG.pathData(q, true) + """" + a + "/>";
            end
            items = items(items ~= "");
            if ~isempty(items)
                self.markClip(p(:, unique(F(~isnan(F)))));
                if isscalar(items)
                    self.add(regexprep(items, "/>$", MySVG.reEscape(common) + "/>"));
                else
                    self.openGroup("", common);
                    self.add(items);
                    self.closeGroup();
                end
            end
            %% vertex markers
            if string(h.Marker) ~= "none"
                for i = 1:numel(h.NodeChildren)
                    if isa(h.NodeChildren(i), "matlab.graphics.primitive.world.Marker")
                        self.walk(h.NodeChildren(i));
                    end
                end
            end
        end

        function flat = patchFaceColors(self, h, F, nV)
            % one colour per face from FaceVertexCData (flat or averaged)
            C = double(h.FaceVertexCData);
            nF = size(F, 1);
            if isempty(C), flat = zeros(nF, 3); return; end
            if size(C, 2) ~= 3
                C = self.mapColors(C(:), string(h.CDataMapping));
            end
            if size(C, 1) == 1
                flat = repmat(C, nF, 1);
            elseif size(C, 1) == nF && nF ~= nV
                flat = C;
            else                                        % per-vertex data
                flat = zeros(nF, 3);
                interp = any(string(h.FaceColor) == "interp");
                for f = 1:nF
                    idx = F(f, ~isnan(F(f, :)));
                    idx = idx(idx <= size(C, 1));
                    if isempty(idx), continue; end
                    if interp
                        flat(f, :) = mean(C(idx, :), 1, "omitnan");
                    else
                        flat(f, :) = C(idx(1), :);
                    end
                end
            end
        end

        function drawImage(self, h)
            if self.is3D
                self.note("image in a 3D axes skipped");
                return
            end
            C = h.CData;
            [m, n, ~] = size(C);
            if m == 0 || n == 0, return; end
            %% to RGB
            if size(C, 3) == 3
                if isinteger(C)
                    rgb = double(C) / double(intmax(class(C)));
                else
                    rgb = min(max(double(C), 0), 1);
                end
                nanMask = any(isnan(rgb), 3);
            else
                nanMask = isnan(double(C));
                mapping = string(h.CDataMapping);
                if mapping == "direct" && isinteger(C), C = double(C) + 1; end
                rgb = reshape(self.mapColors(double(C(:)), mapping, true), m, n, 3);
            end
            alpha = ones(m, n);
            A = double(h.AlphaData);
            if isscalar(A)
                alpha(:) = A;
            elseif isequal(size(A), [m n])
                alpha = A;
            end
            alpha = min(max(alpha, 0), 1);
            alpha(isnan(alpha)) = 0;
            if size(h.CData, 3) == 3, alpha(nanMask) = 0; end
            %% placement
            xd = double(h.XData); yd = double(h.YData);
            ax = ancestor(h, "axes");
            if ~isempty(ax) && ~isnumeric(h.XData), xd = MySVG.num(h.XData, ax.XAxis(1)); end
            if ~isempty(ax) && ~isnumeric(h.YData), yd = MySVG.num(h.YData, ax.YAxis(1)); end
            ex = MySVG.pixelEdges(xd, n);
            ey = MySVG.pixelEdges(yd, m);
            p = self.page(MySVG.data2px(h, [ex; ey; 0 0]));
            if ~all(isfinite(p), "all"), return; end
            if p(1, 1) > p(1, 2), rgb = fliplr(rgb); alpha = fliplr(alpha); end
            if p(2, 1) > p(2, 2), rgb = flipud(rgb); alpha = flipud(alpha); end
            x0 = min(p(1, :)); y0 = min(p(2, :));
            w = abs(diff(p(1, :))); hgt = abs(diff(p(2, :)));
            %% encode (nearest-neighbour upsampling keeps cells crisp in every viewer)
            rep = max(1, floor(1024 / max(m, n)));
            rgb = repelem(uint8(round(rgb * 255)), rep, rep, 1);
            alpha = repelem(alpha, rep, rep);
            tmp = string(tempname) + ".png";
            if all(alpha == 1, "all")
                imwrite(rgb, tmp);
            else
                imwrite(rgb, tmp, Alpha=alpha);
            end
            fid = fopen(tmp, "r");
            bytes = fread(fid, Inf, "*uint8");
            fclose(fid);
            delete(tmp);
            self.markClip([x0 x0 + w; y0 y0 + hgt]);
            self.add(sprintf("<image x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f"" " + ...
                "preserveAspectRatio=""none"" image-rendering=""pixelated"" " + ...
                "xlink:href=""data:image/png;base64,%s""/>", x0, y0, w, hgt, ...
                matlab.net.base64encode(bytes)));
        end

        function drawConstantLine(self, h)
            if isempty(self.axBoxPx) || self.is3D
                self.walkChildren(h);
                return
            end
            ax = ancestor(h, "axes");
            isX = string(h.InterceptAxis) == "x";
            b = self.page([self.axBoxPx(1), self.axBoxPx(1) + self.axBoxPx(3); ...
                self.axBoxPx(2), self.axBoxPx(2) + self.axBoxPx(4)]);
            box = [min(b(1,:)), min(b(2,:)), max(b(1,:)), max(b(2,:))];
            if isX
                v = MySVG.num(h.Value, ax.XAxis(1));
                c = self.page(MySVG.data2px(h, [v; MySVG.midpoint(ax.YAxis(1)); 0]));
                if ~isfinite(c(1)) || c(1) < box(1) - MySVG.TOL || c(1) > box(3) + MySVG.TOL, return; end
                p = [c(1) c(1); box(4) box(2)];
            else
                v = MySVG.num(h.Value, ax.YAxis(1));
                c = self.page(MySVG.data2px(h, [MySVG.midpoint(ax.XAxis(1)); v; 0]));
                if ~isfinite(c(2)) || c(2) < box(2) - MySVG.TOL || c(2) > box(4) + MySVG.TOL, return; end
                p = [box(1) box(3); c(2) c(2)];
            end
            alpha = 1;
            try
                alpha = h.Alpha;
            catch
            end
            if string(h.LineStyle) ~= "none"
                self.add("<path d=""" + MySVG.pathData(p, false) + """" + ...
                    MySVG.lineAttrs([h.Color(:)' alpha], h.LineWidth, h.LineStyle) + "/>");
            end
            %% label
            label = string(h.Label);
            label = label(strlength(label) > 0);
            if isempty(label), return; end
            font = MySVG.fontOf(h);
            try
                font.rgba = [h.LabelColor(:)' 1];
            catch
                font.rgba = [h.Color(:)' 1];
            end
            horz = string(h.LabelHorizontalAlignment);
            vert = string(h.LabelVerticalAlignment);
            aligned = string(h.LabelOrientation) == "aligned";
            pad = 3 * self.k + h.LineWidth / 2;
            o = struct("ha", "left", "va", "middle", "rot", 0, "interp", string(h.Interpreter), "inherit", false, "box", []);
            if isX
                along = struct("top", box(2) + pad, "middle", (box(2) + box(4)) / 2, "bottom", box(4) - pad);
                side = struct("left", -1, "center", 0, "right", 1);
                xy = [p(1, 1) + side.(horz) * pad; along.(vert)];
                if aligned
                    o.rot = 90;
                    o.ha = struct("top", "right", "middle", "center", "bottom", "left").(vert);
                    o.va = struct("left", "bottom", "center", "middle", "right", "top").(horz);
                else
                    o.ha = struct("left", "right", "center", "center", "right", "left").(horz);
                    o.va = vert;
                end
            else
                along = struct("left", box(1) + pad, "center", (box(1) + box(3)) / 2, "right", box(3) - pad);
                side = struct("top", -1, "middle", 0, "bottom", 1);
                xy = [along.(horz); p(2, 1) + side.(vert) * pad];
                o.ha = horz;
                o.va = struct("top", "bottom", "middle", "middle", "bottom", "top").(vert);
            end
            self.emitText(xy, splitlines(strjoin(label, newline)), font, o);
        end

        function drawConstantRegion(self, h)
            % xregion / yregion: a band across the plot box
            if isempty(self.axBoxPx) || self.is3D, return; end
            ax = ancestor(h, "axes");
            b = self.page([self.axBoxPx(1), self.axBoxPx(1) + self.axBoxPx(3); ...
                self.axBoxPx(2), self.axBoxPx(2) + self.axBoxPx(4)]);
            box = [min(b(1,:)), min(b(2,:)), max(b(1,:)), max(b(2,:))];
            isX = string(h.InterceptAxis) == "x";
            if isX, r = ax.XAxis(1); else, r = ax.YAxis(1); end
            f = min(max(MySVG.rulerFrac(r, h.Value), 0), 1);
            f(isnan(f)) = [];
            if numel(f) < 2 || f(1) == f(2), return; end
            rect = box;
            if isX
                rect([1 3]) = box(1) + sort(f) * (box(3) - box(1));
            else
                rect([2 4]) = box(4) - sort(f, "descend") * (box(4) - box(2));
            end
            fill = []; edge = [];
            if isnumeric(h.FaceColor), fill = [h.FaceColor(:)' h.FaceAlpha]; end
            if isnumeric(h.EdgeColor), edge = [h.EdgeColor(:)' h.EdgeAlpha]; end
            if isempty(fill) && isempty(edge), return; end
            self.add(sprintf("<rect x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f""", ...
                rect(1), rect(2), rect(3) - rect(1), rect(4) - rect(2)) + MySVG.fillAttrs(fill) + ...
                MySVG.strokeAttrs(edge, h.LineWidth, h.LineStyle, "miter") + "/>");
        end

        function drawPanel(self, pn)
            % panels have their own canvas: their content is positioned
            % relative to the panel, not the figure
            saved = self.offset;
            restore = onCleanup(@() self.setOffset(saved));
            pos = getpixelposition(pn, true);
            self.offset = pos(1:2) - 1;
            try
                inner = pn.InnerPosition; outer = pn.OuterPosition;
                if string(pn.Units) == "pixels", self.offset = self.offset + inner(1:2) - outer(1:2); end
            catch
            end
            self.walkChildren(pn);
        end

        function setOffset(self, value)
            self.offset = value;
        end

        function drawLegend(self, lg)
            % box first, then the icons, then the entry texts
            self.legend = lg;
            restore = onCleanup(@() self.clearLegend());
            % (the box primitives can lag behind an automatic placement, so the
            % rectangle comes from the legend position and only its style from them)
            pos = getpixelposition(lg, true);
            pos(1:2) = pos(1:2) - self.offset;
            p = self.page([pos(1), pos(1) + pos(3); pos(2), pos(2) + pos(4)]);
            fill = zeros(4, 0); edge = zeros(4, 0);
            face = lg.BoxFace; rim = lg.BoxEdge;
            if MySVG.isOn(face), fill = self.colors(face.ColorData, face.ColorBinding, face.ColorType); end
            if MySVG.isOn(rim), edge = self.colors(rim.ColorData, rim.ColorBinding, rim.ColorType); end
            if ~isempty(fill) || ~isempty(edge)
                attrs = MySVG.fillAttrs(fill(:, 1:min(1, end))');
                if ~isempty(edge), attrs = attrs + MySVG.strokeAttrs(edge(:, 1)', rim.LineWidth, rim.LineStyle, "miter"); end
                self.add(sprintf("<rect x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f""", ...
                    min(p(1, :)), min(p(2, :)), abs(diff(p(1, :))), abs(diff(p(2, :)))) + attrs + "/>");
            end
            self.walk(lg.EntryContainer);
            nodes = lg.NodeChildren;
            for depth = 1:3                              % the text primitive sits just below the legend
                next = [];
                for i = 1:numel(nodes)
                    c = string(class(nodes(i)));
                    if endsWith(c, [".world.Text", ".LegendTextPrimitive"])
                        if MySVG.isOn(nodes(i)), self.drawTextPrim(nodes(i)); end
                    elseif contains(c, ".camera.")
                        next = [next; nodes(i).NodeChildren(:)]; %#ok<AGROW>
                    end
                end
                nodes = next;
                if isempty(nodes), break; end
            end
            try
                if MySVG.isOn(lg.Title) && strlength(strjoin(MySVG.toLines(lg.Title.String), "")) > 0
                    self.legend = [];
                    self.walk(lg.Title);
                end
            catch err
                if self.debug, rethrow(err); end
            end
        end

        function clearLegend(self)
            self.legend = [];
        end

        function drawColorbar(self, cb)
            face = cb.Face;
            px = MySVG.vert2px(face, face.VertexData);
            p = self.page(px);
            box = [min(p(1,:)), min(p(2,:)), max(p(1,:)), max(p(2,:))];
            w = box(3) - box(1); hgt = box(4) - box(2);
            vertical = hgt >= w;
            %% colours along the bar
            colors = [];
            try
                T = face.Texture.CData;
                colors = double(squeeze(T(1:3, :, :)))' / 255;
                if size(colors, 2) ~= 3, colors = []; end
            catch
            end
            if isempty(colors), colors = colormap(cb.Parent); end
            reverse = string(cb.Direction) == "reverse";
            id = self.uid("gradient");
            stops = MySVG.gradientStops(colors);
            if vertical
                dirn = [0 1 0 0];
            else
                dirn = [0 0 1 0];
            end
            if reverse, dirn = dirn([3 4 1 2]); end
            self.defs(end+1) = sprintf("<linearGradient id=""%s"" x1=""%g"" y1=""%g"" x2=""%g"" y2=""%g"">", id, dirn) + ...
                stops + "</linearGradient>";
            attrs = sprintf(" fill=""url(#%s)""", id);
            edgeColor = cb.Color;
            try
                edgeColor = cb.EdgeColor;
            catch
            end
            if string(cb.Box) == "on" && isnumeric(edgeColor)
                attrs = attrs + MySVG.strokeAttrs([edgeColor(:)' 1], cb.LineWidth, "-", "miter");
            end
            self.add(sprintf("<rect x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f""", box(1), box(2), w, hgt) + attrs + "/>");
            %% ticks
            r = cb.Ruler;
            lim = double(cb.Limits);
            tv = double(cb.Ticks);
            isLog = string(r.Scale) == "log";
            if isLog
                f = (log10(tv) - log10(lim(1))) / diff(log10(lim));
            else
                f = (tv - lim(1)) / diff(lim);
            end
            if reverse, f = 1 - f; end
            keep = f >= -1e-6 & f <= 1 + 1e-6;
            labels = string(cb.TickLabels);
            if ~isempty(labels), labels = labels(mod(0:numel(tv) - 1, numel(labels)) + 1); end
            f = f(keep);
            loc = string(cb.Location);
            outer = string(cb.AxisLocation) == "out";
            if vertical
                c = box(4) - f * hgt;
                right = startsWith(loc, "west") ~= outer;
                side = box(1) + right * w;
                sgn = 2 * right - 1;
            else
                c = box(1) + f * w;
                top = startsWith(loc, "north") == outer;
                side = box(2) + ~top * hgt;
                sgn = 1 - 2 * top;
            end
            tickLen = cb.TickLength(1) * max(w, hgt);
            dirn = string(cb.TickDirection);
            color = cb.Color;
            if ~isempty(c) && dirn ~= "none" && tickLen > 0 && isnumeric(color)
                a = side - sgn * tickLen * (dirn ~= "out");
                b = side + sgn * tickLen * (dirn ~= "in");
                self.add("<path d=""" + strtrim(MySVG.tickPath(~vertical, c, a, b)) + """" + ...
                    MySVG.lineAttrs([color(:)' 1], cb.LineWidth, "-") + "/>");
            end
            %% tick labels
            font = MySVG.fontOf(cb);
            font.rgba = [color(:)' 1];
            if ~isempty(labels)
                labels = labels(keep);
                gap = 1.5 + 0.2 * font.size + tickLen * (dirn == "out" || dirn == "both");
                if vertical
                    if sgn > 0, ha = "left"; else, ha = "right"; end
                    va = "middle";
                else
                    ha = "center";
                    if sgn > 0, va = "top"; else, va = "bottom"; end
                end
                o = struct("ha", ha, "va", va, "rot", 0, "interp", string(cb.TickLabelInterpreter), "inherit", true, "box", []);
                self.openGroup(self.uid("colorbar-ticklabels"), MySVG.fontAttrs(font, ha));
                for i = 1:numel(labels)
                    if labels(i) == "", continue; end
                    if vertical, xy = [side + sgn * gap; c(i)]; else, xy = [c(i); side + sgn * gap]; end
                    self.emitText(xy, splitlines(labels(i)), font, o);
                end
                self.closeGroup();
            end
            %% label, exponent, title
            extra = {cb.Label};
            try
                extra{end+1} = r.SecondaryLabel;
            catch
            end
            try
                extra{end+1} = cb.Title;
            catch
            end
            for i = 1:numel(extra)
                t = extra{i};
                if isempty(t) || ~isvalid(t) || ~MySVG.isOn(t), continue; end
                try
                    self.drawTextObject(t);
                catch err
                    if self.debug, rethrow(err); end
                end
            end
        end
    end

    %% ------------------------------------------------ generic primitives
    methods (Access = private)
        function drawStrip(self, prim, isLoop)
            V = prim.VertexData;
            if isempty(V) || string(prim.LineStyle) == "none", return; end
            if any(cellfun(@(c) c == prim, self.consumed)), return; end
            c = self.colors(prim.ColorData, prim.ColorBinding, prim.ColorType);
            if isempty(c), return; end
            idx = prim.VertexIndices;
            if ~isempty(idx), V = V(:, idx); end
            p = self.page(MySVG.vert2px(prim, V));
            n = size(p, 2);
            strips = double(prim.StripData);
            if isempty(strips)
                if isLoop || n <= 2
                    strips = [1, n + 1];
                else                                    % independent segments
                    strips = unique([1:2:n, n + 1]);
                end
            end
            d = "";
            for s = 1:numel(strips) - 1
                q = p(:, strips(s):min(strips(s + 1) - 1, n));
                d = d + self.polylineData(q, isLoop) + " ";
            end
            d = strtrim(d);
            if d == "", return; end
            cap = "none";
            try
                cap = prim.LineCap;
            catch
            end
            self.add("<path d=""" + d + """" + MySVG.lineAttrs(mean(c, 2)', prim.LineWidth, ...
                prim.LineStyle, prim.LineJoin, cap) + "/>");
        end

        function drawFaces(self, prim)
            V = prim.VertexData;
            if isempty(V) || string(prim.ColorType) == "texturemapped", return; end
            c = self.colors(prim.ColorData, prim.ColorBinding, prim.ColorType);
            if isempty(c), return; end
            idx = prim.VertexIndices;
            if ~isempty(idx), V = V(:, idx); end
            n = size(V, 2);
            if self.is3D
                p3 = MySVG.vert2px(prim, V, true);
                p = self.page(p3(1:2, :));
                depth = p3(3, :);
            else
                p = self.page(MySVG.vert2px(prim, V));
                depth = [];
            end
            strips = double(prim.StripData);
            isQuad = endsWith(class(prim), "Quadrilateral");
            %% vertex indices of every polygon
            polys = {};
            if isempty(strips)
                step = 3 + isQuad;
                for i = 1:step:n - step + 1
                    polys{end+1} = i:i + step - 1; %#ok<AGROW>
                end
                merged = false;
            elseif size(c, 2) <= 1 || size(c, 2) ~= n
                % one colour per strip: the outline of a strip is its odd
                % vertices followed by its even vertices in reverse
                for s = 1:numel(strips) - 1
                    v = strips(s):min(strips(s + 1) - 1, n);
                    polys{end+1} = [v(1:2:end), fliplr(v(2:2:end))]; %#ok<AGROW>
                end
                merged = true;
            else
                for s = 1:numel(strips) - 1
                    v = strips(s):min(strips(s + 1) - 1, n);
                    for i = 1:(1 + isQuad):numel(v) - 2 - isQuad
                        if isQuad
                            polys{end+1} = v([i, i + 1, i + 3, i + 2]); %#ok<AGROW>
                        else
                            polys{end+1} = v(i:i + 2); %#ok<AGROW>
                        end
                    end
                end
                merged = false;
            end
            nP = numel(polys);
            if nP == 0, return; end
            %% one colour per polygon
            if size(c, 2) == 1
                pc = repmat(c, 1, nP);
            elseif size(c, 2) == nP
                pc = c;
            elseif size(c, 2) == n                      % per vertex: average
                pc = zeros(4, nP);
                for i = 1:nP, pc(:, i) = mean(c(:, polys{i}), 2); end
            else
                pc = repmat(mean(c, 2), 1, nP);
            end
            pc = round(pc * 255) / 255;
            keep = pc(4, :) > 0;
            self.markClip(p);
            if self.is3D && nP > 1
                %% painter's algorithm: far faces first, one element each
                zs = cellfun(@(v) mean(depth(v)), polys);
                [~, order] = sort(zs, "descend");
                stroke = self.surfaceEdges(prim);       % a surface's mesh lines become face strokes
                items = strings(1, 0);
                for i = order(keep(order))
                    q = p(:, polys{i});
                    if ~all(isfinite(q), "all"), continue; end
                    items(end+1) = "<path d=""" + MySVG.pathData(q, true) + """" + MySVG.fillAttrs(pc(:, i)') + stroke + "/>"; %#ok<AGROW>
                end
                self.add(items);
                return
            end
            [uc, ~, ic] = unique(pc', "rows", "stable");
            seams = size(uc, 1) > 1;
            for u = 1:size(uc, 1)
                if uc(u, 4) == 0, continue; end
                members = find(ic' == u);
                d = "";
                if ~merged && ~isQuad && isempty(strips) && numel(members) > 1
                    d = MySVG.unionData(p, polys(members));
                end
                if d == ""
                    parts = strings(1, numel(members));
                    for i = 1:numel(members)
                        q = p(:, polys{members(i)});
                        if all(isfinite(q), "all"), parts(i) = MySVG.pathData(q, true); end
                    end
                    d = strjoin(parts(parts ~= ""), " ");
                end
                if d == "", continue; end
                attrs = MySVG.fillAttrs(uc(u, :));
                if contains(d, "evenodd:"), d = erase(d, "evenodd:"); attrs = attrs + " fill-rule=""evenodd"""; end
                if seams && uc(u, 4) == 1               % hide hairlines between neighbours
                    attrs = attrs + sprintf(" stroke=""%s"" stroke-width=""0.2""", MySVG.hex(uc(u, 1:3)));
                end
                self.add("<path d=""" + d + """" + attrs + "/>");
            end
        end

        function stroke = surfaceEdges(self, prim)
            % in 3D the mesh lines of a surface must be sorted with its faces,
            % so they are drawn as the stroke of each face
            stroke = "";
            try
                parent = prim.NodeParent;
                if ~contains(class(parent), "Surface"), return; end
                sibs = parent.NodeChildren;
                for i = 1:numel(sibs)
                    e = sibs(i);
                    if ~isa(e, "matlab.graphics.primitive.world.LineStrip") || ~MySVG.isOn(e), continue; end
                    if string(e.LineStyle) == "none" || string(e.ColorBinding) ~= "object" || isempty(e.VertexData), continue; end
                    c = self.colors(e.ColorData, e.ColorBinding, e.ColorType);
                    if isempty(c), continue; end
                    stroke = MySVG.strokeAttrs(c(:, 1)', e.LineWidth, e.LineStyle, e.LineJoin);
                    self.consumed{end+1} = e;
                end
            catch
                stroke = "";
            end
        end

        function drawMarkerPrim(self, prim)
            V = prim.VertexData;
            style = MySVG.markerStyle(prim.Style);
            if isempty(V) || style == "none", return; end
            idx = prim.VertexIndices;
            if ~isempty(idx), V = V(:, idx); end
            edge = self.colors(prim.EdgeColorData, prim.EdgeColorBinding, prim.EdgeColorType);
            face = self.colors(prim.FaceColorData, prim.FaceColorBinding, prim.FaceColorType);
            if isempty(edge) && isempty(face), return; end
            p = self.page(MySVG.vert2px(prim, V));
            n = size(p, 2);
            sz = double(prim.Size(:)');
            if isscalar(sz), sz = repmat(sz, 1, n); end
            keep = all(isfinite(p), 1) & self.insideClip(p);
            if size(edge, 2) == n, edge = edge(:, keep); else, edge = edge(:, 1:min(1, end)); end
            if size(face, 2) == n, face = face(:, keep); else, face = face(:, 1:min(1, end)); end
            self.emitMarkers(p(:, keep), style, sz(keep), edge, face, prim.LineWidth);
        end

        function drawCompositeMarker(self, prim)
            % arrow heads: the children are drawn in points around each anchor
            V = prim.VertexData;
            if isempty(V), return; end
            anchors = self.page(MySVG.vert2px(prim, V));
            ch = prim.NodeChildren;
            for a = 1:size(anchors, 2)
                for i = numel(ch):-1:1
                    part = ch(i);
                    if ~MySVG.isOn(part) || isempty(part.VertexData), continue; end
                    c = self.colors(part.ColorData, part.ColorBinding, part.ColorType);
                    if isempty(c) || c(4, 1) == 0, continue; end
                    q = double(part.VertexData(1:2, :));
                    q = anchors(:, a) + [q(1, :); -q(2, :)];
                    strips = double(part.StripData);
                    if isa(part, "matlab.graphics.primitive.world.TriangleStrip")
                        if isempty(strips)
                            polys = arrayfun(@(j) j:j + 2, 1:3:size(q, 2) - 2, UniformOutput=false);
                            d = MySVG.unionData(q, polys);
                            if d == ""
                                d = strjoin(cellfun(@(v) MySVG.pathData(q(:, v), true), polys), " ");
                            end
                        else
                            d = MySVG.pathData(q(:, [1:2:end, fliplr(2:2:size(q, 2))]), true);
                        end
                        self.add("<path d=""" + erase(d, "evenodd:") + """" + MySVG.fillAttrs(c(:, 1)') + "/>");
                    elseif isa(part, "matlab.graphics.primitive.world.LineLoop") || isa(part, "matlab.graphics.primitive.world.LineStrip")
                        if string(part.LineStyle) == "none", continue; end
                        if isempty(strips), strips = [1, size(q, 2) + 1]; end
                        d = strings(1, numel(strips) - 1);
                        for s = 1:numel(strips) - 1
                            d(s) = MySVG.pathData(q(:, strips(s):strips(s + 1) - 1), isa(part, "matlab.graphics.primitive.world.LineLoop"));
                        end
                        self.add("<path d=""" + strjoin(d, " ") + """" + ...
                            MySVG.lineAttrs(c(:, 1)', part.LineWidth, part.LineStyle, part.LineJoin) + "/>");
                    end
                end
            end
        end

        function emitMarkers(self, p, style, sz, edge, face, lw)
            % p: 2xN centres [pt]; sz: 1xN sizes [pt]; edge / face: 4x1, 4xN, or empty
            n = size(p, 2);
            if n == 0, return; end
            shape = MySVG.markerShape(style);
            if shape.kind == "none", return; end
            if shape.kind == "dot"                      % '.' is a small filled disc
                face = edge; edge = zeros(4, 0);
            elseif ~shape.fillable
                face = zeros(4, 0);
            end
            if isempty(edge) && isempty(face), return; end
            uniform = size(edge, 2) <= 1 && size(face, 2) <= 1;
            common = MySVG.fillAttrs(face(:, 1:min(1, end))');
            if ~isempty(edge)
                common = common + MySVG.strokeAttrs(edge(:, 1)', lw, "-", "miter");
            end
            %% geometry
            x = p(1, :)'; y = p(2, :)'; s = sz(:);
            switch shape.kind
                case {"circle", "dot"}
                    items = compose("<circle cx=""%.2f"" cy=""%.2f"" r=""%.2f""", [x, y, s * shape.r]);
                case "rect"
                    h = s * shape.r;
                    items = compose("<rect x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f""", [x - h, y - h, 2 * h, 2 * h]);
                otherwise
                    d = strings(n, 1);
                    for j = 1:numel(shape.pts)
                        P = shape.pts{j};
                        m = size(P, 2);
                        coords = zeros(n, 2 * m);
                        coords(:, 1:2:end) = x + s * P(1, :);
                        coords(:, 2:2:end) = y + s * P(2, :);
                        fmt = "M" + strjoin(repmat("%.2f,%.2f", 1, m), " ");
                        if shape.fillable, fmt = fmt + "Z"; end
                        d = d + compose(fmt, coords);
                    end
                    if uniform && any(style == ["hbar", "vbar"])
                        d = strjoin(d, " ");            % error-bar caps: one path
                    end
                    items = "<path d=""" + d + """";
            end
            %% per-marker colours
            if ~uniform
                if size(face, 2) > 1
                    items = items + MySVG.fillAttrsMany(face);
                end
                if size(edge, 2) > 1
                    items = items + compose(" stroke=""#%02x%02x%02x""", round(edge(1:3, :)' * 255));
                    if any(edge(4, :) < 1), items = items + compose(" stroke-opacity=""%.3g""", edge(4, :)'); end
                end
            end
            items = items + "/>";
            if isscalar(items)
                self.add(regexprep(items, "/>$", MySVG.reEscape(common) + "/>"));
            else
                self.openGroup("", common);
                self.add(items');
                self.closeGroup();
            end
        end
    end

    %% -------------------------------------------------------------- text
    methods (Access = private)
        function drawTextObject(self, t)
            lines = MySVG.toLines(t.String);
            if all(strlength(lines) == 0), return; end
            %% anchor
            xy = [];
            pos = double(t.Position);
            if numel(pos) < 3, pos(3) = 0; end
            units = "data";
            try
                units = string(t.Units);
            catch
            end
            inAxes = ~isempty(self.axBoxPx) && ~isempty(ancestor(t, "axes"));
            if units == "data" && inAxes
                xy = self.page(MySVG.data2px(t, pos(:)));
            elseif inAxes && ~self.is3D
                b = self.axBoxPx;
                switch units
                    case "normalized", off = pos(1:2) .* b(3:4);
                    case "pixels", off = pos(1:2);
                    case "points", off = pos(1:2) / self.k;
                    case "inches", off = pos(1:2) * self.dpi;
                    case "centimeters", off = pos(1:2) * self.dpi / 2.54;
                    otherwise, off = pos(1:2) * 8;
                end
                xy = self.page([b(1) + off(1); b(2) + off(2)]);
            end
            if isempty(xy) || ~all(isfinite(xy))
                % texts outside an axes (layout titles, annotations): the
                % text primitive carries the resolved anchor
                try
                    ch = t.NodeChildren;
                    for i = 1:numel(ch)
                        if isa(ch(i), "matlab.graphics.primitive.world.Text") && MySVG.isOn(ch(i)) && ~isempty(ch(i).VertexData)
                            xy = self.page(MySVG.vert2px(ch(i), ch(i).VertexData(:, 1)));
                            break
                        end
                    end
                catch
                end
            end
            if (isempty(xy) || ~all(isfinite(xy))) && units == "data"
                xy = self.page(MySVG.data2px(t, pos(:)));
            end
            if isempty(xy) || ~all(isfinite(xy)), return; end
            if string(t.Clipping) == "on" && ~all(self.insideClip(xy)), return; end
            font = MySVG.fontOf(t);
            o = struct("ha", string(t.HorizontalAlignment), "va", string(t.VerticalAlignment), ...
                "rot", double(t.Rotation), "interp", string(t.Interpreter), "inherit", false, "box", []);
            bg = t.BackgroundColor; ec = t.EdgeColor;
            if isnumeric(bg) || isnumeric(ec)
                o.box = struct("bg", bg, "edge", ec, "margin", double(t.Margin) * self.k, ...
                    "lw", t.LineWidth, "style", string(t.LineStyle));
            end
            self.emitText(xy, lines, font, o);
        end

        function drawTextPrim(self, prim)
            % standalone text primitives: legend entries, contour labels, ...
            V = prim.VertexData;
            if isempty(V), return; end
            strs = MySVG.toLines(prim.String, false);
            if isempty(strs) || all(strlength(strs) == 0), return; end
            xy = self.page(MySVG.vert2px(prim, V));
            font = struct("name", "Helvetica", "size", 10, "bold", false, "italic", false, "rgba", [0 0 0 1]);
            o = struct("ha", "left", "va", "middle", "rot", 0, "interp", "tex", "inherit", false, "box", []);
            if ~isempty(self.legend)
                font = MySVG.fontOf(self.legend);
                font.rgba = [self.legend.TextColor(:)' 1];
                o.interp = string(self.legend.Interpreter);
            end
            try
                f = prim.Font;
                font.name = string(f.Name); font.size = double(f.Size);
                font.bold = string(f.Weight) == "bold"; font.italic = string(f.Angle) ~= "normal";
            catch
            end
            try
                c = self.colors(prim.ColorData, "object", "truecoloralpha");
                if ~isempty(c), font.rgba = c(:, 1)'; end
            catch
            end
            fields = ["HorizontalAlignment", "ha"; "VerticalAlignment", "va"; "Interpreter", "interp"];
            for i = 1:size(fields, 1)
                try
                    o.(fields(i, 2)) = string(prim.(fields(i, 1)));
                catch
                end
            end
            try
                o.rot = double(prim.Rotation);
            catch
            end
            if size(xy, 2) == 1
                self.emitText(xy, splitlines(strjoin(strs, newline)), font, o);
            else
                for i = 1:min(size(xy, 2), numel(strs))
                    if strlength(strs(i)) == 0 || ~all(isfinite(xy(:, i))), continue; end
                    self.emitText(xy(:, i), splitlines(strs(i)), font, o);
                end
            end
        end

        function emitText(self, xy, lines, font, o)
            % one <text> element; xy is the MATLAB anchor point [pt]
            lines = reshape(string(lines), 1, []);
            n = numel(lines);
            fs = font.size;
            m = self.fontMetrics(font);
            total = (m.asc + m.desc + (n - 1) * m.pitch) * fs;
            switch o.va
                case "top", y1 = m.asc * fs;
                case "cap", y1 = m.cap * fs;
                case "middle", y1 = m.asc * fs - total / 2;
                case "baseline", y1 = -(n - 1) * m.pitch * fs;
                otherwise, y1 = -(n - 1) * m.pitch * fs - m.desc * fs;
            end
            attrs = "";
            if ~o.inherit, attrs = MySVG.fontAttrs(font, o.ha); end
            rot = mod(o.rot, 360);
            if rot ~= 0
                attrs = attrs + sprintf(" transform=""rotate(%s %.2f %.2f)""", MySVG.trim(sprintf("%.2f", -rot)), xy(1), xy(2));
            end
            %% content
            interp = o.interp;
            body = strings(1, n);
            for i = 1:n
                body(i) = MySVG.runsToXml(MySVG.texRuns(lines(i), interp), fs);
            end
            if any(startsWith(lines, " ") | endsWith(lines, " ") | contains(lines, "  ")) || any(contains(body, "<tspan"))
                attrs = attrs + " xml:space=""preserve""";
            end
            %% background / edge box
            if ~isempty(o.box)
                wdt = self.textWidth(lines, font, interp);
                mg = o.box.margin;
                switch o.ha
                    case "center", x0 = -wdt / 2;
                    case "right", x0 = -wdt;
                    otherwise, x0 = 0;
                end
                y0 = y1 - m.asc * fs;
                a = MySVG.fillAttrs([]);
                if isnumeric(o.box.bg), a = MySVG.fillAttrs([o.box.bg(:)' 1]); end
                if isnumeric(o.box.edge) && o.box.style ~= "none"
                    a = a + MySVG.strokeAttrs([o.box.edge(:)' 1], o.box.lw, o.box.style, "miter");
                end
                if rot ~= 0
                    a = a + sprintf(" transform=""rotate(%s %.2f %.2f)""", MySVG.trim(sprintf("%.2f", -rot)), xy(1), xy(2));
                end
                self.add(sprintf("<rect x=""%.2f"" y=""%.2f"" width=""%.2f"" height=""%.2f""", ...
                    xy(1) + x0 - mg, xy(2) + y0 - mg, wdt + 2 * mg, total + 2 * mg) + a + "/>");
            end
            if n == 1
                self.add(sprintf("<text x=""%.2f"" y=""%.2f""", xy(1), xy(2) + y1) + attrs + ">" + body + "</text>");
            else
                s = "<text" + attrs + ">";
                for i = 1:n
                    s = s + sprintf("<tspan x=""%.2f"" y=""%.2f"">", xy(1), xy(2) + y1 + (i - 1) * m.pitch * fs) + body(i) + "</tspan>";
                end
                self.add(s + "</text>");
            end
        end

        function m = fontMetrics(self, font)
            % ascent / descent / cap height / line pitch in em, measured by MATLAB
            key = font.name + "|" + font.bold + "|" + font.italic;
            if isKey(self.metrics, key)
                m = self.metrics(key);
                return
            end
            m = struct("asc", 0.93, "desc", 0.22, "cap", 0.72, "pitch", 1.2);
            try
                t = self.measurer();
                weights = ["normal", "bold"]; angles = ["normal", "italic"];
                set(t, FontName=font.name, FontWeight=weights(1 + font.bold), FontAngle=angles(1 + font.italic), ...
                    FontSize=100, Interpreter="none", String="Hxg", VerticalAlignment="baseline");
                em = 100 * self.dpi / 72;
                e1 = t.Extent;
                t.VerticalAlignment = "cap";
                e2 = t.Extent;
                t.VerticalAlignment = "baseline";
                t.String = {'Hxg', 'Hxg'};
                e3 = t.Extent;
                c = struct("desc", -e1(2) / em, "asc", (e1(4) + e1(2)) / em, ...
                    "cap", -e2(2) / em + e1(2) / em, "pitch", (e3(4) - e1(4)) / em);
                if c.asc > 0.5 && c.asc < 1.6 && c.desc >= 0 && c.desc < 0.7 && c.pitch > 0.8 && c.pitch < 2
                    if ~(c.cap > 0.4 && c.cap < c.asc), c.cap = 0.75 * c.asc; end
                    m = orderfields(c, m);
                end
            catch err
                if self.debug, rethrow(err); end
            end
            self.metrics(key) = m;
        end

        function w = textWidth(self, lines, font, interp)
            w = max(strlength(lines)) * font.size * 0.55;
            try
                t = self.measurer();
                weights = ["normal", "bold"]; angles = ["normal", "italic"];
                if ~any(interp == ["tex", "none"]), interp = "none"; end
                set(t, FontName=font.name, FontWeight=weights(1 + font.bold), FontAngle=angles(1 + font.italic), ...
                    FontSize=font.size, Interpreter=interp, String=cellstr(lines), VerticalAlignment="baseline");
                e = t.Extent;
                w = e(3) * self.k;
            catch
            end
        end

        function t = measurer(self)
            if isempty(self.metricsText) || ~isvalid(self.metricsText)
                current = get(groot, "CurrentFigure");
                self.metricsFig = figure(Visible="off", HandleVisibility="off", Units="pixels", ...
                    Position=[0 0 400 400], IntegerHandle="off");
                ax = axes(self.metricsFig, Units="pixels", Position=[0 0 400 400], Visible="off");
                self.metricsText = text(ax, 0, 0, "", Units="pixels", FontUnits="points");
                if ~isempty(current) && isvalid(current)
                    set(groot, "CurrentFigure", current);
                end
            end
            t = self.metricsText;
            t.Position = [0 0 0];
        end
    end

    %% ------------------------------------------------------------ colour
    methods (Access = private)
        function c = colors(self, data, binding, type)
            % primitive colour data -> 4xN doubles in [0, 1]; empty when not drawn
            c = zeros(4, 0);
            type = string(type);
            if string(binding) == "none" || isempty(data) || type == "texturemapped", return; end
            if type == "colormapped"
                t = double(data(1, :));
                t(isnan(t)) = 0;
                n = size(self.cmap, 1);
                idx = min(max(round(t * (n - 1)) + 1, 1), n);
                c = [self.cmap(idx, :)'; ones(1, numel(idx))];
            else
                c = double(data) / 255;
                if size(c, 1) < 4, c(4, :) = 1; end
                c = c(1:4, :);
                if type == "truecolor", c(4, :) = 1; end
            end
            if string(binding) == "object", c = c(:, 1); end
        end

        function rgb = mapColors(self, v, mapping, nanFirst)
            % scalar colour data -> Nx3 through the current colormap and limits
            arguments
                self
                v
                mapping (1,1) string = "scaled"
                nanFirst (1,1) logical = false      % images paint NaN with the first colour
            end
            v = double(v(:));
            n = size(self.cmap, 1);
            if mapping == "direct"
                idx = floor(v);
            else
                lim = self.clim;
                if self.logColor && all(lim > 0)
                    v = log10(max(v, realmin)); lim = log10(lim);
                end
                idx = floor((v - lim(1)) / max(diff(lim), eps) * n) + 1;
            end
            bad = isnan(idx);
            idx = min(max(idx, 1), n);
            idx(bad) = 1;
            rgb = self.cmap(idx, :);
            if ~nanFirst, rgb(isnan(v), :) = NaN; end
        end

        function tf = insideClip(self, p)
            tf = true(1, size(p, 2));
            if isempty(self.clipBox), return; end
            b = self.clipBox;
            tf = p(1,:) >= b(1) & p(1,:) <= b(3) & p(2,:) >= b(2) & p(2,:) <= b(4);
        end

        function d = polylineData(self, p, closed)
            % path data for one polyline: split at gaps, clipped to the plot box
            d = "";
            if isempty(p), return; end
            ok = all(isfinite(p), 1);
            if closed && all(ok) && all(self.insideClip(p))
                d = MySVG.pathData(p, true);
                return
            end
            if closed, p = p(:, [1:end, 1]); ok = ok([1:end, 1]); end
            if size(p, 2) > 3 && all(ok) && all(abs(p(:, 1) - p(:, end)) < 1e-6) && all(self.insideClip(p))
                d = MySVG.pathData(p(:, 1:end - 1), true);   % an explicitly closed outline
                return
            end
            edges = diff([false, ok, false]);
            starts = find(edges == 1);
            stops = find(edges == -1) - 1;
            parts = strings(1, 0);
            for r = 1:numel(starts)
                q = p(:, starts(r):stops(r));
                if isempty(self.clipBox)
                    pieces = {q};
                else
                    pieces = MySVG.clipPolyline(q, self.clipBox);
                end
                for i = 1:numel(pieces)
                    if size(pieces{i}, 2) == 1
                        pieces{i} = [pieces{i}, pieces{i}];
                        if size(q, 2) > 1, continue; end
                    end
                    parts(end+1) = MySVG.pathData(pieces{i}, false); %#ok<AGROW>
                end
            end
            d = strjoin(parts, " ");
        end
    end

    %% ------------------------------------------------------------ static
    methods (Static, Access = private)
        function tf = isOn(node)
            tf = true;
            try
                tf = string(node.Visible) == "on";
            catch
            end
        end

        function name = typeName(node, cls)
            name = "";
            if startsWith(cls, ["matlab.ui.", "matlab.graphics.shape.internal.", "matlab.graphics.primitive.canvas."])
                return
            end
            try
                name = string(node.Type);
            catch
                return
            end
            if any(name == ["figure", "root", "annotationpane", "hgtransform"]), name = ""; return; end
            try
                dn = string(node.DisplayName);
                if isscalar(dn) && strlength(dn) > 0 && strlength(dn) < 30
                    dn = regexprep(dn, "[^A-Za-z0-9]+", "_");
                    name = name + "-" + dn;
                end
            catch
            end
        end

        function px = data2px(obj, data)
            data = double(data);
            px = double(matlab.graphics.chart.internal.convertDataSpaceCoordsToViewerCoords(obj, data));
            px(:, ~all(isfinite(data), 1) | any(abs(px) > 1e7, 1)) = NaN;
        end

        function px = vert2px(prim, V, withDepth)
            arguments
                prim
                V
                withDepth (1,1) logical = false
            end
            if withDepth
                [cam, above, space, below] = matlab.graphics.internal.getSpatialTransforms(prim);
                px = double(matlab.graphics.internal.transformWorldToViewer(cam, above, space, below, V, true));
            else
                px = double(matlab.graphics.chart.internal.convertVertexCoordsToViewerCoords(prim, V));
            end
        end

        function v = num(v, ruler)
            if ~isnumeric(v)
                v = ruler2num(v, ruler);
            end
            v = reshape(double(v), 1, []);
        end

        function lim = limits(r)
            % numeric limits of a ruler (categorical rulers pad theirs)
            try
                lim = double(r.NumericLimits);
            catch
                lim = MySVG.num(r.Limits, r);
            end
            lim = reshape(lim, 1, []);
        end

        function m = midpoint(r)
            % a data value in the middle of a ruler, safe for log scales
            lim = MySVG.limits(r);
            if string(r.Scale) == "log" && all(lim > 0)
                m = sqrt(prod(lim));
            else
                m = mean(lim);
            end
        end

        function f = rulerFrac(r, values)
            % position of values along a ruler as a fraction of its length
            lim = MySVG.limits(r);
            v = MySVG.num(values, r);
            if string(r.Scale) == "log"
                f = (log10(v) - log10(lim(1))) / (log10(lim(2)) - log10(lim(1)));
            else
                f = (v - lim(1)) / (lim(2) - lim(1));
            end
            reversed = false;
            try
                reversed = string(r.Direction) == "reverse";
            catch
            end
            if reversed, f = 1 - f; end
            f = real(f);
        end

        function d = axisLine(isX, ends, pos)
            if isX
                d = sprintf("M%.2f,%.2f H%.2f", ends(1), pos, ends(2));
            else
                d = sprintf("M%.2f,%.2f V%.2f", pos, ends(1), ends(2));
            end
            d = MySVG.trim(d);
        end

        function d = tickPath(isX, c, a, b)
            c = reshape(c, 1, []);
            if isX
                d = sprintf("M%.2f,%.2f V%.2f ", [c; repmat([a; b], 1, numel(c))]);
            else
                d = sprintf("M%.2f,%.2f H%.2f ", [repmat(a, 1, numel(c)); c; repmat(b, 1, numel(c))]);
            end
            d = MySVG.trim(d);
        end

        function d = pathData(p, closed)
            d = "M" + MySVG.trim(strtrim(sprintf("%.2f,%.2f ", p)));
            if closed, d = d + "Z"; end
        end

        function s = trim(s)
            % drops trailing zeros of formatted numbers ("12.50" -> "12.5")
            s = regexprep(string(s), "(\.\d*?)0+(?!\d)", "$1");
            s = regexprep(s, "\.(?!\d)", "");
        end

        function s = reEscape(s)
            % escapes a replacement string for regexprep
            s = strrep(strrep(string(s), "\", "\\"), "$", "\$");
        end

        function s = hex(rgb)
            s = string(sprintf("#%02x%02x%02x", round(min(max(double(rgb(1:3)), 0), 1) * 255)));
        end

        function a = fillAttrs(rgba)
            if isempty(rgba) || numel(rgba) < 3
                a = " fill=""none""";
                return
            end
            a = " fill=""" + MySVG.hex(rgba) + """";
            if numel(rgba) > 3 && rgba(4) < 1
                a = a + sprintf(" fill-opacity=""%.3g""", rgba(4));
            end
        end

        function a = fillAttrsMany(rgba)
            a = compose(" fill=""#%02x%02x%02x""", round(rgba(1:3, :)' * 255));
            if any(rgba(4, :) < 1), a = a + compose(" fill-opacity=""%.3g""", rgba(4, :)'); end
        end

        function a = strokeAttrs(rgba, lw, style, join, cap)
            arguments
                rgba
                lw (1,1) double
                style = "-"
                join = "round"
                cap = "none"
            end
            style = string(style);
            if isempty(rgba) || numel(rgba) < 3 || style == "none" || lw <= 0
                a = "";
                return
            end
            a = " stroke=""" + MySVG.hex(rgba) + """ stroke-width=""" + MySVG.trim(sprintf("%.2f", lw)) + """";
            if numel(rgba) > 3 && rgba(4) < 1
                a = a + sprintf(" stroke-opacity=""%.3g""", rgba(4));
            end
            switch style                            % MATLAB's own dash proportions
                case {"dashed", "--"}, dash = [max(5, 4 * lw), max(3, 4 * lw)];
                case {"dotted", ":"}, dash = [lw, max(1.5, lw)];
                case {"dashdot", "-."}, dash = [max(4, 4 * lw), max(1.5, lw), max(1, 2 * lw), max(1.5, lw)];
                otherwise, dash = [];
            end
            if ~isempty(dash)
                a = a + " stroke-dasharray=""" + MySVG.trim(strjoin(compose("%.2f", dash), ",")) + """";
            end
            join = string(join);
            if join == "round", a = a + " stroke-linejoin=""round""";
            elseif join == "chamfer", a = a + " stroke-linejoin=""bevel""";
            end
            cap = string(cap);
            if any(cap == ["square", "round"]), a = a + " stroke-linecap=""" + cap + """"; end
        end

        function a = lineAttrs(varargin)
            % stroke attributes for an unfilled line
            a = " fill=""none""" + MySVG.strokeAttrs(varargin{:});
        end

        function c = rgba(c, alpha, i)
            % [r g b a] from a colour table row, or [] when there is no colour
            arguments
                c
                alpha (1,1) double = 1
                i (1,1) double = 1
            end
            if isempty(c), c = []; return; end
            c = [c(min(i, size(c, 1)), 1:3), alpha];
        end

        function a = fontAttrs(font, ha)
            name = font.name;
            if contains(name, [",", "'"]) == false && contains(name, " "), name = "'" + name + "'"; end
            a = " font-family=""" + name + """ font-size=""" + MySVG.trim(sprintf("%.2f", font.size)) + """";
            if font.bold, a = a + " font-weight=""bold"""; end
            if font.italic, a = a + " font-style=""italic"""; end
            a = a + " fill=""" + MySVG.hex(font.rgba) + """";
            if numel(font.rgba) > 3 && font.rgba(4) < 1, a = a + sprintf(" fill-opacity=""%.3g""", font.rgba(4)); end
            switch ha
                case "center", a = a + " text-anchor=""middle""";
                case "right", a = a + " text-anchor=""end""";
            end
        end

        function font = fontOf(h)
            font = struct("name", string(h.FontName), "size", double(h.FontSize), ...
                "bold", false, "italic", false, "rgba", [0 0 0 1]);
            try
                font.bold = string(h.FontWeight) == "bold";
                font.italic = string(h.FontAngle) ~= "normal";
            catch
            end
            try
                units = string(h.FontUnits);
                switch units
                    case "pixels", font.size = font.size * 72 / get(groot, "ScreenPixelsPerInch");
                    case "inches", font.size = font.size * 72;
                    case "centimeters", font.size = font.size * 72 / 2.54;
                end
            catch
            end
            try
                if isnumeric(h.Color), font.rgba = [h.Color(:)' 1]; end
            catch
            end
        end

        function a = alphaOf(h, prop)
            a = 1;
            try
                v = h.(prop);
                if isnumeric(v) && isscalar(v), a = double(v); end
            catch
            end
        end

        function c = scatterColor(spec, flat, axColor, alpha)
            % 4xN (per point), 4x1 (uniform), or empty (not drawn)
            if isnumeric(spec)
                c = [spec(:); alpha];
            else
                switch string(spec)
                    case "flat", c = [flat'; repmat(alpha, 1, size(flat, 1))];
                    case "auto", c = [axColor(:); alpha];
                    otherwise, c = zeros(4, 0);
                end
            end
            if size(c, 2) > 1 && size(unique(c', "rows"), 1) == 1, c = c(:, 1); end
        end

        function c = patchColor(spec, flat, nF)
            % Nx3 (per face), 1x3 (uniform), or empty (not drawn)
            if isnumeric(spec)
                c = reshape(spec, 1, 3);
            elseif any(string(spec) == ["flat", "interp"]) && ~isempty(flat)
                c = flat;
                if size(c, 1) ~= nF, c = repmat(c(1, :), nF, 1); end
                if size(unique(c, "rows"), 1) == 1, c = c(1, :); end
            else
                c = zeros(0, 3);
            end
        end

        function e = pixelEdges(d, n)
            % outer edges of an image axis from the centres of its end pixels
            d = d(isfinite(d));
            if isempty(d), d = [1 n]; end
            if n > 1 && d(end) ~= d(1)
                half = (d(end) - d(1)) / (n - 1) / 2;
            else
                half = 0.5;
            end
            e = [d(1) - half, d(end) + half];
        end

        function style = markerStyle(s)
            s = lower(string(s));
            names = ["o", "circle"; "+", "plus"; "*", "asterisk"; ".", "point"; "x", "cross"; ...
                "_", "hbar"; "|", "vbar"; "s", "square"; "d", "diamond"; "^", "triangleup"; ...
                "v", "triangledown"; ">", "triangleright"; "<", "triangleleft"; "p", "pentagram"; ...
                "h", "hexagram"; "upwardtriangle", "triangleup"; "downwardtriangle", "triangledown"; ...
                "righttriangle", "triangleright"; "lefttriangle", "triangleleft"; ...
                "uptriangle", "triangleup"; "downtriangle", "triangledown"; "triangle", "triangleup"; ...
                "star", "pentagram"; "hexagon", "hexagram"; "horizontalline", "hbar"; "verticalline", "vbar"];
            i = find(names(:, 1) == s, 1);
            if isempty(i), style = s; else, style = names(i, 2); end
        end

        function shape = markerShape(style)
            % unit marker geometry (y down), measured from MATLAB's own output
            shape = struct("kind", "poly", "pts", {{}}, "fillable", true, "r", 0.5);
            tri = [0 -0.576 0.576; -0.665 0.333 0.333];
            switch style
                case "circle", shape.kind = "circle";
                case "point", shape.kind = "dot"; shape.r = 1 / 6;
                case "square", shape.kind = "rect"; shape.r = 0.39;
                case "diamond", shape.pts = {[-0.5 0 0.5 0; 0 0.665 0 -0.665]};
                case "triangleup", shape.pts = {tri};
                case "triangledown", shape.pts = {[tri(1, :); -tri(2, :)]};
                case "triangleleft", shape.pts = {[tri(2, :); tri(1, :)]};
                case "triangleright", shape.pts = {[-tri(2, :); tri(1, :)]};
                case "pentagram"
                    shape.pts = {[-0.475 -0.117 0 0.118 0.476 0.19 0.294 0 -0.294 -0.19; ...
                        -0.155 -0.155 -0.5 -0.155 -0.155 0.062 0.404 0.2 0.404 0.062]};
                case "hexagram"
                    shape.pts = {[-0.433 -0.144 0 0.144 0.433 0.25 0.433 0.144 0 -0.144 -0.433 -0.25; ...
                        -0.25 -0.25 -0.5 -0.25 -0.25 0 0.25 0.25 0.5 0.25 0.25 0]};
                case "plus", shape.pts = {[0 0; -0.5 0.5], [-0.5 0.5; 0 0]}; shape.fillable = false;
                case "cross", shape.pts = {[-0.354 0.354; -0.354 0.354], [-0.354 0.354; 0.354 -0.354]}; shape.fillable = false;
                case "asterisk"
                    shape.pts = {[0 0; -0.5 0.5], [-0.5 0.5; 0 0], [-0.354 0.354; -0.354 0.354], [-0.354 0.354; 0.354 -0.354]};
                    shape.fillable = false;
                case "hbar", shape.pts = {[-0.5 0.5; 0 0]}; shape.fillable = false;
                case "vbar", shape.pts = {[0 0; -0.5 0.5]}; shape.fillable = false;
                otherwise, shape.kind = "none";
            end
        end

        function stops = gradientStops(colors)
            % gradient stops for a colormap: smooth maps are thinned to the
            % stops that matter; small (discrete) maps keep hard steps
            n = size(colors, 1);
            if n < 64
                off = [0:n - 1; 1:n] / n;
                rows = compose("<stop offset=""%.4f"" stop-color=""#%02x%02x%02x""/>", ...
                    off(:), round(repelem(colors, 2, 1) * 255));
            else
                keep = 1;
                i = 1;
                while i < n
                    j = n;
                    while j > i + 1
                        t = ((i:j)' - i) / (j - i);
                        fit = colors(i, :) + t .* (colors(j, :) - colors(i, :));
                        if max(abs(fit - colors(i:j, :)), [], "all") < 1.5 / 255, break; end
                        j = i + max(1, floor((j - i) / 2));
                    end
                    keep(end+1) = j; %#ok<AGROW>
                    i = j;
                end
                rows = compose("<stop offset=""%.4f"" stop-color=""#%02x%02x%02x""/>", ...
                    (keep(:) - 1) / (n - 1), round(colors(keep, :) * 255));
            end
            stops = strjoin(rows, "");
        end

        function d = unionData(p, polys)
            % outline of a set of triangles (prefixed "evenodd:" when it has holes)
            d = "";
            if numel(polys) > MySVG.MAX_UNION, return; end
            state = warning("off", "all");
            restore = onCleanup(@() warning(state));
            try
                shapes = repmat(polyshape, 1, numel(polys));
                for i = 1:numel(polys)
                    q = p(:, polys{i});
                    shapes(i) = polyshape(q(1, :), q(2, :), Simplify=false);
                end
                u = union(shapes);
                if u.NumRegions == 0, return; end
                [x, y] = boundary(u);
                cuts = [0; find(isnan(x)); numel(x) + 1];
                parts = strings(1, numel(cuts) - 1);
                for i = 1:numel(cuts) - 1
                    idx = cuts(i) + 1:cuts(i + 1) - 1;
                    if numel(idx) > 1 && x(idx(1)) == x(idx(end)) && y(idx(1)) == y(idx(end)), idx(end) = []; end
                    if numel(idx) < 3, continue; end
                    parts(i) = MySVG.pathData([x(idx)'; y(idx)'], true);
                end
                d = strjoin(parts(parts ~= ""), " ");
                if u.NumHoles > 0 && d ~= "", d = "evenodd:" + d; end
            catch
                d = "";
            end
        end

        function pieces = clipPolyline(p, box)
            % clips a polyline to a rectangle (Liang-Barsky per segment)
            n = size(p, 2);
            in = p(1,:) >= box(1) & p(1,:) <= box(3) & p(2,:) >= box(2) & p(2,:) <= box(4);
            if all(in), pieces = {p}; return; end
            pieces = {};
            if n == 1, return; end
            out = nan(2, 2 * n + 2);
            m = 0;
            open = false;
            for i = 1:n - 1
                if in(i) && in(i + 1)
                    if ~open, m = m + 1; out(:, m) = p(:, i); open = true; end
                    m = m + 1; out(:, m) = p(:, i + 1);
                    continue
                end
                a = p(:, i); dlt = p(:, i + 1) - a;
                t0 = 0; t1 = 1; ok = true;
                pk = [-dlt(1), dlt(1), -dlt(2), dlt(2)];
                qk = [a(1) - box(1), box(3) - a(1), a(2) - box(2), box(4) - a(2)];
                for e = 1:4
                    if pk(e) == 0
                        if qk(e) < 0, ok = false; break; end
                    else
                        r = qk(e) / pk(e);
                        if pk(e) < 0, t0 = max(t0, r); else, t1 = min(t1, r); end
                        if t0 > t1, ok = false; break; end
                    end
                end
                if ~ok
                    if open, m = m + 1; open = false; end   % NaN separator
                    continue
                end
                if ~open || t0 > 0
                    if open, m = m + 1; end
                    m = m + 1; out(:, m) = a + t0 * dlt; open = true;
                end
                m = m + 1; out(:, m) = a + t1 * dlt;
                if t1 < 1, m = m + 1; open = false; end
            end
            out = out(:, 1:m);
            gaps = [0, find(isnan(out(1, :))), m + 1];
            for g = 1:numel(gaps) - 1
                q = out(:, gaps(g) + 1:gaps(g + 1) - 1);
                if size(q, 2) >= 2, pieces{end+1} = q; end %#ok<AGROW>
            end
        end

        function [p, sz, face, edge] = depthSort(h, data, keep, p, sz, face, edge)
            % far-to-near order for 3D scatter points
            idx = find(keep);
            try
                [cam, above, space, below] = matlab.graphics.internal.getSpatialTransforms(h);
                w = matlab.graphics.internal.transformDataToWorld(space, below, double(data(:, idx)));
                v = double(matlab.graphics.internal.transformWorldToViewer(cam, above, space, below, w, true));
                [~, order] = sort(v(3, :), "descend");
            catch
                order = 1:numel(idx);
            end
            p = p(:, idx(order)); sz = sz(idx(order));
            if size(face, 2) > 1, face = face(:, order); end
            if size(edge, 2) > 1, edge = edge(:, order); end
        end

        function order = faceOrder(h, V, F)
            % far-to-near order for the faces of a 3D patch
            order = 1:size(F, 1);
            try
                [cam, above, space, below] = matlab.graphics.internal.getSpatialTransforms(h);
                w = matlab.graphics.internal.transformDataToWorld(space, below, V');
                v = double(matlab.graphics.internal.transformWorldToViewer(cam, above, space, below, w, true));
                z = v(3, :);
                G = F; G(isnan(G)) = 1;
                depth = z(G);
                depth(isnan(F)) = NaN;
                [~, order] = sort(mean(reshape(depth, size(F)), 2, "omitnan"), "descend");
                order = order';
            catch
            end
        end

        function lines = toLines(str, split)
            % String property (char, char matrix, cellstr, string, numeric) -> lines
            arguments
                str
                split (1,1) logical = true
            end
            if isnumeric(str), str = string(str); end
            if ischar(str) && size(str, 1) > 1
                lines = string(cellstr(str));
            else
                lines = string(str);
            end
            lines = reshape(lines, 1, []);
            lines(ismissing(lines)) = "";
            if split && ~isempty(lines)
                lines = splitlines(strjoin(lines, newline))';
                lines = reshape(lines, 1, []);
            end
            if isempty(lines), lines = ""; end
        end

        function xml = runsToXml(runs, fs)
            % styled runs -> text content (plain text or <tspan> elements)
            xml = "";
            shift = 0;
            for i = 1:numel(runs)
                r = runs(i);
                txt = replace(r.text, ["&", "<", ">"], ["&amp;", "&lt;", "&gt;"]);
                a = "";
                if r.bold == 1, a = a + " font-weight=""bold"""; elseif r.bold == 0, a = a + " font-weight=""normal"""; end
                if r.italic == 1, a = a + " font-style=""italic"""; elseif r.italic == 0, a = a + " font-style=""normal"""; end
                base = fs;
                if r.size > 0, base = r.size; end
                if r.scale ~= 1 || r.size > 0
                    a = a + " font-size=""" + MySVG.trim(sprintf("%.2f", r.scale * base)) + """";
                end
                if ~isempty(r.color), a = a + " fill=""" + MySVG.hex(r.color) + """"; end
                if r.font ~= "", a = a + " font-family=""" + r.font + """"; end
                if abs(r.shift - shift) > 1e-9
                    a = a + " dy=""" + MySVG.trim(sprintf("%.2f", -(r.shift - shift) * fs)) + """";
                    shift = r.shift;
                end
                if a == ""
                    xml = xml + txt;
                else
                    xml = xml + "<tspan" + a + ">" + txt + "</tspan>";
                end
            end
        end

        function runs = texRuns(str, interp)
            % splits a string into styled runs using MATLAB's TeX subset
            %   bold / italic: -1 inherit, 0 off, 1 on; size: 0 inherit, else points;
            %   scale multiplies the size; shift in em (up positive)
            blank = struct("text", "", "bold", -1, "italic", -1, "scale", 1, "size", 0, "shift", 0, "color", [], "font", "");
            str = char(str);
            if interp == "none" || ~any(ismember('\^_{}$', str))
                runs = blank;
                runs.text = string(str);
                return
            end
            if interp == "latex", str = strrep(str, '$', ''); end
            runs = repmat(blank, 1, 0);
            [runs, ~] = MySVG.texGroup(str, 1, blank, runs, false);
            runs = runs(arrayfun(@(r) strlength(r.text) > 0, runs));
            if isempty(runs), runs = blank; end
        end

        function [runs, i] = texGroup(s, i, st, runs, inBraces)
            n = numel(s);
            while i <= n
                c = s(i);
                switch c
                    case '}'
                        i = i + 1;
                        if inBraces, return; end
                    case '{'
                        [runs, i] = MySVG.texGroup(s, i + 1, st, runs, true);
                    case {'^', '_'}
                        sub = st;
                        sub.scale = st.scale * 0.7;
                        if c == '^'
                            sub.shift = st.shift + 0.42 * abs(st.scale);
                        else
                            sub.shift = st.shift - 0.18 * abs(st.scale);
                        end
                        i = i + 1;
                        if i > n, break; end
                        if s(i) == '{'
                            [runs, i] = MySVG.texGroup(s, i + 1, sub, runs, true);
                        elseif s(i) == '\'
                            [runs, i, ~] = MySVG.texCommand(s, i, sub, runs);
                        else
                            runs = MySVG.texAppend(runs, sub, s(i));
                            i = i + 1;
                        end
                    case '\'
                        [runs, i, st] = MySVG.texCommand(s, i, st, runs);
                    otherwise
                        runs = MySVG.texAppend(runs, st, c);
                        i = i + 1;
                end
            end
        end

        function [runs, i, st] = texCommand(s, i, st, runs, maxLen)
            % handles the command starting at s(i) == '\'
            arguments
                s
                i
                st
                runs
                maxLen (1,1) double = Inf
            end
            n = numel(s);
            j = i + 1;
            while j <= n && isletter(s(j)) && j - i <= maxLen, j = j + 1; end
            name = string(s(i + 1:j - 1));
            if name == ""                               % escaped character
                if i < n
                    runs = MySVG.texAppend(runs, st, s(i + 1));
                end
                i = i + 2;
                return
            end
            i = j;
            switch name
                case "bf", st.bold = 1;
                case {"it", "sl"}, st.italic = 1;
                case "rm", st.bold = 0; st.italic = 0;
                case {"fontname", "fontsize", "color"}
                    model = "";
                    if i <= n && s(i) == '['
                        e = find(s(i:end) == ']', 1) + i - 1;
                        if ~isempty(e), model = string(s(i + 1:e - 1)); i = e + 1; end
                    end
                    arg = "";
                    if i <= n && s(i) == '{'
                        e = find(s(i:end) == '}', 1) + i - 1;
                        if ~isempty(e), arg = string(s(i + 1:e - 1)); i = e + 1; end
                    end
                    switch name
                        case "fontname", st.font = arg;
                        case "fontsize"
                            v = str2double(arg);
                            if isfinite(v) && v > 0, st.size = v; end
                        case "color"
                            try
                                if model == "rgb"
                                    st.color = str2double(split(strtrim(arg)))';
                                else
                                    st.color = validatecolor(arg);
                                end
                            catch
                            end
                    end
                case {"mathrm", "text", "textrm", "mathbf", "textbf", "mathit", "textit", "mathsf", "operatorname", "mathcal", "mathbb"}
                    sub = st;
                    if any(name == ["mathbf", "textbf"]), sub.bold = 1; end
                    if any(name == ["mathit", "textit"]), sub.italic = 1; end
                    if any(name == ["mathrm", "text", "textrm"]), sub.italic = 0; end
                    if i <= n && s(i) == '{'
                        [runs, i] = MySVG.texGroup(s, i + 1, sub, runs, true);
                    end
                case {"left", "right", "displaystyle", "limits", "newline"}
                otherwise
                    sym = MySVG.texSymbol(name);
                    if sym == "" && startsWith(name, ["bf", "it", "sl", "rm"])
                        % modifiers need no separator: "\bfbold"
                        [runs, ~, st] = MySVG.texCommand(s, i - strlength(name) - 1, st, runs, 2);
                        i = i - strlength(name) + 2;
                    elseif sym == ""
                        runs = MySVG.texAppend(runs, st, char("\" + name));
                    else
                        runs = MySVG.texAppend(runs, st, char(sym));
                    end
            end
        end

        function runs = texAppend(runs, st, txt)
            same = ~isempty(runs) && isequaln(rmfield(runs(end), "text"), rmfield(st, "text"));
            if same
                runs(end).text = runs(end).text + string(txt);
            else
                st.text = string(txt);
                runs(end+1) = st;
            end
        end

        function sym = texSymbol(name)
            persistent map
            if isempty(map)
                names = ["alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta", ...
                    "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "varpi", "rho", "sigma", "varsigma", "tau", ...
                    "upsilon", "phi", "varphi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", ...
                    "Sigma", "Upsilon", "Phi", "Psi", "Omega", "leq", "le", "geq", "ge", "neq", "ne", "pm", "mp", "times", ...
                    "div", "cdot", "ast", "circ", "bullet", "infty", "partial", "nabla", "approx", "equiv", "cong", ...
                    "sim", "propto", "leftarrow", "rightarrow", "to", "uparrow", "downarrow", "leftrightarrow", ...
                    "Leftarrow", "Rightarrow", "Leftrightarrow", "forall", "exists", "in", "ni", "subset", "supset", ...
                    "subseteq", "supseteq", "cup", "cap", "int", "sum", "prod", "surd", "sqrt", "angle", "perp", "mid", ...
                    "neg", "wedge", "vee", "oplus", "otimes", "oslash", "langle", "rangle", "lceil", "rceil", ...
                    "lfloor", "rfloor", "ldots", "cdots", "prime", "aleph", "Re", "Im", "wp", "copyright", "deg", ...
                    "degree", "o", "clubsuit", "diamondsuit", "heartsuit", "spadesuit", "ll", "gg", "ell", "hbar", ...
                    "dagger", "star", "quad", "qquad"];
                codes = [945 946 947 948 949 949 950 951 952 977 ...
                    953 954 955 956 957 958 960 982 961 963 962 964 ...
                    965 966 966 967 968 969 915 916 920 923 926 928 ...
                    931 933 934 936 937 8804 8804 8805 8805 8800 8800 177 8723 215 ...
                    247 183 8727 8728 8226 8734 8706 8711 8776 8801 8773 ...
                    8764 8733 8592 8594 8594 8593 8595 8596 ...
                    8656 8658 8660 8704 8707 8712 8715 8834 8835 ...
                    8838 8839 8746 8745 8747 8721 8719 8730 8730 8736 8869 8739 ...
                    172 8743 8744 8853 8855 8856 10216 10217 8968 8969 ...
                    8970 8971 8230 8943 8242 8501 8476 8465 8472 169 176 ...
                    176 248 9827 9830 9829 9824 8810 8811 8467 8463 ...
                    8224 8902 8195 8195];
                map = dictionary(names, string(arrayfun(@(c) {char(c)}, codes)));
            end
            if isKey(map, name), sym = map(name); else, sym = ""; end
        end
    end
end
