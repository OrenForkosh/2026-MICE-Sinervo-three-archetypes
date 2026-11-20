classdef MyPareto
    % MyPareto__Minimal polytope enclosing a point cloud (Pareto archetypes).
    %   A fitted MyPareto object holds the vertices of a polytope (the
    %   archetypes) fitted around a set of points, together with which of
    %   the points fall inside it. The entry point is MyPareto.fit, which
    %   wraps the five simplex algorithms shipped with ParTI (Hart et al.,
    %   Nat Methods 2015) plus an exact 2-D triangle and a general 2-D
    %   k-gon fit, behind one modern interface with named options.
    %
    %   Algorithms (Algorithm option)
    %       "exact"  Smallest-area triangle enclosing every point. 2-D only,
    %                3 vertices only. Deterministic.
    %       "sisal"  ParTI default. Minimum-volume simplex with soft
    %                constraints (Tau), so a few points may lie outside.
    %       "mvsa"   Minimum-volume simplex, hard constraints.
    %       "mves"   Minimum-volume enclosing simplex (needs SeDuMi, which
    %                ships without Apple-silicon binaries).
    %       "sdvmm"  Maximum-volume inscribed simplex from data points.
    %       "pcha"   Archetypal analysis; archetypes lie inside the convex
    %                hull (Delta > 0 lets them move outside). Any k.
    %       "cover"  Smallest-area convex k-gon that covers a fraction of
    %                the points. 2-D only, any k >= 3.
    %       "hull"   Convex hull of the points; k is ignored.
    %       "auto"   "exact" for a 2-D triangle, "sisal" for any other
    %                simplex (k <= ndims + 1), "cover" for a 2-D k-gon.
    %
    %   The simplex algorithms fit at most ndims + 1 vertices. For more
    %   vertices use "cover" (2-D) or "pcha".
    %
    %   Example
    %       X = [rand(300, 1), rand(300, 1)];
    %       p = MyPareto.fit(X, 3);                       % exact triangle
    %       p = MyPareto.fit(X, 3, Algorithm="sisal");    % ParTI's default
    %       p = MyPareto.fit(X, 3, Coverage=0.95);        % ignore 5% outliers
    %       p = MyPareto.fit(X, 5, Coverage=0.9);         % pentagon
    %       p.plot(Data=X);
    %       w = p.weights(X);                             % barycentric
    %
    %   See also: MyPareto.fit, MyPareto.plot, MyPareto.test

    properties (SetAccess = private)
        vertices  (:,:) double  = zeros(0, 2)   % nvertices x ndims, archetypes
        algorithm (1,1) string  = ""            % algorithm that produced the fit
        volume    (1,1) double  = NaN           % volume (area in 2-D) of the polytope
        inside    (:,1) logical = false(0, 1)   % per fitted point: inside the polytope
        violation (:,1) double  = zeros(0, 1)   % per fitted point: distance beyond the boundary (0 inside)
        coverage  (1,1) double  = NaN           % fraction of fitted points inside
        options   (1,1) struct  = struct()      % resolved fit options
    end

    properties (Dependent)
        nvertices
        ndims
        isSimplex
    end

    %% ---------------------------------------------------------------- fitting
    methods (Static)
        function obj = fit(X, k, opts)
            % fit__Fit a k-vertex polytope around the rows of X.
            %   Rows of X are points, columns are dimensions. Rows with NaN
            %   are ignored for fitting and reported as outside.
            %
            %   Options
            %       Algorithm      (string, default "auto"): See class help.
            %       Coverage       (double, default 1): Fraction of points the
            %                      polytope is fitted to. Below 1, the most
            %                      extreme points are peeled off first (see
            %                      MyPareto.peelHull) and ignored by the fit.
            %       Restarts       (double, default 10): Random restarts for
            %                      the stochastic algorithms (sisal, mvsa,
            %                      pcha, cover); the best fit is kept.
            %       Tau            (double, default 1): SISAL penalty on points
            %                      outside the simplex. Smaller is more
            %                      tolerant to outliers.
            %       Delta          (double, default 0): PCHA relaxation that
            %                      lets archetypes leave the convex hull.
            %       BackOff        (double, default 0): SDVMM back-off,
            %                      about 1.3 x noise standard deviation.
            %       Seed           (double, default []): rng seed for a
            %                      reproducible fit; the rng state is restored.
            %       Verbose        (logical, default false): Print progress.
            %
            %   Example
            %       p = MyPareto.fit(X, 3, Algorithm="sisal", Coverage=0.95);
            arguments
                X (:,:) double {mustBeNonempty}
                k (1,1) double {mustBeInteger, mustBePositive} = 3
                opts.Algorithm (1,1) string {mustBeMember(opts.Algorithm, ...
                    ["auto", "exact", "sisal", "mvsa", "mves", "sdvmm", "pcha", "cover", "hull"])} = "auto"
                opts.Coverage (1,1) double {mustBeInRange(opts.Coverage, 0, 1, "exclude-lower")} = 1
                opts.Restarts (1,1) double {mustBeInteger, mustBePositive} = 10
                opts.Tau (1,1) double {mustBePositive} = 1
                opts.Delta (1,1) double {mustBeNonnegative} = 0
                opts.BackOff (1,1) double {mustBeNonnegative} = 0
                opts.Seed double = []
                opts.Verbose (1,1) logical = false
            end
            valid = all(isfinite(X), 2);
            [~, d] = size(X);
            if d < 2
                error("MyPareto:dims", "Points must have at least two columns.");
            end
            alg = MyPareto.resolveAlgorithm(opts.Algorithm, k, d);
            if ~isempty(opts.Seed)
                previous = rng;
                restore = onCleanup(@() rng(previous)); %#ok<NASGU>
                rng(opts.Seed);
            end
            if opts.Verbose
                fprintf("MyPareto: fitting %d vertices to %d points in %d-D with %s\n", k, nnz(valid), d, alg);
            end

            tol = 1e-9 * max(range(X(valid, :)), [], "all");
            nOut = floor((1 - opts.Coverage) * nnz(valid));
            keep = valid;
            if nOut > 0 && alg ~= "cover"   % "cover" handles Coverage itself
                keep(valid) = MyPareto.peelHull(X(valid, :), nOut);
                if opts.Verbose
                    fprintf("  peeled off the %d most extreme points\n", nOut);
                end
            end
            V = MyPareto.fitOnce(X(keep, :), k, alg, opts);
            violation = MyPareto.violationOf(V, X);

            obj = MyPareto();
            obj.vertices = MyPareto.orderVertices(V);
            obj.algorithm = alg;
            obj.volume = MyPareto.volumeOf(V);
            obj.violation = violation;
            obj.inside = valid & violation <= tol;
            obj.coverage = nnz(obj.inside) / nnz(valid);
            opts.Algorithm = alg;
            obj.options = opts;
            if opts.Verbose
                fprintf("  volume %.4g, %.1f%% of points inside\n", obj.volume, 100 * obj.coverage);
            end
        end
    end

    %% ---------------------------------------------------------------- queries
    methods
        function n = get.nvertices(obj)
            n = size(obj.vertices, 1);
        end

        function d = get.ndims(obj)
            d = size(obj.vertices, 2);
        end

        function tf = get.isSimplex(obj)
            tf = obj.nvertices <= obj.ndims + 1;
        end

        function w = weights(obj, X)
            % weights__Barycentric coordinates of points with respect to the vertices.
            %   One row per point, one column per vertex; rows sum to one and
            %   are non-negative for points inside. For a simplex of fewer
            %   than ndims + 1 vertices the points are first projected onto
            %   the simplex's affine hull. Only defined for simplices.
            arguments
                obj
                X (:,:) double
            end
            if ~obj.isSimplex
                error("MyPareto:notSimplex", "Barycentric weights are only defined for a simplex (at most ndims + 1 vertices).");
            end
            MyPareto.checkDims(obj, X);
            V = obj.vertices;
            w = ([V'; ones(1, obj.nvertices)] \ [X'; ones(1, size(X, 1))])';
        end

        function tf = contains(obj, X)
            % contains__True for each row of X that lies inside the polytope.
            arguments
                obj
                X (:,:) double
            end
            MyPareto.checkDims(obj, X);
            tol = 1e-9 * max(range(obj.vertices), [], "all");
            tf = obj.distance(X) <= tol;
        end

        function dist = distance(obj, X)
            % distance__Distance of each row of X beyond the polytope boundary.
            %   Zero for points inside; outside, the largest distance to a
            %   facet plane. A simplex of fewer than ndims + 1 vertices is
            %   judged on the projection of the points onto its affine hull.
            arguments
                obj
                X (:,:) double
            end
            MyPareto.checkDims(obj, X);
            dist = MyPareto.violationOf(obj.vertices, X);
        end

        function [pValue, stats] = significance(obj, X, opts)
            % significance__t-ratio test of the fit against column-shuffled data (ParTI).
            %   The t-ratio is the polytope volume divided by the volume of
            %   the convex hull of the points. A pointy, polytope-like cloud
            %   gives a ratio near one. The null distribution refits the
            %   same polytope, with the same options, to data whose columns
            %   are shuffled independently, which destroys the joint shape
            %   but keeps each marginal. For the enclosing algorithms the
            %   p-value is the fraction of shuffles with a ratio at least as
            %   small as observed; for the inscribed ones (pcha, sdvmm) at
            %   least as large.
            %
            %   X must be the data the object was fitted to.
            %
            %   Options
            %       Shuffles (double, default 1000): Number of shuffles.
            %       Seed     (double, default []): rng seed; state is restored.
            %       Verbose  (logical, default true): Show a progress bar.
            %
            %   Outputs
            %       pValue (double): Fraction of shuffles beating the data,
            %              with a floor of 1 / Shuffles.
            %       stats  (struct): tRatio, null (Shuffles x 1), shuffles, direction.
            %
            %   Example
            %       p = MyPareto.fit(X, 3);
            %       [pValue, stats] = p.significance(X, Shuffles=1000);
            arguments
                obj
                X (:,:) double
                opts.Shuffles (1,1) double {mustBeInteger, mustBePositive} = 1000
                opts.Seed double = []
                opts.Verbose (1,1) logical = true
            end
            MyPareto.checkDims(obj, X);
            X = X(all(isfinite(X), 2), :);
            n = size(X, 1);
            if ~isempty(opts.Seed)
                previous = rng;
                restore = onCleanup(@() rng(previous)); %#ok<NASGU>
                rng(opts.Seed);
            end
            fitOptions = obj.options;
            fitOptions.Verbose = false;
            fitOptions.Seed = [];
            fitArgs = namedargs2cell(fitOptions);
            k = obj.nvertices;

            observed = obj.volume / MyPareto.hullVolume(X);
            null = nan(opts.Shuffles, 1);
            if opts.Verbose
                progress = MyProgress(opts.Shuffles, "t-ratio shuffles");
            end
            for i = 1:opts.Shuffles
                shuffled = X;
                for j = 1:size(X, 2)
                    shuffled(:, j) = X(randperm(n), j);
                end
                try
                    fit = MyPareto.fit(shuffled, k, fitArgs{:});
                    null(i) = fit.volume / MyPareto.hullVolume(shuffled);
                catch
                    % a shuffle the algorithm could not fit is left NaN
                end
                if opts.Verbose
                    progress.update();
                end
            end
            if opts.Verbose
                progress.done();
            end
            inscribed = ismember(obj.algorithm, ["pcha", "sdvmm"]);
            if inscribed
                beats = null >= observed;
            else
                beats = null <= observed;
            end
            valid = ~isnan(null);
            pValue = max(nnz(beats & valid), 1) / max(nnz(valid), 1);
            stats = struct(tRatio=observed, null=null, shuffles=opts.Shuffles, ...
                direction=string(ifelse(inscribed, "larger", "smaller")) + " ratio is more polytope-like", ...
                shufflesFailed=nnz(~valid));

            function out = ifelse(condition, a, b)
                if condition, out = a; else, out = b; end
            end
        end

        function obj = orderLike(obj, reference)
            % orderLike__Reorder the vertices to best match a reference set.
            %   Minimizes the total distance between matched vertices over
            %   all permutations; keeps vertex indices stable across fits.
            arguments
                obj
                reference (:,:) double
            end
            k = obj.nvertices;
            if ~isequal(size(reference), size(obj.vertices))
                error("MyPareto:badReference", "Reference must be %d x %d.", k, obj.ndims);
            end
            orders = perms(1:k);
            cost = arrayfun(@(i) sum(vecnorm(obj.vertices(orders(i, :), :) - reference, 2, 2)), 1:size(orders, 1));
            [~, best] = min(cost);
            obj.vertices = obj.vertices(orders(best, :), :);
        end

        function h = plot(obj, opts)
            % plot__Draw the polytope (2-D patch or 3-D hull) on the current axes.
            %
            %   Options
            %       Data      (double, default []): Points to scatter; those
            %                 outside the polytope are marked with a cross.
            %       Color     (default [0.85 0.33 0.10]): Edge and face color.
            %       FaceAlpha (double, default 0.1)
            %       LineWidth (double, default 1.5)
            %       Labels    (logical, default true): Number the vertices.
            arguments
                obj
                opts.Data (:,:) double = zeros(0, obj.ndims)
                opts.Color = [0.85 0.33 0.10]
                opts.FaceAlpha (1,1) double = 0.1
                opts.LineWidth (1,1) double = 1.5
                opts.Labels (1,1) logical = true
            end
            V = obj.vertices;
            held = ishold;
            hold on
            if ~isempty(opts.Data)
                in = obj.contains(opts.Data);
                if obj.ndims == 2
                    dots = @(D, varargin) scatter(D(:, 1), D(:, 2), varargin{:});
                else
                    dots = @(D, varargin) scatter3(D(:, 1), D(:, 2), D(:, 3), varargin{:});
                end
                dots(opts.Data(in, :), 8, [0.5 0.5 0.5], "filled");
                if any(~in)
                    dots(opts.Data(~in, :), 20, opts.Color, "x");
                end
            end
            switch obj.ndims
                case 2
                    h = patch(V(:, 1), V(:, 2), opts.Color, FaceAlpha=opts.FaceAlpha, ...
                        EdgeColor=opts.Color, LineWidth=opts.LineWidth);
                case 3
                    faces = convhulln(V);
                    h = patch(Faces=faces, Vertices=V, FaceColor=opts.Color, FaceAlpha=opts.FaceAlpha, ...
                        EdgeColor=opts.Color, LineWidth=opts.LineWidth);
                    view(3)
                otherwise
                    error("MyPareto:plotDims", "plot supports 2-D and 3-D polytopes only.");
            end
            if opts.Labels
                for i = 1:obj.nvertices
                    pos = num2cell(V(i, :));
                    text(pos{:}, "  " + i, Color=opts.Color, FontWeight="bold");
                end
            end
            if ~held
                hold off
            end
            axis equal
        end
    end

    %% ---------------------------------------------------------------- internals
    methods (Static, Access = private)
        function alg = resolveAlgorithm(alg, k, d)
            % resolveAlgorithm__Pick the algorithm for "auto" and validate k against d.
            if alg == "auto"
                if d == 2 && k == 3
                    alg = "exact";
                elseif k <= d + 1
                    alg = "sisal";
                elseif d == 2
                    alg = "cover";
                else
                    error("MyPareto:tooManyVertices", ...
                        "%d vertices in %d-D: only a simplex (up to %d vertices) can be fitted; use Algorithm=""pcha"".", k, d, d + 1);
                end
            end
            switch alg
                case "exact"
                    if d ~= 2 || k ~= 3
                        error("MyPareto:exact", "Algorithm ""exact"" fits a triangle to 2-D data only.");
                    end
                case "cover"
                    if d ~= 2 || k < 3
                        error("MyPareto:cover", "Algorithm ""cover"" fits a k-gon (k >= 3) to 2-D data only.");
                    end
                case {"sisal", "mvsa", "mves", "sdvmm"}
                    if k > d + 1
                        error("MyPareto:tooManyVertices", ...
                            "Algorithm ""%s"" fits at most %d vertices to %d-D data; use ""cover"" (2-D) or ""pcha"".", alg, d + 1, d);
                    end
                    if k < 2 || (k < 3 && ismember(alg, ["mves", "sdvmm"]))
                        error("MyPareto:tooFewVertices", "Algorithm ""%s"" needs at least %d vertices.", alg, 2 + ismember(alg, ["mves", "sdvmm"]));
                    end
                    MyPareto.ensurePath();
                    if alg == "mves" && exist("adendotd", "file") ~= 3
                        error("MyPareto:sedumi", "Algorithm ""mves"" needs SeDuMi with binaries built for this platform (run install_sedumi in _external/ParTI/SeDuMi_1_3).");
                    end
                case "pcha"
                    MyPareto.ensurePath();
            end
        end

        function V = fitOnce(X, k, alg, opts)
            % fitOnce__Fit the vertices with one algorithm, keeping the best restart.
            switch alg
                case "exact"
                    V = MyPareto.minEnclosingTriangle(X);
                case "cover"
                    V = MyPareto.minCoverPolygon(X, k, opts.Coverage, opts.Restarts);
                case "hull"
                    V = X(unique(convhulln(X)), :);
                otherwise
                    if ismember(alg, ["sisal", "mvsa", "pcha"])
                        restarts = opts.Restarts;
                    else
                        restarts = 1;   % deterministic
                    end
                    V = [];
                    bestScore = inf;
                    for r = 1:restarts
                        [candidate, score] = MyPareto.runParTI(X, k, alg, opts);
                        if isempty(candidate) || ~all(isfinite(candidate), "all") || ~isfinite(score)
                            continue
                        end
                        if score < bestScore
                            bestScore = score;
                            V = candidate;
                        end
                    end
                    if isempty(V)
                        error("MyPareto:failed", "Algorithm ""%s"" did not return a valid simplex in %d restarts.", alg, restarts);
                    end
            end
        end

        function [V, score] = runParTI(X, k, alg, opts)
            % runParTI__One call of a ParTI algorithm; score is lower for better fits.
            [n, d] = size(X);
            Y = X';
            switch alg
                case {"sisal", "mvsa"}
                    if k == d + 1
                        Y = [Y; ones(1, n)];   % embed so the data span a k-1 affine subspace of k-D
                    end
                    if alg == "sisal"
                        [~, M] = evalc('sisal(Y, k, "VERBOSE", 0, "TAU", opts.Tau)');
                    else
                        [~, M] = evalc('mvsa(Y, k, "verbose", 0)');   % VCA inside prints regardless
                    end
                    if isscalar(M)
                        V = [];
                        score = inf;
                        return
                    end
                    V = M(1:d, :)';
                    score = MyPareto.volumeOf(V);
                case "mves"
                    A = MVES(Y, k, 0);
                    V = A';
                    score = MyPareto.volumeOf(V);
                case "sdvmm"
                    A = SDVMM(Y, k, opts.BackOff);
                    V = A';
                    score = -MyPareto.volumeOf(V);   % inscribed: larger is better
                case "pcha"
                    [XC, ~, ~, ~, varexpl] = PCHA1(Y, k, 1:n, 1:n, opts.Delta);
                    V = full(XC)';
                    score = -varexpl;
            end
        end

        function ensurePath()
            % ensurePath__Add the ParTI algorithm folders under _external to the path.
            if exist("sisal", "file") == 2 && exist("PCHA1", "file") == 2
                return
            end
            root = fullfile(fileparts(fileparts(mfilename("fullpath"))), "_external", "ParTI");
            if ~isfolder(root)
                error("MyPareto:noParTI", "ParTI not found at %s (clone it with _external/ParTI.sh).", root);
            end
            for sub = ["sisal_demo", "mvsa_demo", "MVES_code", "ADVMM_and_SDVMM_codes", "PCHA", "SeDuMi_1_3"]
                addpath(fullfile(root, sub), "-end");
            end
        end

        function checkDims(obj, X)
            if size(X, 2) ~= obj.ndims
                error("MyPareto:dims", "Points must have %d columns.", obj.ndims);
            end
        end

        function V = orderVertices(V)
            % orderVertices__Counterclockwise about the centroid in 2-D, else by first coordinate.
            if size(V, 2) == 2
                c = mean(V, 1);
                [~, order] = sort(atan2(V(:, 2) - c(2), V(:, 1) - c(1)));
            else
                [~, order] = sortrows(V);
            end
            V = V(order, :);
        end

        function vol = hullVolume(X)
            % hullVolume__Volume (area in 2-D) of the convex hull of the points.
            [~, vol] = convhulln(X);
        end

        function vol = volumeOf(V)
            % volumeOf__Volume of the polytope within its own affine hull.
            [k, d] = size(V);
            if k <= d + 1
                E = V(2:end, :) - V(1, :);
                vol = sqrt(abs(det(E * E'))) / factorial(k - 1);
            else
                [~, vol] = convhulln(V);
            end
        end

        function viol = violationOf(V, X)
            % violationOf__Distance of each row of X beyond the polytope; zero inside, NaN for NaN rows.
            %   A simplex of fewer than ndims + 1 vertices is judged on the
            %   projection of the points onto its affine hull.
            [k, d] = size(V);
            viol = nan(size(X, 1), 1);
            valid = all(isfinite(X), 2);
            X = X(valid, :);
            if k >= d + 1
                [A, b] = MyPareto.halfspaces(V);
                v = max(X * A' - b', [], 2);
            else
                % Lower-dimensional simplex: project onto its affine hull.
                E = V(2:end, :) - V(1, :);
                [Q, ~] = qr(E', "econ");
                P = (X - V(1, :)) * Q;
                [A, b] = MyPareto.halfspaces((V - V(1, :)) * Q);
                v = max(P * A' - b', [], 2);
            end
            viol(valid) = max(v, 0);
        end

        function [A, b] = halfspaces(V)
            % halfspaces__Facet normals (unit rows of A) and offsets b with inside <=> A*x <= b.
            [k, m] = size(V);
            if m == 1
                A = [-1; 1];
                b = [-min(V); max(V)];
                return
            end
            if k == m + 1
                facets = nchoosek(1:k, m);
            else
                facets = convhulln(V);
            end
            centroid = mean(V, 1);
            A = zeros(size(facets, 1), m);
            b = zeros(size(facets, 1), 1);
            for i = 1:size(facets, 1)
                P = V(facets(i, :), :);
                normal = null(P(2:end, :) - P(1, :));
                normal = normal(:, 1)';
                if (centroid - P(1, :)) * normal' > 0
                    normal = -normal;
                end
                A(i, :) = normal;
                b(i) = P(1, :) * normal';
            end
        end
    end

    %% ---------------------------------------------------------------- geometry
    methods (Static)
        function keep = peelHull(X, nOut)
            % peelHull__Logical mask that drops the nOut most extreme points of X.
            %   Greedily removes, one at a time, the convex-hull vertex whose
            %   removal shrinks the hull volume the most. Deterministic and
            %   independent of the polytope algorithm, so it serves as the
            %   outlier tolerance of MyPareto.fit.
            %
            %   Example
            %       keep = MyPareto.peelHull(X, round(0.05 * height(X)));
            arguments
                X (:,:) double {mustBeFinite}
                nOut (1,1) double {mustBeInteger, mustBeNonnegative}
            end
            [n, d] = size(X);
            keep = true(n, 1);
            for i = 1:nOut
                idx = find(keep);
                if numel(idx) <= d + 1
                    break
                end
                [facets, volume] = convhulln(X(idx, :));
                bestGain = -inf;
                for j = unique(facets(:))'
                    trial = idx;
                    trial(j) = [];
                    [~, trialVolume] = convhulln(X(trial, :));
                    if volume - trialVolume > bestGain
                        bestGain = volume - trialVolume;
                        pick = idx(j);
                    end
                end
                keep(pick) = false;
            end
        end

        function [vertices, area] = minEnclosingTriangle(points, opts)
            % minEnclosingTriangle__Smallest-area triangle enclosing a 2-D point set.
            %   A minimal enclosing triangle has one side flush with an edge
            %   of the convex hull (Klee & Laskowski 1985), so each hull edge
            %   is tried as one side; the other two sides are supporting
            %   lines whose angles are searched on a grid and then refined
            %   with fminsearch.
            %
            %   Options
            %       Resolution (double, default 360): Grid points per full turn for the two free sides.
            arguments
                points (:,2) double
                opts.Resolution (1,1) double = 360
            end
            k = convhull(points(:, 1), points(:, 2));
            hull = points(k(1:end-1), :);
            edges = circshift(hull, -1) - hull;
            flushAngles = unique(mod(atan2(-edges(:, 1), edges(:, 2)), 2 * pi));   % outward normals of a counterclockwise hull
            support = @(t) max(hull * [cos(t(:)'); sin(t(:)')], [], 1)';
            grid = 2 * pi * (0:opts.Resolution - 1)' / opts.Resolution;
            [b, c] = ndgrid(grid, grid);
            keep = b < c;
            b = b(keep);
            c = c(keep);
            hb = support(b);
            hc = support(c);
            area = inf;
            for a = flushAngles'
                [value, idx] = min(MyPareto.triangleArea(a, b, c, support(a), hb, hc));
                if value < area * 1.05
                    objective = @(t) MyPareto.triangleArea(a, t(1), t(2), support(a), support(t(1)), support(t(2)));
                    [t, value] = fminsearch(objective, [b(idx), c(idx)], ...
                        optimset(TolX=1e-10, TolFun=1e-12, MaxFunEvals=5000, MaxIter=5000, Display="off"));
                    if value < area
                        area = value;
                        angles = [a, t];
                    end
                end
            end
            h = support(angles);
            [x, y] = MyPareto.lineIntersection(angles([1 2 3]), angles([2 3 1]), h([1 2 3])', h([2 3 1])');
            vertices = [x(:), y(:)];
        end

        function [vertices, info] = minCoverPolygon(X, k, coverage, nStarts)
            % minCoverPolygon__Approximate minimum-area convex k-gon covering a fraction of 2-D points.
            %
            %   [V, INFO] = minCoverPolygon(X, K)
            %   [V, INFO] = minCoverPolygon(X, K, COVERAGE, NSTARTS)
            %
            %   X        : N-by-2 matrix of point coordinates.
            %   K        : number of polygon sides (integer >= 3).
            %   COVERAGE : required fraction of points inside (default 0.95).
            %   NSTARTS  : number of starting configurations (default 8).
            %
            %   V        : K-by-2 vertices in counterclockwise order.
            %   INFO     : structure with area, coverage, point membership, etc.
            %
            %   Uses only base MATLAB (fminsearch). This is a nonconvex optimization:
            %   multiple starts improve the answer but do not guarantee a global optimum.
            arguments
                X (:,2) double {mustBeFinite, mustBeNonempty}
                k (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(k, 3)}
                coverage (1,1) double {mustBeInRange(coverage, 0, 1, "exclude-lower")} = 0.95
                nStarts (1,1) double {mustBeInteger, mustBePositive} = 8
            end

            n = size(X,1);
            m = ceil(coverage*n);
            if m < 3 || rank(bsxfun(@minus,X,mean(X,1))) < 2
                error('Need at least three target points and noncollinear 2-D data.');
            end

            % Translate and isotropically scale. Isotropic scaling preserves
            % relative polygon areas and helps fminsearch numerically.
            origin = median(X,1);
            radii = sqrt(sum(bsxfun(@minus,X,origin).^2,2));
            unit = median(radii);
            if unit <= 0, unit = max(radii); end
            Y = bsxfun(@rdivide,bsxfun(@minus,X,origin),unit);

            % Robust-ish starting ellipse, using the central 90% of points.
            [~,order] = sort(sum(Y.^2,2));
            core = Y(order(1:max(3,ceil(0.90*n))),:);
            Sigma = cov(core) + 1e-3*eye(2);

            bestArea = inf;
            best = struct();
            d = 2*k+1;
            options = optimset('Display','off', ...
                'MaxIter',200*d,'MaxFunEvals',300*d, ...
                'TolX',1e-5,'TolFun',1e-7);

            for r = 1:nStarts
                % Parameter vector:
                %   z(1:2)     = center
                %   z(3)       = rotation of first outward normal
                %   z(4:k+2)   = relative logarithmic support distances
                %   z(k+3:end) = logits for angular gaps between edge normals
                z = zeros(d,1);
                z(3) = 2*pi*(r-1)/(k*nStarts);
                if r > 1
                    j = (1:k-1)';
                    z(k+3:end) = 0.08*sin(1.1*j*r);
                end

                gaps = gapsFromLogits(z(k+3:end));
                angles = z(3) + [0; cumsum(gaps(1:end-1))];
                normals = [cos(angles),sin(angles)];
                support = sqrt(sum((normals*Sigma).*normals,2)) + 0.03;
                z(4:k+2) = log(support(1:end-1)) - log(support(end));

                objective(z);  % Record feasible initial candidate.
                fminsearch(@objective,z,options);
            end

            if ~isfinite(bestArea)
                error('Optimization did not find a valid polygon. Increase nStarts.');
            end

            % Tiny inflation protects inclusion of boundary points from roundoff.
            t = best.scaleFactor * (1 + 1e-10) + 1e-12;
            V = bsxfun(@plus,t*best.baseVertices,best.center);
            vertices = bsxfun(@plus,unit*V,origin);
            scores = max(bsxfun(@rdivide, ...
                bsxfun(@minus,Y,best.center)*best.normals',best.offsets'),[],2);
            inside = scores <= t + 1e-11;

            info.area = polyarea(vertices(:,1),vertices(:,2));
            info.coverage = sum(inside)/n;
            info.nInside = sum(inside);
            info.inside = inside;
            info.coverageRequested = coverage;
            info.nSides = k;
            info.nStarts = nStarts;
            info.center = origin + unit*best.center;
            info.edgeNormals = best.normals;
            info.edgeDistances = unit*t*best.offsets;

            % Nested objective remembers the best geometrically valid candidate.
            function loss = objective(z)
                [loss,cand] = evaluateCandidate(z,Y,k,m);
                if cand.valid && cand.area < bestArea
                    bestArea = cand.area;
                    best = cand;
                end
            end
            function gaps = gapsFromLogits(logits)
                q = [logits(:);0];
                w = exp(q - max(q));
                gaps = (2*pi/sum(w))*w;
            end

            function [loss,cand] = evaluateCandidate(z,Y,k,m)
                cand = struct('valid',false);
                bad = 1e12;
                c = z(1:2)';

                logb = [z(4:k+2);0];
                logb = logb - mean(logb); % Remove redundant global polygon scale.
                if any(~isfinite(z)) || max(abs(logb)) > 15
                    loss = bad; return
                end
                b = exp(logb);

                gaps = gapsFromLogits(z(k+3:end));
                if any(gaps <= 1e-4) || any(gaps >= pi-1e-4)
                    loss = bad; return
                end
                theta = z(3) + [0;cumsum(gaps(1:end-1))];
                thetaNext = [theta(2:end);theta(1)+2*pi];
                bNext = b([2:end,1]);
                normals = [cos(theta),sin(theta)];

                % Vertices are intersections of successive supporting lines.
                V = [(b.*sin(thetaNext)-bNext.*sin(theta))./sin(gaps), ...
                    (bNext.*cos(theta)-b.*cos(thetaNext))./sin(gaps)];
                if any(~isfinite(V(:)))
                    loss = bad; return
                end

                % A valid K-gon has every adjacent-line intersection satisfying ALL
                % half-planes and has nonzero edge lengths.
                violation = max(0,bsxfun(@minus,V*normals',b'));
                edges = V([2:end,1],:) - V;
                lengths = sqrt(sum(edges.^2,2));
                area0 = polyarea(V(:,1),V(:,2));

                % Required scale is the M-th smallest radial half-plane score.
                scores = max(bsxfun(@rdivide, ...
                    bsxfun(@minus,Y,c)*normals',b'),[],2);
                scores = sort(scores);
                t = scores(m);
                if ~(isfinite(t) && t > 0 && isfinite(area0))
                    loss = bad; return
                end
                area = t^2*area0;

                % Penalty guides fminsearch away from redundant/invalid edges.
                penalty = 1e4*max(1,t^2) * (sum(violation(:).^2) + ...
                    sum(max(0,1e-5-lengths).^2));
                loss = area + penalty;

                cand.valid = max(violation(:)) < 1e-8 && ...
                    all(lengths > 1e-5) && area0 > 1e-9;
                if cand.valid
                    cand.area = area;
                    cand.scaleFactor = t;
                    cand.center = c;
                    cand.baseVertices = V;
                    cand.offsets = b;
                    cand.normals = normals;
                end
            end
        end

        function results = test(opts)
            % test__Fit synthetic triangle data with every available algorithm and compare.
            %   Draws points uniformly inside a known triangle, adds a few
            %   outliers, and reports area and coverage per algorithm. With
            %   Plot=true, draws the fits.
            %
            %   Options
            %       Plot (logical, default false)
            arguments
                opts.Plot (1,1) logical = false
            end
            rng(1);
            truth = [0 0; 4 1; 1 3];
            n = 300;
            w = -log(rand(n, 3));
            w = w ./ sum(w, 2);
            X = w * truth;
            outliers = truth(1, :) + [-1.5 -1; -1 -1.5; 5.5 0.5; 2 4.5; 0.5 4];
            X = [X; outliers];
            trueArea = polyarea(truth(:, 1), truth(:, 2));
            fprintf("True triangle area %.3f, %d points (%d outliers)\n", trueArea, size(X, 1), size(outliers, 1));

            cases = {
                "exact",  3, 1
                "exact",  3, 0.98
                "sisal",  3, 1
                "sisal",  3, 0.98
                "mvsa",   3, 1
                "mves",   3, 1
                "sdvmm",  3, 1
                "pcha",   3, 1
                "pcha",   5, 1
                "cover",  4, 0.98
                "hull",   0, 0.98
                };
            results = table(Size=[0 6], VariableTypes=["string", "double", "double", "double", "double", "double"], ...
                VariableNames=["algorithm", "k", "requested", "area", "coverage", "seconds"]);
            if opts.Plot
                figure(Name="MyPareto.test");
                tiledlayout("flow");
            end
            for i = 1:size(cases, 1)
                [alg, k, coverage] = cases{i, :};
                try
                    t = tic;
                    p = MyPareto.fit(X, max(k, 1), Algorithm=alg, Coverage=coverage, Seed=1);
                    results(end + 1, :) = {alg, p.nvertices, coverage, p.volume, p.coverage, toc(t)}; %#ok<AGROW>
                    if opts.Plot
                        nexttile;
                        p.plot(Data=X);
                        title(sprintf("%s k=%d area=%.2f in=%.0f%%", alg, p.nvertices, p.volume, 100 * p.coverage));
                    end
                catch err
                    fprintf("  %-6s k=%d skipped: %s\n", alg, k, err.message);
                end
            end
            disp(results);
        end
    end

    methods (Static, Access = private)
        function area = triangleArea(a, b, c, ha, hb, hc)
            % triangleArea__Area of the triangle bounded by three supporting lines (normal angle, offset); Inf when unbounded.
            sorted = sort(mod([a + 0 * b, b, c], 2 * pi), 2);
            gaps = diff([sorted, sorted(:, 1) + 2 * pi], 1, 2);
            [x1, y1] = MyPareto.lineIntersection(a, b, ha, hb);
            [x2, y2] = MyPareto.lineIntersection(b, c, hb, hc);
            [x3, y3] = MyPareto.lineIntersection(c, a, hc, ha);
            area = abs((x2 - x1) .* (y3 - y1) - (x3 - x1) .* (y2 - y1)) / 2;
            area(any(gaps >= pi - 1e-9, 2)) = inf;
        end

        function [x, y] = lineIntersection(t1, t2, h1, h2)
            % lineIntersection__Point where x*cos(t1) + y*sin(t1) = h1 meets x*cos(t2) + y*sin(t2) = h2.
            d = sin(t2 - t1);
            x = (h1 .* sin(t2) - h2 .* sin(t1)) ./ d;
            y = (h2 .* cos(t1) - h1 .* cos(t2)) ./ d;
        end
    end

    %% ---------------------------------------------------------------- legacy
    methods (Static)
        function out = findBoundingPoly2D(pts, thresh, out, opt)
            % findBoundingPoly2D__Brute-force minimal convex polygon on a grid covering a fraction of 2-D points (legacy).
            %   Prefer MyPareto.fit(pts, n, Algorithm="cover", Coverage=thresh).
            arguments
                pts
                thresh = .85
                out = []
                opt.N = 20          % resolution of grid is NxN
                opt.n = 3           % number of vertices
                opt.extend = 0.2;   % max distance of vetice from data in fraction
                opt.minThresh = .7; % min threshold
                opt.verbose = true;
            end
            N = opt.N; % resolution of grid is NxN
            n = opt.n;  % number of vertices
            extend = opt.extend;
            min_thresh = opt.minThresh;
            range = {};
            for i = 1:2
                fr = min(pts(:, i));
                to = max(pts(:, i));
                len = to - fr;
                fr = fr - extend * len;
                to = to + extend * len;
                range{i} = [fr, to];
            end
            [x, y] = meshgrid(linspace(range{1}(1), range{1}(2), N), linspace(range{2}(1), range{2}(2), N));

            if isempty(out)
                ncks{n} = nchoosek(1:length(x(:)), n);

                % Remove small areas
                if opt.verbose; fprintf('- Removing small areas...\n'); end
                t = tic;
                H = histcounts2(pts(:, 1), pts(:, 2), x(1, :), y(:, 1));
                total = nansum(H(:));
                count = -1;
                while nansum(H(:)) > total * min_thresh
                    [~, idx] = max(H(:));
                    H(idx) = nan;
                    count = count + 1;
                end
                min_area = mean(diff(x(1, :)) .* diff(y(:, 1)')) * count;
                sz = abs(polygonSize(x(ncks{n}), y(ncks{n})));
                ncks{n}(sz < min_area, :) = [];
                if opt.verbose; fprintf('  . time: %f\n', toc(t)); end
                % Remove non-convex polygons
                if opt.verbose; fprintf('- Removing non convex polygons...\n'); end
                t = tic;
                curr = ncks{n};
                ncks{n} = curr(isPolygonConvex(x(ncks{n}), y(ncks{n})), :);
                if opt.verbose; fprintf('  . time: %f\n', toc(t)); end
                % Count points inside polygon
                if opt.verbose; fprintf('- Num points in polygon...\n'); end
                t = tic;
                npoints = countPointsInPolygons(x(ncks{n}), y(ncks{n}), pts(:, 1), pts(:, 2)) / size(pts, 1);
                if opt.verbose; fprintf('  . time: %f\n', toc(t)); end
                %%
                out.perms = ncks{n};
                out.npoints = npoints;
                out.grid.x = x(1, :);
                out.grid.y = y(:, 1)';
                out.opt = opt;
            end
            %%
            assert(thresh > out.opt.minThresh);
            small_ncks = out.perms;
            small_ncks(out.npoints < thresh, :) = [];
            %
            sz = abs(polygonSize(x(small_ncks), y(small_ncks)));
            [out.size, out.idx] = min(sz);

            %%
            out.x = x(small_ncks(out.idx, :));
            out.y = y(small_ncks(out.idx, :));
            function A = polygonSize(X, Y)
                % polygonSize  Fast area-per-row for multiple 2-D polygons (shoelace; sign follows vertex order).
                if ~any(isnan(X(:))) && ~any(isnan(Y(:)))
                    Xs = X(:, [2:end, 1]);
                    Ys = Y(:, [2:end, 1]);
                    A  = 0.5 * sum( X .* Ys - Y .* Xs , 2);
                    return
                end
                n = size(X,1);
                A = zeros(n,1);
                for i = 1:n
                    xi = X(i,:);  yi = Y(i,:);
                    v  = ~isnan(xi) & ~isnan(yi);      % remove padding
                    xi = xi(v);   yi = yi(v);
                    if isempty(xi)
                        A(i) = NaN;                    % no vertices in this row
                    else
                        A(i) = polyarea(xi, yi);
                    end
                end
            end
            function isConvex = isPolygonConvex(X, Y)
                % isPolygonConvex  Convexity of many 2-D polygons (one per row), processed in chunks.
                thresh = round(sqrt(1e9));
                if size(X, 1)  > thresh
                    offset = 0;
                    isConvex = false(size(X, 1), 1);
                    idx = 1;
                    while offset < size(X, 1)
                        isConvex(offset + 1:min(offset + thresh, end)) = isPolygonConvex(X(offset + 1:min(offset + thresh, end), :), Y(offset + 1:min(offset + thresh, end), :));
                        offset = offset + thresh;
                        idx = idx + 1;
                    end
                    return
                end
                X = [X, X(:,1:2)];
                Y = [Y, Y(:,1:2)];
                dx1 = X(:,2:end-1) - X(:,1:end-2);
                dy1 = Y(:,2:end-1) - Y(:,1:end-2);
                dx2 = X(:,3:end)   - X(:,2:end-1);
                dy2 = Y(:,3:end)   - Y(:,2:end-1);
                crossZ = dx1 .* dy2 - dy1 .* dx2;  % size: M x N
                signs = sign(crossZ);
                first_sign = signs .* (signs ~= 0);  % eliminate zeros
                [~, idx] = max(abs(first_sign), [], 2);  % get position of first non-zero
                ref_sign = signs(sub2ind(size(signs), (1:size(signs,1))', idx));
                isConvex = all(signs == ref_sign, 2) | all(signs == 0, 2);  % handle all-zeros
            end
            function counts = countPointsInPolygons(X, Y, px, py)
                % countPointsInPolygons  Vectorized ray-casting count of points inside each polygon (one per row).
                [M, N] = size(X);    % M polygons with N vertices
                thresh = max(round(1e8 / length(px)), 10);
                if size(X, 1)  > thresh
                    offset = 0;
                    counts = zeros(size(X, 1), 1);
                    while offset < size(X, 1)
                        counts(offset + 1:min(offset + thresh, end)) = countPointsInPolygons(X(offset + 1:min(offset + thresh, end), :), Y(offset + 1:min(offset + thresh, end), :), px, py);
                        offset = offset + thresh;
                    end
                    return
                end
                K = numel(px);       % K points
                X = [X, X(:,1)];
                Y = [Y, Y(:,1)];
                xv1 = X(:,1:end-1); xv2 = X(:,2:end);
                yv1 = Y(:,1:end-1); yv2 = Y(:,2:end);
                xv1 = reshape(xv1, [M, 1, N]);  xv2 = reshape(xv2, [M, 1, N]);
                yv1 = reshape(yv1, [M, 1, N]);  yv2 = reshape(yv2, [M, 1, N]);
                px = reshape(px, 1, K);   % 1 × K
                py = reshape(py, 1, K);   % 1 × K
                cond1 = ( (py > min(yv1, yv2)) & (py <= max(yv1, yv2)) );
                xinters = (py - yv1) .* (xv2 - xv1) ./ (yv2 - yv1 + eps) + xv1;
                cond2 = px < xinters;
                crossings = sum(cond1 & cond2, 3);  % M × K
                inside = mod(crossings, 2) == 1;
                counts = sum(inside, 2);  % M × 1
            end
        end
    end
end
