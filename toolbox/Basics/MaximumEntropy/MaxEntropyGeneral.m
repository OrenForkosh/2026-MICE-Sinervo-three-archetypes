classdef MaxEntropyGeneral < InfoTheory
    % MaxEntropyGeneral Maximum-Entropy toolbox. 
    %
    % Based upon: 
    %   Yair Shemesh, Yehezkel Sztainberg, Oren Forkosh, Tamar Shlapobersky, 
    %   Alon Chen, and Elad Schneidman. “High-Order Social Interactions in 
    %   Groups of Mice.” ELife 2 (September 3, 2013): e00759. 
    %   https://doi.org/10.7554/eLife.00759.
    %
    methods (Static = true)
        function Compare(me1, me2)
            % Show a compariosson of two ME models using a plot-plot graph
            nbins = 10;
            order = sum(me1.Patterns~=0, 2);
            q = quantile(me1.Expected, linspace(0, 1, nbins + 1));
            [~, idx] = histc(me1.Expected(order == 2), q);
            cmap = hot(length(q));
            w1 = me1.Weights(order == 2);
            w2 = me2.Weights(order == 2);
            Plot.Equality(w1, w2, 'Marker', 'o', 'MarkerFaceColor', 'none', 'MarkerEdgeColor', 'none');
            Fig.Hon
            for i=1:length(q)
                Plot.Equality(w1(idx == i), w2(idx == i), 'Marker', 'o', 'MarkerFaceColor', cmap(length(q)-i+1, :), 'MarkerEdgeColor', 'k');
            end
            Fig.Hoff;
            Fig.Title('2nd order interactions');
        end
        
        
        function Analyze(me, ~)
            % Display data regarding ME model
            if iscell(me)
                %% connected information
                subplot(2,2,1);
                cla
                textstyle = Fig.DefaultAxesFont;
                cmap = Colormaps.Categorical;
                patch([0, 1, 1, 0], [0 0 100 100], cmap(length(me) + 1, :), 'edgecolor', 'none');
                text(1, 100, sprintf(' %.3f', me{1}.EmpMultiInfo), textstyle{:});
                for i=length(me):-1:1
                    h = me{i}.ConnInfo / me{i}.EmpMultiInfo * 100;
                    patch([0, 1, 1, 0], [0 0 h h], cmap(i, :), 'edgecolor', 'none');
                    Fig.Hon
                    plot([0 1], [h h], 'k:');
                    text(1, h, sprintf(' %.3f', me{i}.ConnInfo), textstyle{:});
                end
                Fig.YAxis(0, 100);
                Fig.XAxis(0, 1.5);
                Fig.XTick([]);
                Fig.YLabel('connected information [%%]');
                Fig.Fix;
                set(gca, 'XColor', 'w');
                Fig.Hoff;
            end
        end
        
        function DrawHinton(obj, me, varargin)
            %
            map = sum(me.Patterns ~= 0, 2) == 2;
            loc = bsxfun(@plus, me.Patterns(map, :), (0:size(me.Patterns, 2)-1) * (me.nVals));
            loc(me.Patterns(map, :) == 0) = 0;
            loc = sort(loc, 2);
            loc = loc(:, end-1:end);
            d = zeros(me.nVals * size(me.Patterns, 2));
            d(sub2ind(size(d), loc(:, 1), loc(:, 2))) = me.Weights(map);
            %d(sub2ind(size(d), loc(:, 2), loc(:, 1))) = me.Weights(map);
            d = d(1:end-me.nVals, me.nVals+1:end);
            Plot.Hinton(d)
            set(gca, 'ytick', 1:me.nVals, 'yticklabel', obj.ROI.ZoneNames);
            set(gca, 'xtick', 1:me.nVals, 'xticklabel', obj.ROI.ZoneNames, 'XAxisLocation', 'top', 'XTickLabelRotation', 45);
        end
        
        function DrawMap(me, varargin)
            %%
            opt = Q.defaultargs(false, varargin, ...
                'Colormap', Colormaps.Categorical, ...
                'Maxval', [], ...
                'Gap', 0, ...
                'CircleSize', 20, ...
                'MaxWidth', 10, ...
                'Tolerance', 0, ...
                'UseQunatile', false, ...
                'Labels', [], ...
                'Highlight', [], ...
                'LimitVal', true, ...
                'Rotation', 0 ...
                );
            %%
            expfun = @(x, a) exp(a*x) / exp(a);
            scale = @(x) expfun(x, .5);
            colorscale = @(x) expfun(x, 2);
            colorscale = @(x) x;
            %scale = @(x) x;
            %scale = @(x) exp(x);
            maxwidth = opt.MaxWidth;
            markersize = opt.CircleSize;
            %%
            dim = size(me.Patterns, 2);
            angles = [];
            l = linspace(0, 2*pi/(dim) - opt.Gap, me.nVals+1);
            l = l(1:end-1);
            for i=1:dim
                angles = [angles, l + opt.Rotation + (i-1) * (2*pi / dim) ]; %#ok<AGROW>
            end
            centers = [sin(angles)', cos(angles)'];
            
            lmap = Colormaps.BlueWhiteRed(256);
            highlightmap = Colormaps.makeColorMap(Colors.PrettyGreen,[255 255 255]/255,Colors.VitaminC,256);
            %lmap = parula(256);
            order = sum(me.Patterns ~= 0, 2);
            if opt.UseQunatile
                me.Weights(order == 2) = Q.nwarp((me.Weights(order == 2)));
            end
            
            weights = me.Weights(order == 2);
            if isempty(opt.Maxval)
                maxval = max(abs(weights));
            else
                maxval = opt.Maxval;
            end
            if opt.LimitVal
                me.Weights(me.Weights > maxval) = maxval;
                me.Weights(me.Weights < -maxval) = -maxval;
            end
            
            [~, o] = sort(abs(me.Weights));
            idx = 1;
            for i=o
                if order(i) ~= 2
                    continue;
                end
                pat = me.Patterns(i, :);
                subj = find(pat);
                fridx = (subj(1) - 1) * (me.nVals) + pat(subj(1));
                toidx = (subj(2) - 1) * (me.nVals) + pat(subj(2));
                %%
                fr = centers(fridx, :);
                to = centers(toidx, :);
                %%
                dfr = [sin(atan2(fr(1),fr(2)))/4, cos(atan2(fr(1),fr(2)))/4];
                dto = [sin(atan2(to(1),to(2)))/4, cos(atan2(to(1),to(2)))/4];
                Q = Shapes.Bezier(fr, fr - dfr, to - dto, to);
                %%
                w = me.Weights(i) / maxval;
                s  = sign(w) * scale(abs(w));
                cs = sign(w) * colorscale(abs(w));
                currmap = lmap;
                if length(opt.Highlight) > i && opt.Highlight(i)
                    currmap = highlightmap;
                end
                if s ~= 0
                    plot(Q(:, 1), Q(:, 2), '-', 'Color', currmap(round(128-min(max(cs, -1), 1)*127), :), 'LineWidth',  abs(s) * maxwidth);
                end
                Fig.Hon
                idx = idx + 1;
            end
            for i=1:dim
                for j=1:me.nVals
                    idx = (i - 1) * (me.nVals) + j;
                    plot(centers(idx, 1), centers(idx, 2), 'o', 'MarkerEdgeColor', 'none', 'MarkerFaceColor', opt.Colormap(i, :), 'MarkerSize', markersize);
                    text(centers(idx, 1), centers(idx, 2), num2str(j), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'color', 'w', 'fontsize', markersize * 3/4, 'Rotation', -angles(idx) / pi * 180);
                    if ~isempty(opt.Labels)
                        currangle = 90 - angles(idx) / pi * 180;
                        style = {'VerticalAlignment', 'middle', 'color', 'k', 'fontsize', markersize * 3/4, 'Color', opt.Colormap(i, :)};
                        if abs(currangle) > 90
                            text(centers(idx, 1)*1.1, centers(idx, 2)*1.1, opt.Labels{j}, 'HorizontalAlignment', 'right', 'Rotation', currangle + 180, style{:});
                        else
                            text(centers(idx, 1)*1.1, centers(idx, 2)*1.1, opt.Labels{j}, 'HorizontalAlignment', 'left', 'Rotation', currangle, style{:});
                        end
                    end
                end
            end
            Fig.Hoff;
            axis off;
            axis equal
            Fig.Fix;
            
        end
        
        function DrawMapOld(me)
            %%
            maxwidth = 10;
            radiusfactor = 1;
            scale = @(x) exp(4*x);
            %
            dim = size(me.Patterns, 2);
            pat = me.Patterns;
            pat = pat(sum(pat, 2) > 0, :);
            order = sum(pat, 2);
            centers = [sin(linspace(0, 2*pi, dim+1))', cos(linspace(0, 2*pi, dim+1))'];
            cmap = [Colormaps.SubCategorical; Colormaps.SubCategorical];
            lmap = Colormaps.BlueWhiteRed(256);
            maxval = max(abs(me.Weights(order == 2)));
            
            [weights, idx] = sort(abs(me.Weights));
            
            for k=idx
                if sum(pat(k, :) ~= 0) ~= 2
                    continue
                end
                ij = find(pat(k, :));
                i = ij(1); j = ij(2);
                fr = centers(i, :);
                to = centers(j, :);
                dfr = [sin(atan2(fr(1),fr(2)))/4, cos(atan2(fr(1),fr(2)))/4];
                dto = [sin(atan2(to(1),to(2)))/4, cos(atan2(to(1),to(2)))/4];
                Q = Shapes.Bezier(fr, fr - dfr, to - dto, to);
                w = me.Weights(k) / maxval;
                s = sign(w) * scale(w) / scale(1);
                plot(Q(:, 1), Q(:, 2), '-', 'Color', lmap(round(128-s*127), :), 'LineWidth',  abs(s) * maxwidth);
                Fig.Hon;
                
            end
            
            for i=1:dim
                Shapes.Circle(centers(i, 1), centers(i, 2), 1/dim*radiusfactor, cmap(i, :), 'EdgeColor', 'none')
                Shapes.Text(centers(i, 1), centers(i, 2), num2str(i), 'w')
            end
            axis off;
            axis equal
            Fig.Fix;
            Fig.Hoff;
        end
        
        function ProbProb(p_emp, p, varargin)
            opt.AddInfoToPlot = false;
            %%
            count = 0;
            perms = [];
            style = {};
            if nargin == 1
                me = p_emp;
                p_emp = me.EmpJointProbs;
                p = me.JointProbs;
                count = me.nSamples;
            else
                i = 1;
                while i<=length(varargin)
                    if isscalar(varargin{i})
                        count = varargin{i};
                    elseif ischar(varargin{i})
                        style{end+1} = varargin{i};
                        i = i + 1;
                        style{end+1} = varargin{i};
                    else
                        perms = varargin{i};
                    end
                    i = i + 1;
                end
            end
            
            
            %%            
            u1 = log10(p_emp(:));
            u2 = log10(p(:));
            %%
            a = zeros(1, 4);
            a([1 3]) = min(u1(isfinite(u1)));
            if count > 0
                l = sequence(a(1), a(2), 100);
                r = 10.^l * count;
                [www, p] = binofit(r(r <= count), count);
                p1 = log10(p(:, 1));
                p2 = log10(p(:, 2));
                p1(~isfinite(p1) | p1 < a(3)-1) = a(3)-1;
                fill([l, flipdim(l, 2)], [p1', flipdim(p2', 2)], [.8 .8 .8], 'LineStyle', 'none');
                Fig.Hon
            end
            
            if isempty(perms)
                plot(u1, u2, '.', 'color', Colors.Blue, style{:});
            else
                dim = size(perms, 2);
                color = Colormaps.UglyBlueRed(dim);
                for o=1:dim
                    map = sum(perms, 2) == o;
                    plot(u1(map), u2(map), '.', 'color', color(o, :), style{:});
                    hold on
                end
                h = colorbar;
                colormap(color)
                set(h, 'YTick', 1.5:dim+.5);
                set(h, 'YTickLabel', 1:dim);
            end
            hold off
            axis equal
            axis square
            hold on
            axis(a);
            plot([min(a(1), a(3)) min(a(2), a(4))], [min(a(1), a(3)) min(a(2), a(4))], 'k-', 'HandleVisibility', 'off');
            hold off
            if opt.AddInfoToPlot
                dcm_obj = datacursormode(gcf);
                set(dcm_obj,'UpdateFcn',@myupdatefcn)
            end
            Fig.Labels('observed probability', 'model');
            Fig.Fix
        end
        
        function P = JointProbs(me)
            dim = size(me.Patterns, 2);
            perms = InfoTheory.Dec2Base(0:me.nVals^dim-1, dim, me.nVals);
            feats = sparse(MaxEntropyGeneral.ToFeatures(perms, me.Patterns, me.nVals));
            p = exp(feats * me.Weights');
            p = p / sum(p);
            P = zeros(ones(1, dim) * me.nVals);
            dimsub = cell(1, dim);
            for i=1:dim
                dimsub{i} = perms(:, i) + 1;
            end
            P(sub2ind(size(P), dimsub{:})) = p;
        end
        
        function res = FitData(me, data)
            %%
            [ndata, dim] = size(data);
            %             perms = (dec2bin(0:2^dim-1) - '0')';
            %             allfeats = bsxfun(@eq, perms' * me.Patterns, sum(me.Patterns, 1));
            %             p = exp(allfeats * me.Weights);
            
            p_emp = histc(2.^(dim-1:-1:0) * data', 0:2^dim-1);
            p_emp = p_emp / sum(p_emp);
            
            res = InfoTheory.KullbackLiebler(p_emp(:), me.JointProbs);
        end
        
        function sim = Simulate(me, N)
            dim = size(me.Patterns, 2);
            perms = InfoTheory.Dec2Base(0:me.nVals^dim-1, dim, me.nVals);
            p = cumsum(me.JointProbs);
            r = rand(1, N);
            sim = zeros(N, dim);
            for i=1:N
                idx = find(r(i) < p, 1);
                sim(i, :) = perms(idx, :);
            end
        end
        
        function txt = myupdatefcn(empt, event_obj)
            pos = get(event_obj,'Position');
            idx = find(u1 == pos(1) & u2 == pos(2));
            if ~isempty(idx)
                txt = [sprintf('(p=%.4f)', p_emp(idx))];
            end
        end
        
        function me = FillModel(data, me)
            if isa(data, 'logical')
                data = double(data);
            end
            
            me.nSamples = size(data, 1);
            me.nVariables = size(data, 2);
            
            me.EmpIndepProbs = InfoTheory.IndepProbsVec(data, 0:me.nVals-1);
            me.EmpJointProbs = InfoTheory.JointProbsVec(data, 0:me.nVals-1);
            me.EmpEntropy = InfoTheory.EmpiricalEntropy(data, 0:me.nVals-1);
            me.EmpIndepEntropy = InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:me.nVals-1));
            me.EmpMultiInfo = sum(me.EmpIndepEntropy) - me.EmpEntropy;
       
            try 
                me.JointProbs = exp(MaxEntropyGeneralEnergy(me.nVals, me.Patterns, me.Weights)); %exp(feats * me.Weights');
            catch
                perms = InfoTheory.Dec2Base(0:me.nVals^me.nVariables-1, me.nVariables, me.nVals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, me.Patterns, me.nVals);
                me.JointProbs = exp(feats * me.Weights');
            end
            me.JointProbs = me.JointProbs / sum(me.JointProbs);
            me.Entropy = InfoTheory.Entropy(me.JointProbs);
            
            me.KL = InfoTheory.KullbackLiebler(me.EmpJointProbs, me.JointProbs);
            me.ConnInfo = sum(me.EmpIndepEntropy) - me.Entropy;
        end
        
        function me = InitModel(data, patterns, nvals, opt)
            Console.Message('initializing weights');
            if nargin < 4
                opt = struct();
            end
            opt = Q.defaultargs(opt, 'RandomInitalize', true);
            if opt.RandomInitalize
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
            else
                if ~exist('orig', 'var')
                    orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
                end
            end
            me = orig;
        end
        
        function me = TrainGradientDescent(data, varargin)
            % trains a Maximum entropy model using gradient-descent
            %   TrainGradientDescent(data, patterns) trains the model
            %       with the specified patterns
            %   TrainGradientDescent(data, order, nvals) trains the model
            %       with the specified order
            maxiters = 15000;
            %maxiters = 100;
            trainrate = 1;
            KLthresh = 1e-7;
            maxsearchiters = 25;
            convergeRepeats = 10;
            %wolfc1 = 1e-1;
            %wolfc2 = .9;
            useNesterov = true;
            usemex = true;
            opt.RandomInitalize = true;
            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(varargin)
                order = 2;
                nvals = max(data(:))+1;
            elseif length(varargin) == 1
                if isstruct(varargin{1})
                    orig = varargin{1};
                    patterns = orig.Patterns;
                    nvals = orig.nVals;
                elseif isscalar(varargin{1})
                    order = varargin{1};
                    nvals = max(data(:))+1;
                else
                    patterns = varargin{1};
                    order = nan;
                end
            else
                if isscalar(varargin{1})
                    order = varargin{1};
                else
                    patterns = varargin{1};
                end
                nvals = varargin{2};
            end
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            orig = MaxEntropyGeneral.InitModel(data, patterns, nvals, opt);
            me = orig;
            me.Momentum = me.Weights;
            %%
            if usemex
                Console.Message(1, 'using mex code to save memory');
                [u, ~, ic] = unique(data * (nvals.^(dim-1:-1:0))');
                ud = InfoTheory.Dec2Base(u, dim, nvals);
                expected = MaxEntropyGeneralNormalizedExpectation(ud, patterns, histc(ic, 1:length(u)));
                u = []; ud = []; ic = []; %#ok<NASGU>
            else
                Console.Message(1, 'using native matlab code');
                expected = mean(MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals), 1);
                %%
                perms = InfoTheory.Dec2Base(0:nvals^dim-1, dim, nvals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, patterns, nvals);
            end
            %%
            empprob = InfoTheory.JointProbsVec(data, 0:nvals-1);
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            %%
            History = struct('Weights', {}, 'Momentum', {}, 'KL', {}, 'tr', {});
            
            %%
            prevKL = inf;
            nConverge = 0;
            tr = trainrate;
            iter = 1;
            tic;
            while iter < maxiters
                if usemex
                    p = exp(MaxEntropyGeneralEnergy(nvals, patterns, me.Weights));
                else
                    p = exp(feats * me.Weights');
                end
                p = p / sum(p);
                %%
                KL = MaxEntropyGeneral.KullbackLiebler(empprob, p);
                if prevKL - KL  < KLthresh
                    nConverge = nConverge + 1;
                    if nConverge >= convergeRepeats
                        break;
                    end
                end
                prevKL = KL;
                %%
                tr = trainrate;
                if usemex
                    dw = (expected - MaxEntropyGeneralWeightedExpectation(nvals, patterns, p));
                else
                    dw = (expected - p' * feats);
                end
                pm = me.Momentum;
                for searchiter = 1:maxsearchiters
                    if useNesterov
                        m = me.Weights + tr * dw;
                        w = m + (iter-1)/(iter+2)*(m - pm);
                    else
                        w = me.Weights + tr * dw;
                    end
                    if usemex
                        p = exp(MaxEntropyGeneralEnergy(nvals, patterns, w));
                    else
                        p = exp(feats * w');
                    end
                    p = p / sum(p);
                    tKL = MaxEntropyGeneral.KullbackLiebler(empprob, p);
                    %currdw = (expected - p' * feats);
                    if tKL <= KL %+ wolfc1 * tr * (dw * dw') && ...
                        %abs(currdw * dw') <= wolfc2 * abs(dw * dw');
                        break
                    end
                    tr = tr / 10;
                end
                if searchiter >= maxsearchiters && useNesterov
                    useNesterov = false;
                    [~, bestiter] = min([History.KL]);
                    iter = bestiter - 1;
                    me.Weights = History(iter).Weights;
                    me.Momentum = History(iter).Momentum;
                    tr = me.History(iter).tr/10;
                    KL = me.History(iter).KL;
                    continue;
                end
                if useNesterov
                    me.Momentum = m;
                end
                me.Weights = w;
                H = InfoTheory.Entropy(p);
                %%
                if useNesterov
                    fprintf('# iter %4d - Nesterov: KL=%3.5f, H=%.3f, tr=%g\n', iter, KL, H, tr);
                else
                    fprintf('# iter %4d - GD:       KL=%3.5f, H=%.3f, tr=%g\n', iter, KL, H, tr);
                end
                %%
                History(iter) = struct('Weights', me.Weights, 'Momentum', me.Momentum, 'KL', KL, 'tr', tr);
                %%
                iter = iter + 1;
            end
            toc
            fprintf('# iter %4d: KL=%f, H=%f/%f (%.2f%%)\n', iter, KL, indepEntropy-H, multiInfo, (indepEntropy-H)/multiInfo*100);
            %%
            me.Weights = gather(me.Weights);
            me.Momentum = gather(me.Momentum);
            %%
            me.Patterns = patterns;
            me.Expected = expected;
            me.nVals = nvals;
            me.KL = [History.KL];
%            me = MaxEntropyGeneral.FillModel(data, me, nvals);
            %%
            if false
                MaxEntropyGeneral.ProbProb(me.EmpObservedProbs, me.JointProbs(me.EmpObservedMap), perms(me.EmpObservedMap, :));
                title({sprintf('RI - %d patterns', me.nPatterns), sprintf('(KL = %.3f)', me.KL)});
            end
        end

        function me = TrainOnline(data, varargin)
            %%
            dim = size(data, 2); % dimension of samples
            % generate matrix of all the features (in this case, of max order 2)
            feats = MaxEntropyGeneral.GeneratePatterns(dim, 2, 2); 
            nonzero = sum(feats, 2); % number of non-zero units of each feature
            map = Q.padright(bsxfun(@eq, data * feats', nonzero'), 1, 1);
            % compute constraints - the expected value of the feats
            const = mean(map);
            % generate matrix containing all possible inputs
            perms = InfoTheory.Dec2Base(0:2^dim-1, dim, 2);
            % compute the features for each row in perms
            permmap = Q.padright(bsxfun(@eq, perms * feats', nonzero'), 1, 1);
            % initialize max-ent model
            me = randn(1, size(const, 2));
            alpha = 1/size(data, 1);
            for iter = 1:1000
                for i=101:size(data, 1)
                    idx = randi(size(perms, 1));
                    %ep = exp(permmap(idx, :) * me') * permmap(idx, :);
                    ep = exp(map(i-1, :) * me') * map(i-100, :);
                    %ep = exp(map(i, :) * me') * map(i, :);
                    dme = (map(i, :) - ep);
                    %dme(end) = dme(end) / size(permmap, 1);
                    %dme(end) = sign(dme(end)) * min(max(abs(dme(1:end-1))), abs(dme(end)));
                    dme(end) = sign(dme(end)) * min(sum(abs(dme(1:end-1))), abs(dme(end)));
                    %dme(end) = +sum(ep(1:end-1));
                    me = me + alpha * dme;
                end
                fprintf('half DKL = %f (%f)\n', mean(map * me'), sum(exp(permmap * me')));
            end
            
               %%
            dim = size(data, 2); % dimension of samples
            % generate matrix of all the features (in this case, of max order 2)
            feats = MaxEntropyGeneral.GeneratePatterns(dim, 2, 2); 
            nonzero = sum(feats, 2); % number of non-zero units of each feature
            map = Q.padright(bsxfun(@eq, data * feats', nonzero'), 1, 1);
            % compute constraints - the expected value of the feats
            const = mean(map);
            % generate matrix containing all possible inputs
            perms = InfoTheory.Dec2Base(0:2^dim-1, dim, 2);
            % compute the features for each row in perms
            permmap = Q.padright(bsxfun(@eq, perms * feats', nonzero'), 1, 1);
            % initialize max-ent model
            me = randn(1, size(const, 2));
                    me(end) = -log(sum(exp(permmap(:, 1:end-1) * me(1:end-1)')));
            alpha = 1; %1/size(data, 1);
            map = map(randperm(size(map, 1)), :);
            for iter = 1:1000
                for i=2:size(data, 1)
                    idx = randi(size(perms, 1));
                    ep = exp(permmap(idx, :) * me') * permmap(idx, :);
                    dme = (map(i, :) - map(i-1, :));
                    %dme(end) = dme(end) / size(permmap, 1);
                    me = me + alpha * dme;
                end
                fprintf('half DKL = %f (%f)\n', mean(map * me'), sum(exp(permmap * me')));
            end
        end

        function me = SimpleTrain(data, varargin)
            %% WARNING!!! Work in progress
              
            %% The shortes, and simplest ME algorithm
            dim = size(data, 2); % dimension of samples
            % generate matrix of all the features (in this case, of max order 2)
            feats = MaxEntropyGeneral.GeneratePatterns(dim, 2, 2); 
            nonzero = sum(feats, 2); % number of non-zero units of each feature
            map = Q.padright(bsxfun(@eq, data * feats', nonzero'), 1, 1);
            % compute constraints - the expected value of the feats
            const = mean(map);
            % generate matrix containing all possible inputs
            perms = InfoTheory.Dec2Base(0:2^dim-1, dim, 2);
            % compute the features for each row in perms
            permmap = Q.padright(bsxfun(@eq, perms * feats', nonzero'), 1, 1);
            % initialize max-ent model
            me = randn(1, size(const, 2));
            alpha = .1;
            for iter = 1:1000
                ep = sum(bsxfun(@times, exp(permmap * me'), permmap));
                dme = (const - ep);
                dme(end) = dme(end) / size(permmap, 1);
                me = me + alpha * dme;
                me(end) = -log(sum(exp(permmap(:, 1:end-1) * me(1:end-1)')));
                fprintf('half DKL = %f (%f)\n', mean(map * me'), sum(exp(permmap * me')));
            end
        end

        function [me, mes, ref] = RegularizedPrefix(data, varargin)
            % trains a Maximum entropy model using LBFGS
            % based on: Nocedal, Jorge, and Stephen J. Wright. Conjugate gradient methods. Springer New York, 2006.
            %   TrainLBFGS(data, patterns) trains the model with the specified patterns
            %   TrainLBFGS(data, order, nvals) trains the model with the specified order
            %wolfc1 = 1e-1;
            %wolfc2 = .9;
            opt = Q.defaultargs(struct(varargin{find(cellfun(@ischar, varargin)):end}), ...
                'Verbose', true, ...
                'ElasticBalance', 1, ... %% Scalar value from 0 to 1 (excluding 0) representing the weight of lasso (L1) versus ridge (L2) optimization. Alpha = 1 represents lasso regression, Alpha close to 0 approaches ridge regression
                'ElasticWeight', 0, ... %% 0 no regularization
                'TrainTypes', 1:4, ...
                'LBFGSMemoryLength', 15, ...
                'MaxIters', 15000,...
                'InitialTrainRate', 1,...
                'MinRepeatsToConverge', 10, ...
                'MaxLineSearchBacktracks', 25,...
                'KLThresh', 1e-7, ...
                'UseMEX', true, ...
                'Output', true, ...
                'Weights', [], ...
                'Tolerence', 0.05, ...
                'Method', 'subgradient', ... %% 'subgradient' or 'ista'
                'TrainMap', [], ... % if set, divides data to train and test sets to choose best model
                'MemoryAware', true);
            args = varargin;
            varargin(find(cellfun(@ischar, varargin)):end) = [];
            %%
            ref = [];
            if length(opt.ElasticBalance) > 1 || length(opt.ElasticWeight) > 1
                if isempty(opt.TrainMap)
                    map = true(size(data, 2), 1);
                else
                    map = opt.TrainMap(:);
                end
                mes={};
                for idx1 = 1:length(opt.ElasticBalance)
                    eb = opt.ElasticBalance(idx1);
                    currme = cell(1, length(opt.ElasticWeight));
                    parfor idx2 = 1:length(opt.ElasticWeight)
                        ew = opt.ElasticWeight(idx2);
                        currarg = args;
                        currarg{find(strcmp(currarg, 'ElasticBalance')) + 1} = eb;
                        currarg{find(strcmp(currarg, 'ElasticWeight')) + 1} = ew;
                        currme{idx2} = MaxEntropyGeneral.Regularized(data(map, :), currarg{:});
                        currme{idx2}.ElasticWeight = ew;
                        currme{idx2}.ElasticBalance = eb;
                    end
                    mes = [mes(:)', currme(:)'];
                end
                if ~isempty(opt.TrainMap)
                    %%
                    ref = InfoTheory.JointProbsVec(data(~map, :), 0:mes{1}.nVals);
                    js = zeros(length(opt.ElasticBalance), length(opt.ElasticWeight));
                    idx = zeros(length(opt.ElasticBalance), length(opt.ElasticWeight));
                    for i=1:length(mes)
                        mes{i}.JensenShannon = InfoTheory.JensenShannon(ref, mes{i}.JointProbs);
                        js(find(opt.ElasticBalance == mes{i}.ElasticBalance), find(opt.ElasticWeight == mes{i}.ElasticWeight)) = mes{i}.JensenShannon;
                        idx(find(opt.ElasticBalance == mes{i}.ElasticBalance), find(opt.ElasticWeight == mes{i}.ElasticWeight)) = i;
                    end
                    valid = js(:) <= min(js(:))+ min(js(:)) * opt.Tolerence;
                    best.idx = 0;
                    best.js = inf;
                    best.weight = -inf;
                    for i=Q.torow(idx(valid))
                        if best.weight < mes{i}.ElasticWeight
                            best.js = mes{i}.JensenShannon;
                            best.idx = i;
                            best.weight = mes{i}.ElasticWeight;
                        end
                    end
                    if opt.Output
                        %%
                        semilogx(opt.ElasticWeight, js, 'o-');
                        hold on;
                        semilogx(best.weight, best.js, 'o-');
                        Fig.HLine(InfoTheory.JensenShannon(ref, mes{best.idx}.EmpJointProbs));
                        hold off;
                        title(sprintf('%.2f', best.js));
                    end
                    
                    %%
                    currarg = args;
                    currarg{find(strcmp(currarg, 'ElasticBalance')) + 1} = mes{best.idx}.ElasticBalance;
                    currarg{find(strcmp(currarg, 'ElasticWeight')) + 1} = mes{best.idx}.ElasticWeight;
                    me = MaxEntropyGeneral.Regularized(data, currarg{:});
                end

                return;
            end
            
            %%
            
            if opt.MemoryAware
                memfunc = @sparse;
            else
                memfunc = @(x) x;
            end
            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(varargin)
                order = 2;
                maxval = max(data(:))+1;
            elseif length(varargin) == 1
                if isstruct(varargin{1})
                    orig = varargin{1};
                    patterns = orig.Patterns;
                    maxval = orig.nVals;
                elseif isscalar(varargin{1})
                    order = varargin{1};
                    maxval = max(data(:))+1;
                else
                    patterns = varargin{1};
                    order = nan;
                end
            else
                if isscalar(varargin{1})
                    order = varargin{1};
                else
                    patterns = varargin{1};
                end
                maxval = varargin{2};
            end
            nvals = maxval + 1;
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            if opt.Verbose; Console.Subtitle('initializing weights'); end
            randinit = true;
            if ~isempty(opt.Weights)
                orig.Weights = opt.Weights;
            elseif randinit
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
            else
                orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
            end
            me = orig;
            me.Momentum = me.Weights;
            me.Patterns = patterns;
            %%
            if opt.UseMEX
                if opt.Verbose; Console.Message(1, 'using external mex code'); end
                [u, ~, ic] = unique(InfoTheory.Base2Dec(data, nvals));
                ud = InfoTheory.Dec2Base(u, dim, nvals);
                count = histc(ic, 1:length(u));
                expected = MaxEntropyGeneralNormalizedExpectation(ud, patterns, count);
                u = []; ud = []; ic = []; count = []; %#ok<NASGU>
            else
                if opt.Verbose; Console.Message(1, 'using only native matlab code'); end
                expected = mean(MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals), 1);
                %%
                perms = InfoTheory.Dec2Base(0:nvals^dim-1, dim, nvals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, patterns, nvals);
            end
            %%
            empprob = memfunc(InfoTheory.JointProbsVec(data, 0:nvals-1));
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            
            %%
            History = struct('Weights', {}, 'KL', {}, 'tr', {}, 'df', {});
            LBFGS = struct('s', {}, 'y', {}, 'p', {});
            %%
            prevKL = inf;
            nConverge = 0;
            tr = opt.InitialTrainRate;
            nzidx = find(empprob);
            nzempprob = nonzeros(empprob);
            KL1 = nzempprob' * InfoTheory.Log2(nzempprob);
            log2e = log2(exp(1));
            trainTypeKL2 = zeros(1, length(opt.TrainTypes));
            C = sum(MaxEntropyGeneral.ToFeaturesSparse(ones(1, size(patterns, 2)), patterns, nvals));
            iter = 1;
            htime = tic;
            regfun  = @(w) opt.ElasticWeight * mean((1-opt.ElasticBalance)/2 * w.^2 + opt.ElasticBalance * abs(w));
            dregfun = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance) * w + opt.ElasticBalance * (2 * ( w >= 0 ) - 1)) / length(w);
            %prox = 
            while iter < opt.MaxIters
                if iter == 1
                    if opt.UseMEX
                        prob = exp(MaxEntropyGeneralEnergy(nvals, patterns, me.Weights));
                    else
                        prob = exp(feats * me.Weights');
                    end
                    prob = prob / sum(prob);
                    KL2 = nzempprob' * InfoTheory.Log2(prob(nzidx)); %#ok<FNDSB>
                    KL = KL1 - KL2 + regfun(me.Weights);
                end
                %%
                if prevKL - KL  < opt.KLThresh
                    nConverge = nConverge + 1;
                    if nConverge >= opt.MinRepeatsToConverge
                        break;
                    end
                end
                prevKL = KL;
                %%
                if opt.UseMEX
                    margin = MaxEntropyGeneralWeightedExpectation(nvals, patterns, prob);
                else
                    margin = prob' * feats;
                end
                df = (expected - margin) - dregfun(me.Weights);
                
                %%
                if iter > 1
                    LBFGS(iter-1).y = df - History(iter-1).df;
                    LBFGS(iter-1).p = 1 / (LBFGS(iter-1).s * LBFGS(iter-1).y');
                    a = zeros(1, opt.LBFGSMemoryLength);
                    H = (LBFGS(iter-1).s * LBFGS(iter-1).y')/(LBFGS(iter-1).y * LBFGS(iter-1).y');
                    q = df;
                    start = max(iter - opt.LBFGSMemoryLength, 1);
                    for i=iter-1:-1:start
                        idx = i - start + 1;
                        a(idx) = LBFGS(i).p * (LBFGS(i).s * q');
                        q = q - a(idx) * LBFGS(i).y;
                    end
                    r = (H .* q)';
                    for i=start:iter-1
                        idx = i - start + 1;
                        b = LBFGS(i).p * (LBFGS(i).y * r);
                        dr = LBFGS(i).s' * (a(idx) - b);
                        r = r + dr;
                    end
                    dw = -r';
                else
                    dw = df;
                end
                %%
                tr = opt.InitialTrainRate;
                pm = me.Momentum;
                for searchiter = 1:opt.MaxLineSearchBacktracks
                    bestKL2 = -inf;
                    besttype = 0;
                    for q=opt.TrainTypes
                        m = me.Weights + tr * df;
                        if q==1                        % LBFGS
                            currw = me.Weights + tr * dw;
                        elseif q==2                    % GD
                            currw = me.Weights + tr * df;
                        elseif q==3 && searchiter == 1 % GIS
                            currw = me.Weights + 1 / C * InfoTheory.Log(expected ./ margin);
                            currw(expected == 0) = me.Weights(expected == 0);
                        else                           % Nesterov
                            currw = m + (iter-1)/(iter+2)*(m - pm);
                        end
                        %%
                        if opt.UseMEX
                            lprob = MaxEntropyGeneralEnergy(nvals, patterns, currw);
                        else
                            lprob = feats * currw';
                        end
                        z = sum(exp(lprob));
                        tKL2 = (empprob' * lprob) * log2e - InfoTheory.Log2(z) - regfun(currw);
                        %%
                        trainTypeKL2(q) = tKL2;
                        if tKL2 > bestKL2
                            bestKL2 = tKL2;
                            prob = exp(lprob) / z;
                            w = currw;
                            besttype = q;
                            %H = -(prob' * lprob) * log2e + InfoTheory.Log2(z);
                        end
                    end
                    %currdw = (expected - p' * feats);
                    if bestKL2 > KL2 %+ wolfc1 * tr * (dw * dw') && ...
                        %abs(currdw * dw') <= wolfc2 * abs(dw * dw');
                        break
                    end
                    tr = tr / 10;
                end
                KL2 = bestKL2;
                KL = KL1 - KL2;
                me.Weights = w;
                me.Momentum = m;
                %%
                switch besttype
                    case 1
                        trainname = ' LBFGS  ';
                    case 2
                        trainname = '  GD    ';
                    case 3
                        trainname = '  GIS   ';
                    case 4
                        trainname = 'Nesterov';
                    otherwise
                        trainname = 'Unknown ';
                end
                
                %%
                if length(opt.TrainTypes) > 1
                    %fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f', iter, trainname, KL, H, tr, toc(htime)/iter);
                    if opt.Verbose; 
                        fprintf('# iter %4d (%s): KL-regularized=%3.5f, tr=%g, ips=%.2f', iter, trainname, KL, tr, toc(htime)/iter); 
                        fprintf(mat2str(KL1 - trainTypeKL2, 3));
                        fprintf('\n');
                    end
                else
                    %fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f\n', iter, trainname, KL, H, tr, toc(htime)/iter);
                    if opt.Verbose; fprintf('# iter %4d (%s): KL-regularized=%3.5f, tr=%g, ips=%.2f\n', iter, trainname, KL, tr, toc(htime)/iter); end
                end
                %%
                History(iter) = struct('Weights', me.Weights, 'KL', KL, 'tr', tr, 'df', df);
                %%
                if iter > 1
                    LBFGS(iter).s = me.Weights - History(iter-1).Weights;
                else
                    LBFGS(iter).s = me.Weights - orig.Weights;
                end
                %%
                iter = iter + 1;
            end
            H = InfoTheory.Entropy(exp(lprob)/sum(exp(lprob)));
            if opt.Verbose; fprintf('# iter %4d: KL-regularized=%f, H=%f/%f (%.2f%%)\n', iter, KL, indepEntropy-H, multiInfo, (indepEntropy-H)/multiInfo*100); end
            %%
            me.Weights = me.Weights;
            me.KL = [History.KL];
            %%
            me.Patterns = patterns;
            me.Expected = expected;
            me.nVals = nvals;
            me = MaxEntropyGeneral.FillModel(data, me);
            me.nVals = maxval;
            %%
            me.ElasticWeight = opt.ElasticWeight;
            me.ElasticBalance = opt.ElasticBalance;
            %%
            if false
                MaxEntropyGeneral.ProbProb(me.EmpObservedProbs, me.JointProbs(me.EmpObservedMap), perms(me.EmpObservedMap, :));
                title({sprintf('RI - %d patterns', me.nPatterns), sprintf('(KL-regularized = %.3f)', me.KL)});
            end
        end
        

        function [me, mes, ref] = Regularized(data, varargin)
            % trains a Maximum entropy model using LBFGS
            % based on: Nocedal, Jorge, and Stephen J. Wright. Conjugate gradient methods. Springer New York, 2006.
            %   TrainLBFGS(data, patterns) trains the model with the specified patterns
            %   TrainLBFGS(data, order, nvals) trains the model with the specified order
            %wolfc1 = 1e-1;
            %wolfc2 = .9;
            opt = Q.defaultargs(struct(varargin{find(cellfun(@ischar, varargin)):end}), ...
                'Verbose', true, ...
                'ElasticBalance', 1, ... %% Scalar value from 0 to 1 (excluding 0) representing the weight of lasso (L1) versus ridge (L2) optimization. Alpha = 1 represents lasso regression, Alpha close to 0 approaches ridge regression
                'ElasticWeight', 0, ... %% 0 no regularization
                'TrainTypes', [2 4], ...
                'MaxIters', 15000,...
                'InitialTrainRate', 1,...
                'MinRepeatsToConverge', 10, ...
                'MaxLineSearchBacktracks', 25,...
                'KLThresh', 1e-7, ...
                'UseMEX', true, ...
                'Output', true, ...
                'Weights', [], ...
                'Tolerence', 0.05, ...
                'TrainMap', [], ... % if set, divides data to train and test sets to choose best model
                'MemoryAware', true);
            args = varargin;
            varargin(find(cellfun(@ischar, varargin)):end) = [];
            %%
            ref = [];
            if length(opt.ElasticBalance) > 1 || length(opt.ElasticWeight) > 1
                if isempty(opt.TrainMap)
                    map = true(size(data, 2), 1);
                else
                    map = opt.TrainMap(:);
                end
                mes={};
                for idx1 = 1:length(opt.ElasticBalance)
                    eb = opt.ElasticBalance(idx1);
                    currme = cell(1, length(opt.ElasticWeight));
                    parfor idx2 = 1:length(opt.ElasticWeight)
                        ew = opt.ElasticWeight(idx2);
                        currarg = args;
                        currarg{find(strcmp(currarg, 'ElasticBalance')) + 1} = eb;
                        currarg{find(strcmp(currarg, 'ElasticWeight')) + 1} = ew;
                        currme{idx2} = MaxEntropyGeneral.Regularized(data(map, :), currarg{:});
                        currme{idx2}.ElasticWeight = ew;
                        currme{idx2}.ElasticBalance = eb;
                    end
                    mes = [mes(:)', currme(:)'];
                end
                if ~isempty(opt.TrainMap)
                    %%
                    ref = InfoTheory.JointProbsVec(data(~map, :), 0:mes{1}.nVals);
                    js = zeros(length(opt.ElasticBalance), length(opt.ElasticWeight));
                    idx = zeros(length(opt.ElasticBalance), length(opt.ElasticWeight));
                    for i=1:length(mes)
                        mes{i}.JensenShannon = InfoTheory.JensenShannon(ref, mes{i}.JointProbs);
                        js(find(opt.ElasticBalance == mes{i}.ElasticBalance), find(opt.ElasticWeight == mes{i}.ElasticWeight)) = mes{i}.JensenShannon;
                        idx(find(opt.ElasticBalance == mes{i}.ElasticBalance), find(opt.ElasticWeight == mes{i}.ElasticWeight)) = i;
                    end
                    valid = js(:) <= min(js(:))+ min(js(:)) * opt.Tolerence;
                    best.idx = 0;
                    best.js = inf;
                    best.weight = -inf;
                    for i=Q.torow(idx(valid))
                        if best.weight < mes{i}.ElasticWeight
                            best.js = mes{i}.JensenShannon;
                            best.idx = i;
                            best.weight = mes{i}.ElasticWeight;
                        end
                    end
                    if opt.Output
                        %%
                        semilogx(opt.ElasticWeight, js, 'o-');
                        hold on;
                        semilogx(best.weight, best.js, 'o-');
                        Fig.HLine(InfoTheory.JensenShannon(ref, mes{best.idx}.EmpJointProbs));
                        hold off;
                        title(sprintf('%.2f', best.js));
                    end
                    
                    %%
                    currarg = args;
                    currarg{find(strcmp(currarg, 'ElasticBalance')) + 1} = mes{best.idx}.ElasticBalance;
                    currarg{find(strcmp(currarg, 'ElasticWeight')) + 1} = mes{best.idx}.ElasticWeight;
                    me = MaxEntropyGeneral.Regularized(data, currarg{:});
                end

                return;
            end
            
            %%
            
            if opt.MemoryAware
                memfunc = @sparse;
            else
                memfunc = @(x) x;
            end
            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(varargin)
                order = 2;
                maxval = max(data(:))+1;
            elseif length(varargin) == 1
                if isstruct(varargin{1})
                    orig = varargin{1};
                    patterns = orig.Patterns;
                    maxval = orig.nVals;
                elseif isscalar(varargin{1})
                    order = varargin{1};
                    maxval = max(data(:))+1;
                else
                    patterns = varargin{1};
                    order = nan;
                end
            else
                if isscalar(varargin{1})
                    order = varargin{1};
                else
                    patterns = varargin{1};
                end
                maxval = varargin{2};
            end
            nvals = maxval + 1;
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            if opt.Verbose; Console.Subtitle('initializing weights'); end
            randinit = true;
            if ~isempty(opt.Weights)
                orig.Weights = opt.Weights;
            elseif randinit
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
            else
                orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
            end
            me = orig;
            me.Momentum = me.Weights;
            me.Patterns = patterns;
            %%
            if opt.UseMEX
                if opt.Verbose; Console.Message(1, 'using external mex code'); end
                [u, ~, ic] = unique(InfoTheory.Base2Dec(data, nvals));
                ud = InfoTheory.Dec2Base(u, dim, nvals);
                count = histc(ic, 1:length(u));
                expected = MaxEntropyGeneralNormalizedExpectation(ud, patterns, count);
                u = []; ud = []; ic = []; count = []; %#ok<NASGU>
            else
                if opt.Verbose; Console.Message(1, 'using only native matlab code'); end
                expected = mean(MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals), 1);
                %%
                perms = InfoTheory.Dec2Base(0:nvals^dim-1, dim, nvals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, patterns, nvals);
            end
            %%
            empprob = memfunc(InfoTheory.JointProbsVec(data, 0:nvals-1));
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            
            %%
            History = struct('Weights', {}, 'KL', {}, 'tr', {}, 'df', {});
            %%
            prevKL = inf;
            nConverge = 0;
            tr = opt.InitialTrainRate;
            nzidx = find(empprob);
            nzempprob = nonzeros(empprob);
            KL1 = nzempprob' * InfoTheory.Log2(nzempprob);
            log2e = log2(exp(1));
            trainTypeKL2 = zeros(1, length(opt.TrainTypes));
            C = sum(MaxEntropyGeneral.ToFeaturesSparse(ones(1, size(patterns, 2)), patterns, nvals));
            iter = 1;
            htime = tic;
            
            kk = 10;
            
            regfun  = @(w) opt.ElasticWeight * mean((1-opt.ElasticBalance)/2 * w.^2 + opt.ElasticBalance * abs(w));
            dregfun = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance) * w + opt.ElasticBalance * (2 * ( w >= 0 ) - 1)) / length(w);

            smoothabs = @(x, kk) 2/kk*log(1+exp(kk*x)) - x - 2/kk*log(2);
            %regfun  = @(w) opt.ElasticWeight * mean((1-opt.ElasticBalance)/2 * w.^2 + opt.ElasticBalance * abs(w));
            regfun  = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance)/2 * w(:)'*w(:) + opt.ElasticBalance * sum(abs(w))) / length(w);
            %dregfun = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance) * w + opt.ElasticBalance * (2 * ( w >= 0 ) - 1)) / length(w);
            
            
            dregfun = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance) * w) / length(w);

            
            ttt = 0.001;
            absfun = @(x) sqrt(x.^2 + ttt);
            dabsfun = @(x) x./sqrt(x.^2 + ttt);
            absfun = @(x) abs(x);
            dabsfun = @(x) sign(x);
            regfun  = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance)/2 * w(:)'*w(:) + opt.ElasticBalance * sum(absfun(w))) / length(w);
            dregfun = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance) * w + opt.ElasticBalance * dabsfun(w)) / length(w);
            dregfun = @(w) opt.ElasticWeight * ((1-opt.ElasticBalance) * w) / length(w);
            
            %dregfun = @(w) 0;
            %prox = @(x, t) sign(x).*max(abs(x)-t  *lambda,0);
            lambda = @(x, t) opt.ElasticBalance * opt.ElasticWeight * t; 
            prox = @(x, t) sign(x).*max(abs(x) - lambda(x, t), 0);
            prox = @(x, t) x;
            

            
            while iter < opt.MaxIters
                if iter == 1
                    if opt.UseMEX
                        prob = exp(MaxEntropyGeneralEnergy(nvals, patterns, me.Weights));
                    else
                        prob = exp(feats * me.Weights');
                    end
                    prob = prob / sum(prob);
                    KL2 = nzempprob' * InfoTheory.Log2(prob(nzidx)); %#ok<FNDSB>
                    KL = KL1 - KL2 + regfun(me.Weights);
                end
                %%
                if prevKL - KL  < opt.KLThresh
                    nConverge = nConverge + 1;
                    if nConverge >= opt.MinRepeatsToConverge
                        break;
                    end
                end
                prevKL = KL;
                %%
                if opt.UseMEX
                    margin = MaxEntropyGeneralWeightedExpectation(nvals, patterns, prob);
                else
                    margin = prob' * feats;
                end
                %df = (expected - margin) - dregfun(me.Weights);
                df = (expected - margin) - dregfun(me.Weights);
                
                %%
                tr = opt.InitialTrainRate;
                pm = me.Momentum;
                for searchiter = 1:opt.MaxLineSearchBacktracks
                    bestKL2 = -inf;
                    besttype = 0;
                    for q=opt.TrainTypes
                        %m = me.Weights + tr * df;
                        m = prox(me.Weights + tr * df, tr);
                        if q==1                        % LBFGS
                            error
                        elseif q==2                    % GD
                            currw = prox(me.Weights + tr * df, tr);
                        elseif q==3 && searchiter == 1 % GIS
                            error
                        else                           % Nesterov
                            currw = m + (iter-1)/(iter+2)*(m - pm);
                        end
                        %%
                        if opt.UseMEX
                            lprob = MaxEntropyGeneralEnergy(nvals, patterns, currw);
                        else
                            lprob = feats * currw';
                        end
                        z = sum(exp(lprob));
                        tKL2 = (empprob' * lprob) * log2e - InfoTheory.Log2(z) - regfun(currw);
                        %%
                        trainTypeKL2(q) = tKL2;
                        if tKL2 > bestKL2
                            bestKL2 = tKL2;
                            prob = exp(lprob) / z;
                            w = currw;
                            besttype = q;
                            %H = -(prob' * lprob) * log2e + InfoTheory.Log2(z);
                        end
                    end
                    %currdw = (expected - p' * feats);
                    if bestKL2 > KL2 %+ wolfc1 * tr * (dw * dw') && ...
                        %abs(currdw * dw') <= wolfc2 * abs(dw * dw');
                        break
                    end
                    tr = tr / 10;
                end
                KL2 = bestKL2;
                KL = KL1 - KL2;
                me.Weights = w;
                me.Momentum = m;
                %%
                switch besttype
                    case 1
                        trainname = ' LBFGS(ERROR)';
                    case 2
                        trainname = '  GD    ';
                    case 3
                        trainname = '  GIS   ';
                    case 4
                        trainname = 'Nesterov';
                    otherwise
                        trainname = 'Unknown ';
                end
                
                %%
                if length(opt.TrainTypes) > 1
                    %fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f', iter, trainname, KL, H, tr, toc(htime)/iter);
                    if opt.Verbose; 
                        fprintf('# iter %4d (%s): KL-regularized=%3.5f, tr=%g, ips=%.2f', iter, trainname, KL, tr, toc(htime)/iter); 
                        fprintf(mat2str(KL1 - trainTypeKL2, 3));
                        fprintf('\n');
                    end
                else
                    %fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f\n', iter, trainname, KL, H, tr, toc(htime)/iter);
                    if opt.Verbose; fprintf('# iter %4d (%s): KL-regularized=%3.5f, tr=%g, ips=%.2f\n', iter, trainname, KL, tr, toc(htime)/iter); end
                end
                %%
                History(iter) = struct('Weights', me.Weights, 'KL', KL, 'tr', tr, 'df', df);
                %%
                iter = iter + 1;
            end
            H = InfoTheory.Entropy(exp(lprob)/sum(exp(lprob)));
            if opt.Verbose; fprintf('# iter %4d: KL-regularized=%f, H=%f/%f (%.2f%%)\n', iter, KL, indepEntropy-H, multiInfo, (indepEntropy-H)/multiInfo*100); end
            %%
            me.Weights = me.Weights;
            me.KL = [History.KL];
            %%
            me.Patterns = patterns;
            me.Expected = expected;
            me.nVals = nvals;
            me = MaxEntropyGeneral.FillModel(data, me);
            me.nVals = maxval;
            %%
            me.ElasticWeight = opt.ElasticWeight;
            me.ElasticBalance = opt.ElasticBalance;
            %%
            if false
                MaxEntropyGeneral.ProbProb(me.EmpObservedProbs, me.JointProbs(me.EmpObservedMap), perms(me.EmpObservedMap, :));
                title({sprintf('RI - %d patterns', me.nPatterns), sprintf('(KL-regularized = %.3f)', me.KL)});
            end
        end
        

        function me = Regularized2(data, order, nvals, varargin)
            parser = inputParser;
            parser.addOptional('Verbose', true);
            parser.addOptional('Gamma', 0);
            parser.addOptional('Alpha', .5);
            parser.addOptional('Weights', []);
            
            parser.parse(varargin{:});
            opt = parser.Results;
            

            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            if opt.Verbose; Console.Subtitle('initializing weights'); end
            randinit = true;
            if ~isempty(opt.Weights)
                orig.Weights = opt.Weights;
            elseif randinit
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
            else
                orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
            end
            me = orig;
            me.Patterns = patterns;
            %%
            if opt.Verbose; Console.Message(1, 'using external mex code'); end
            [u, ~, ic] = unique(InfoTheory.Base2Dec(data, nvals));
            ud = InfoTheory.Dec2Base(u, dim, nvals);
            count = histc(ic, 1:length(u));
            expected = MaxEntropyGeneralNormalizedExpectation(ud, patterns, count);
            u = []; ud = []; ic = []; count = []; %#ok<NASGU>
            %%
            empprob = sparse(InfoTheory.JointProbsVec(data, 0:nvals-1));
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            
            %%
            
            options = optimoptions('fminunc','Algorithm','trust-region','SpecifyObjectiveGradient',true, 'Display', 'iter', 'TolFun', 1e-7, 'MaxIterations', 5000);
            options = optimoptions('fminunc','Algorithm','quasi-newton','SpecifyObjectiveGradient',true, 'Display', 'final', 'MaxIterations', 5000, 'TolFun', 1e-7, 'UseParallel', true);
            options = optimoptions('fminunc','Algorithm','quasi-newton','SpecifyObjectiveGradient',true, 'Display', 'iter', 'MaxIterations', 5000, 'TolFun', 1e-7, 'UseParallel', false);
            
            w0 = me.Weights;
            
            
            problem.options = options;
            problem.x0 = w0;
            problem.objective = @(w) MaxEntropyGeneral.TargetFunction(nonzeros(empprob), nvals, patterns, w, find(empprob), expected, opt.Gamma, opt.Alpha);
            problem.solver = 'fminunc';
            
            
            if opt.Verbose; Console.Message(1, 'trainig model'); end
            me.Weights = fminunc(problem);
            Console.Message(2, 'score = %f', problem.objective(me.Weights))
            %%
            me.Expected = expected;
            me.nVals = nvals;
            me = MaxEntropyGeneral.FillModel(data, me);
            me.Score = MaxEntropyGeneral.TargetFunction(nonzeros(empprob), nvals, patterns, me.Weights, find(empprob), expected);
        end

        function [f, df] = TargetFunction(nzempprob, nvals, patterns, w, nzidx, expected, gamma, alpha)
            prob = exp(MaxEntropyGeneralEnergy(nvals, patterns, w));
            prob = prob / sum(prob);
            f = -nzempprob' * InfoTheory.Log2(prob(nzidx));
            if nargin > 6
                f = f + gamma * mean((1-alpha)/2 * w.^2 + alpha * abs(w));
            end
            if nargout > 1
                df = -(expected - MaxEntropyGeneralWeightedExpectation(nvals, patterns, prob));
                if nargin > 6
                    df = df + gamma * ((1-alpha) * w + alpha * (2 * ( w >= 0 ) - 1)) / length(w);
                end
            end
        end
        
        
        
        function me = Train(data, varargin)
            % trains a Maximum entropy model using LBFGS
            % based on: Nocedal, Jorge, and Stephen J. Wright. Conjugate gradient methods. Springer New York, 2006.
            %   Train(data, patterns) trains the model with the specified patterns
            %   Train(data, order, nvals) trains the model with the specified order
            %   wolfc1 = 1e-1;
            %   wolfc2 = .9;
            opt = Q.defaultargs(struct(varargin{find(cellfun(@ischar, varargin)):end}), ...
                'Verbose', true, ...
                'TrainTypes', 1:4, ...
                'LBFGSMemoryLength', 15, ...
                'MaxIters', 15000,...
                'InitialTrainRate', 1,...
                'MinRepeatsToConverge', 10, ...
                'MaxLineSearchBacktracks', 25,...
                'KLThresh', 1e-7, ...
                'UseMEX', true, ...
                'MemoryAware', true);
            varargin(find(cellfun(@ischar, varargin)):end) = [];
            %%
            try
                MaxEntropyGeneralNormalizedExpectation
            catch me
                if me.identifier == "MATLAB:UndefinedFunction"
                    installMaximumEntropy
                end
            end
            %%
            if opt.MemoryAware
                memfunc = @sparse;
            else
                memfunc = @(x) x;
            end
            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(varargin)
                order = 2;
                nvals = max(data(:))+1;
            elseif length(varargin) == 1
                if isstruct(varargin{1})
                    orig = varargin{1};
                    patterns = orig.Patterns;
                    nvals = orig.nVals;
                elseif isscalar(varargin{1})
                    order = varargin{1};
                    nvals = max(data(:))+1;
                else
                    patterns = varargin{1};
                    order = nan;
                end
            else
                if isscalar(varargin{1})
                    order = varargin{1};
                else
                    patterns = varargin{1};
                end
                nvals = varargin{2};
            end
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            if opt.Verbose; Console.Subtitle('initializing weights'); end
            randinit = true;
            if randinit
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
            else
                orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
            end
            me = orig;
            me.Momentum = me.Weights;
            me.Patterns = patterns;
            %%
            if opt.UseMEX
                if opt.Verbose; Console.Message(1, 'using external mex code'); end
                [u, ~, ic] = unique(InfoTheory.Base2Dec(data, nvals));
                ud = InfoTheory.Dec2Base(u, dim, nvals);
                count = histc(ic, 1:length(u));
                expected = MaxEntropyGeneralNormalizedExpectation(ud, patterns, count);
                u = []; ud = []; ic = []; count = []; %#ok<NASGU>
            else
                if opt.Verbose; Console.Message(1, 'using only native matlab code'); end
                expected = mean(MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals), 1);
                %%
                perms = InfoTheory.Dec2Base(0:nvals^dim-1, dim, nvals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, patterns, nvals);
            end
            %%
            empprob = memfunc(InfoTheory.JointProbsVec(data, 0:nvals-1));
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            
            %%
            History = struct('Weights', {}, 'KL', {}, 'tr', {}, 'df', {});
            LBFGS = struct('s', {}, 'y', {}, 'p', {});
            %%
            prevKL = inf;
            nConverge = 0;
            tr = opt.InitialTrainRate;
            nzidx = find(empprob);
            nzempprob = nonzeros(empprob);
            KL1 = nzempprob' * InfoTheory.Log2(nzempprob);
            log2e = log2(exp(1));
            trainTypeKL2 = zeros(1, length(opt.TrainTypes));
            C = sum(MaxEntropyGeneral.ToFeaturesSparse(ones(1, size(patterns, 2)), patterns, nvals));
            iter = 1;
            htime = tic;
            while iter < opt.MaxIters
                if iter == 1
                    if opt.UseMEX
                        prob = exp(MaxEntropyGeneralEnergy(nvals, patterns, me.Weights));
                    else
                        prob = exp(feats * me.Weights');
                    end
                    prob = prob / sum(prob);
                    KL2 = nzempprob' * InfoTheory.Log2(prob(nzidx));
                    KL = KL1 - KL2;
                end
                %%
                if prevKL - KL  < opt.KLThresh
                    nConverge = nConverge + 1;
                    if nConverge >= opt.MinRepeatsToConverge
                        break;
                    end
                end
                prevKL = KL;
                %%
                if opt.UseMEX
                    margin = MaxEntropyGeneralWeightedExpectation(nvals, patterns, prob);
                else
                    margin = prob' * feats;
                end
                df = (expected - margin);
                
                %%
                if iter > 1
                    LBFGS(iter-1).y = df - History(iter-1).df;
                    LBFGS(iter-1).p = 1 / (LBFGS(iter-1).s * LBFGS(iter-1).y');
                    a = zeros(1, opt.LBFGSMemoryLength);
                    H = (LBFGS(iter-1).s * LBFGS(iter-1).y')/(LBFGS(iter-1).y * LBFGS(iter-1).y');
                    q = df;
                    start = max(iter - opt.LBFGSMemoryLength, 1);
                    for i=iter-1:-1:start
                        idx = i - start + 1;
                        a(idx) = LBFGS(i).p * (LBFGS(i).s * q');
                        q = q - a(idx) * LBFGS(i).y;
                    end
                    r = (H .* q)';
                    for i=start:iter-1
                        idx = i - start + 1;
                        b = LBFGS(i).p * (LBFGS(i).y * r);
                        dr = LBFGS(i).s' * (a(idx) - b);
                        r = r + dr;
                    end
                    dw = -r';
                else
                    dw = df;
                end
                %%
                tr = opt.InitialTrainRate;
                pm = me.Momentum;
                for searchiter = 1:opt.MaxLineSearchBacktracks
                    bestKL2 = -inf;
                    besttype = 0;
                    for q=opt.TrainTypes
                        m = me.Weights + tr * df;
                        if q==1                        % LBFGS
                            currw = me.Weights + tr * dw;
                        elseif q==2                    % GD
                            currw = me.Weights + tr * df;
                        elseif q==3 && searchiter == 1 % GIS
                            currw = me.Weights + 1 / C * InfoTheory.Log(expected ./ margin);
                            currw(expected == 0) = me.Weights(expected == 0);
                        else                           % Nesterov
                            currw = m + (iter-1)/(iter+2)*(m - pm);
                        end
                        %%
                        if opt.UseMEX
                            lprob = MaxEntropyGeneralEnergy(nvals, patterns, currw);
                        else
                            lprob = feats * currw';
                        end
                        z = sum(exp(lprob));
                        tKL2 = (empprob' * lprob) * log2e - InfoTheory.Log2(z);
                        %%
                        trainTypeKL2(q) = tKL2;
                        if tKL2 > bestKL2
                            bestKL2 = tKL2;
                            prob = exp(lprob) / z;
                            w = currw;
                            besttype = q;
                            %H = -(prob' * lprob) * log2e + InfoTheory.Log2(z);
                        end
                    end
                    %currdw = (expected - p' * feats);
                    if bestKL2 > KL2 %+ wolfc1 * tr * (dw * dw') && ...
                        %abs(currdw * dw') <= wolfc2 * abs(dw * dw');
                        break
                    end
                    tr = tr / 10;
                end
                KL2 = bestKL2;
                KL = KL1 - KL2;
                me.Weights = w;
                me.Momentum = m;
                %%
                switch besttype
                    case 1
                        trainname = ' LBFGS  ';
                    case 2
                        trainname = '  GD    ';
                    case 3
                        trainname = '  GIS   ';
                    case 4
                        trainname = 'Nesterov';
                    otherwise
                        trainname = 'Unknown ';
                end
                
                %%
                if length(opt.TrainTypes) > 1
                    %fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f', iter, trainname, KL, H, tr, toc(htime)/iter);
                    if opt.Verbose; 
                        fprintf('# iter %4d (%s): KL=%3.5f, tr=%g, ips=%.2f', iter, trainname, KL, tr, toc(htime)/iter); 
                        fprintf(mat2str(KL1 - trainTypeKL2, 3));
                        fprintf('\n');
                    end
                else
                    %fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f\n', iter, trainname, KL, H, tr, toc(htime)/iter);
                    if opt.Verbose; fprintf('# iter %4d (%s): KL=%3.5f, tr=%g, ips=%.2f\n', iter, trainname, KL, tr, toc(htime)/iter); end
                end
                %%
                History(iter) = struct('Weights', me.Weights, 'KL', KL, 'tr', tr, 'df', df);
                %%
                if iter > 1
                    LBFGS(iter).s = me.Weights - History(iter-1).Weights;
                else
                    LBFGS(iter).s = me.Weights - orig.Weights;
                end
                %%
                iter = iter + 1;
            end
            H = InfoTheory.Entropy(exp(lprob)/sum(exp(lprob)));
            if opt.Verbose; fprintf('# iter %4d: KL=%f, H=%f/%f (%.2f%%)\n', iter, KL, indepEntropy-H, multiInfo, (indepEntropy-H)/multiInfo*100); end
            %%
            me.Weights = me.Weights;
            me.KL = [History.KL];
            %%
            me.Patterns = patterns;
            me.Expected = expected;
            me.nVals = nvals;
            me = MaxEntropyGeneral.FillModel(data, me);
            %%
            if false
                MaxEntropyGeneral.ProbProb(me.EmpObservedProbs, me.JointProbs(me.EmpObservedMap), perms(me.EmpObservedMap, :));
                title({sprintf('RI - %d patterns', me.nPatterns), sprintf('(KL = %.3f)', me.KL)});
            end
        end
        
        function me = TrainLBFGS(data, varargin)
            % trains a Maximum entropy model using LBFGS
            % based on: Nocedal, Jorge, and Stephen J. Wright. Conjugate gradient methods. Springer New York, 2006.
            %   TrainLBFGS(data, patterns) trains the model with the specified patterns
            %   TrainLBFGS(data, order, nvals) trains the model with the specified order
            maxiters = 15000;
            trainrate = 1;
            KLthresh = 1e-7;
            maxsearchiters = 25;
            convergeRepeats = 10;
            %wolfc1 = 1e-1;
            %wolfc2 = .9;
            usemex = true;
            opt = Q.defaultargs(struct(), 'LBFGSMemoryLength', 15);
            
            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(varargin)
                order = 2;
                nvals = max(data(:))+1;
            elseif length(varargin) == 1
                if isstruct(varargin{1})
                    orig = varargin{1};
                    patterns = orig.Patterns;
                    nvals = orig.nVals;
                elseif isscalar(varargin{1})
                    order = varargin{1};
                    nvals = max(data(:))+1;
                else
                    patterns = varargin{1};
                    order = nan;
                end
            else
                if isscalar(varargin{1})
                    order = varargin{1};
                else
                    patterns = varargin{1};
                end
                nvals = varargin{2};
            end
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            Console.Subtitle('initializing weights');
            randinit = true;
            if randinit
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
                me.Patterns = patterns;
            else
                orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
            end
            me = orig;
            %%
            if usemex
                Console.Message(1, 'using mex code to save memory');
                [u, ~, ic] = unique(data * (nvals.^(dim-1:-1:0))');
                ud = InfoTheory.Dec2Base(u, dim, nvals);
                expected = MaxEntropyGeneralNormalizedExpectation(ud, patterns, histc(ic, 1:length(u)));
                u = []; ud = []; ic = []; %#ok<NASGU>
            else
                Console.Message(1, 'using native matlab code');
                expected = mean(MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals), 1);
                %%
                perms = InfoTheory.Dec2Base(0:nvals^dim-1, dim, nvals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, patterns, nvals);
            end
            %%
            empprob = InfoTheory.JointProbsVec(data, 0:nvals-1);
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            %%
            History = struct('Weights', {}, 'KL', {}, 'tr', {}, 'df', {});
            LBFGS = struct('s', {}, 'y', {}, 'p', {});
            %%
            prevKL = inf;
            nConverge = 0;
            tr = trainrate;
            iter = 1;
            KL1 = empprob' * InfoTheory.Log2(empprob);
            log2e = log2(exp(1));
            htime = tic;
            while iter < maxiters
                if iter == 1
                    if usemex
                        prob = exp(MaxEntropyGeneralEnergy(nvals, patterns, me.Weights));
                    else
                        prob = exp(feats * me.Weights');
                    end
                    prob = prob / sum(prob);
                    KL2 = empprob' * InfoTheory.Log2(prob);
                    KL = KL1 - KL2;
                end
                %%
                if prevKL - KL  < KLthresh
                    nConverge = nConverge + 1;
                    if nConverge >= convergeRepeats
                        break;
                    end
                end
                prevKL = KL;
                %%
                if usemex
                    df = (expected - MaxEntropyGeneralWeightedExpectation(nvals, patterns, prob));
                else
                    df = (expected - prob' * feats);
                end
                
                %%
                if iter > 1
                    LBFGS(iter-1).y = df - History(iter-1).df;
                    LBFGS(iter-1).p = 1 / (LBFGS(iter-1).s * LBFGS(iter-1).y');
                    a = zeros(1, opt.LBFGSMemoryLength);
                    H = (LBFGS(iter-1).s * LBFGS(iter-1).y')/(LBFGS(iter-1).y * LBFGS(iter-1).y');
                    q = df;
                    start = max(iter - opt.LBFGSMemoryLength, 1);
                    for i=iter-1:-1:start
                        idx = i - start + 1;
                        a(idx) = LBFGS(i).p * (LBFGS(i).s * q');
                        q = q - a(idx) * LBFGS(i).y;
                    end
                    r = (H .* q)';
                    for i=start:iter-1
                        idx = i - start + 1;
                        b = LBFGS(i).p * (LBFGS(i).y * r);
                        dr = LBFGS(i).s' * (a(idx) - b);
                        r = r + dr;
                    end
                    dw = -r';
                else
                    dw = df;
                end
                %%
                tr = trainrate;
                
                for searchiter = 1:maxsearchiters
                    w = me.Weights + tr * dw;
                    if usemex
                        lprob = MaxEntropyGeneralEnergy(nvals, patterns, w);
                        prob = exp(lprob);
                    else
                        lprob = feats * w';
                        prob = exp(lprob);
                    end
                    z = sum(prob);
                    prob = prob / z;
                    tKL2 = (empprob' * lprob) * log2e - InfoTheory.Log2(z);
                    %currdw = (expected - p' * feats);
                    if tKL2 > KL2 %+ wolfc1 * tr * (dw * dw') && ...
                        %abs(currdw * dw') <= wolfc2 * abs(dw * dw');
                        break
                    end
                    tr = tr / 10;
                end
                KL2 = tKL2;
                KL = KL1 - KL2;
                me.Weights = w;
                %%
                H = -(prob' * lprob) * log2e + InfoTheory.Log2(z);
                %%
                fprintf('# iter %4d (LBFGS): KL=%3.5f, H=%.3f, tr=%g, ips=%.2f\n', iter, KL, H, tr, toc(htime)/iter);
                %%
                History(iter) = struct('Weights', me.Weights, 'KL', KL, 'tr', tr, 'df', df);
                %%
                if iter > 1
                    LBFGS(iter).s = me.Weights - History(iter-1).Weights;
                else
                    LBFGS(iter).s = me.Weights - orig.Weights;
                end
                %%
                iter = iter + 1;
            end
            fprintf('# iter %4d: KL=%f, H=%f/%f (%.2f%%)\n', iter, KL, indepEntropy-H, multiInfo, (indepEntropy-H)/multiInfo*100);
            %%
            me.Weights = me.Weights;
            me.KL = [History.KL];
            %%
            me.Patterns = patterns;
            me.Expected = expected;
            me.nVals = nvals;
            %me = MaxEntropyGeneral.FillModel(data, me);
            %%
            if false
                MaxEntropyGeneral.ProbProb(me.EmpObservedProbs, me.JointProbs(me.EmpObservedMap), perms(me.EmpObservedMap, :));
                title({sprintf('RI - %d patterns', me.nPatterns), sprintf('(KL = %.3f)', me.KL)});
            end
        end
        
        function me = TrainExports(data, varargin)
            % trains a Maximum entropy model using LBFGS
            % based on: Nocedal, Jorge, and Stephen J. Wright. Conjugate gradient methods. Springer New York, 2006.
            %   TrainLBFGS(data, patterns) trains the model with the specified patterns
            %   TrainLBFGS(data, order, nvals) trains the model with the specified order
            maxiters = 15000;
            maxiters = 50;
            trainrate = 1;
            KLthresh = 1e-7;
            maxsearchiters = 25;
            convergeRepeats = 10;
            %wolfc1 = 1e-1;
            %wolfc2 = .9;
            usemex = true;
            MinExpectation = .1 / size(data, 1);

            %% patterns
            dim = size(data, 2);
            patterns = [];
            
            if isempty(varargin)
                order = 2;
                nvals = max(data(:))+1;
            elseif length(varargin) == 1
                if isstruct(varargin{1})
                    orig = varargin{1};
                    patterns = orig.Patterns;
                    nvals = orig.nVals;
                elseif isscalar(varargin{1})
                    order = varargin{1};
                    nvals = max(data(:))+1;
                else
                    patterns = varargin{1};
                    order = nan;
                end
            else
                if isscalar(varargin{1})
                    order = varargin{1};
                else
                    patterns = varargin{1};
                end
                nvals = varargin{2};
            end
            if isempty(patterns)
                patterns = MaxEntropyGeneral.GeneratePatterns(dim, order, nvals);
            end
            
            %%
            Console.Subtitle('initializing weights');
            randinit = true;
            if randinit
                orig.Weights = randn(1, size(patterns, 1)) / size(patterns, 1);
            else
                orig = MaxEntropyGeneral.InitializeModel(data, patterns, nvals);
            end
            me = orig;
            me.Momentum = me.Weights;
            me.Patterns = patterns;
            
            %%
            if usemex
                Console.Message(1, 'using mex code to save memory');
                expected = MaxEntropyGeneralExpectation(data, patterns);
            else
                Console.Message(1, 'using native matlab code');
                expected = mean(MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals), 1);
                %%
                perms = InfoTheory.Dec2Base(0:nvals^dim-1, dim, nvals);
                feats = MaxEntropyGeneral.ToFeaturesSparse(perms, patterns, nvals);
            end
            %%
            empprob = InfoTheory.JointProbsVec(data, 0:nvals-1);
            indepEntropy = sum(InfoTheory.Entropy(InfoTheory.IndepProbs(data, 0:nvals-1)));
            jointEntropy = InfoTheory.Entropy(empprob);
            multiInfo = indepEntropy - jointEntropy;
            %%
            me.History.Weights = sparse(maxiters, length(me.Weights));
            me.History.KL = sparse(1, length(me.Weights));
            me.History.tr = sparse(1, length(me.Weights));
            me.History.dw = sparse(maxiters, length(me.Weights));
            %%
            LBFGS.s = sparse(maxiters, length(me.Weights));
            LBFGS.y = sparse(maxiters, length(me.Weights));
            LBFGS.p = sparse(maxiters, 1);
            LBFGS.m = 15;
            %%
            prevKL = inf;
            nConverge = 0;
            tr = trainrate;
            C = sum(MaxEntropyGeneral.ToFeaturesSparse(ones(1, size(patterns, 2)), patterns, nvals));
            iter = 1;
            while iter < maxiters
                if iter == 1
                    if usemex
                        prob = exp(MaxEntropyGeneralEnergy(nvals, patterns, me.Weights));
                    else
                        prob = exp(feats * me.Weights');
                    end
                    prob = prob / sum(prob);
                end
                %%
                KL = MaxEntropyGeneral.KullbackLiebler(empprob, prob);
                if prevKL - KL  < KLthresh
                    nConverge = nConverge + 1;
                    if nConverge >= convergeRepeats
                        break;
                    end
                end
                prevKL = KL;
                %%
                if usemex
                    margin = MaxEntropyGeneralWeightedExpectation(nvals, patterns, prob);
                else
                    margin = prob' * feats;
                end
                df = (expected - margin);
                
                %%
                if iter > 1
                    LBFGS.y(iter-1, :) = df - me.History.df(iter-1, :);
                    LBFGS.p(iter-1) = 1 / (LBFGS.s(iter-1, :) * LBFGS.y(iter-1, :)');
                    a = zeros(1, LBFGS.m);
                    H = (LBFGS.s(iter-1, :) * LBFGS.y(iter-1, :)')/(LBFGS.y(iter-1, :) * LBFGS.y(iter-1, :)');
                    q = df;
                    start = max(iter - LBFGS.m, 1);
                    for i=iter-1:-1:start
                        idx = i - start + 1;
                        a(idx) = LBFGS.p(i) * (LBFGS.s(i, :) * q');
                        q = q - a(idx) * LBFGS.y(i, :);
                    end
                    r = (H .* q)';
                    for i=start:iter-1
                        idx = i - start + 1;
                        b = LBFGS.p(i) * (LBFGS.y(i, :) * r);
                        dr = LBFGS.s(i, :)' * (a(idx) - b);
                        r = r + dr;
                    end
                    dw = -r';
                else
                    dw = df;
                end
                %%
                tr = trainrate;
                pm = me.Momentum;
                for searchiter = 1:maxsearchiters
                    tKL = inf;
                    KL_ = zeros(1,4);
                    Q = 0;
                    for q=1:4
                        if q==1
                            cw = me.Weights + tr * dw;
                        elseif q==2
                            cw = me.Weights + tr * df;
                        elseif q==3 && searchiter == 1
                            cw = me.Weights + 1 / C * log(expected ./ margin);
                            cw(margin == 0 | expected == 0) = 0;
                        else
                            cw = m + (iter-1)/(iter+2)*(m - pm);
                        end
                        if usemex
                            cprob = exp(MaxEntropyGeneralEnergy(nvals, patterns, cw));
                        else
                            cprob = exp(feats * cw');
                        end
                        cprob = cprob / sum(cprob);
                        cKL = MaxEntropyGeneral.KullbackLiebler(empprob, cprob);
                        KL_(q) = cKL;
                        if tKL > cKL
                            tKL = cKL;
                            prob = cprob;
                            w = cw;
                            Q = q;
                        end
                    end
                    %currdw = (expected - p' * feats);
                    if tKL <= KL %+ wolfc1 * tr * (dw * dw') && ...
                        %abs(currdw * dw') <= wolfc2 * abs(dw * dw');
                        break
                    end
                    tr = tr / 10;
                end
                me.Weights = w;
                me.Momentum = m;
                %%
                switch Q
                    case 1
                        name = 'LBFGS';
                    case 2
                        name = 'GD';
                    case 3
                        name = 'GIS';
                    case 4
                        name = 'Nesterov';
                end
                %%
                H = InfoTheory.Entropy(prob);
                %%
                fprintf('# iter %4d (%s): KL=%3.5f, H=%.3f, tr=%g [', iter, name, KL, H, tr);
                fprintf('%f, ', KL_);
                fprintf('%f]\n', KL);
                %%
                me.History.Weights(iter, :) = gather(me.Weights);
                me.History.KL(iter) = gather(KL);
                me.History.tr(iter) = tr;
                me.History.df(iter, :) = df;
                %%
                if iter > 1
                    LBFGS.s(iter, :) = me.Weights - me.History.Weights(iter-1, :);
                else
                    LBFGS.s(iter, :) = me.Weights - orig.Weights;
                end
                %%
                iter = iter + 1;
            end
            fprintf('# iter %4d: KL=%f, H=%f/%f (%.2f%%)\n', iter, KL, indepEntropy-H, multiInfo, (indepEntropy-H)/multiInfo*100);
            %%
            me.Weights = me.Weights;
            %%
            me.Patterns = patterns;
            me.Expected = expected;
            me.nVals = nvals;
            %me = MaxEntropyGeneral.FillModel(data, me);
            %%
            if false
                MaxEntropyGeneral.ProbProb(me.EmpObservedProbs, me.JointProbs(me.EmpObservedMap), perms(me.EmpObservedMap, :));
                title({sprintf('RI - %d patterns', me.nPatterns), sprintf('(KL = %.3f)', me.KL)});
            end
        end
        
        function feat = Expected(data, patterns, nvals)
            winsz = 1e9;
            nwins = ceil((size(data, 1) * size(patterns, 1)) / winsz);
            for i=1:nwins
                feat = true(size(data, 1), size(patterns, 1));
            end
        end

        function feat = ToFeaturesSparse(data, patterns, nvals)
            %%
            [ndata, dim] = size(data);
            maxsz = 1e9;
            winsz = ceil(maxsz / size(patterns, 1));
            nwins = ceil(ndata / winsz);
            %feat = logical(sparse(ndata, size(patterns, 1)));
            F = cell(1, nwins);
            for i=1:nwins
                curr = data((i - 1) * winsz + 1 : min(ndata, i * winsz), :);
                f = true(size(curr, 1), size(patterns, 1));
                %%
                for d=1:dim
                    D = curr(:, d);
                    P = patterns(:, d);
                    for v=0:nvals-1
                        m1 = D == v;
                        m2 = P == v | P == 0;
                        f(m1, ~m2) = false;
                    end
                end
                %feat((i - 1) * winsz + 1:(i - 1) * winsz + size(curr, 1), :) = f;
                F{i} = sparse(f);
            end
            feat = cat(1, F{:});
        end
        
        function feat = ToFeatures(data, patterns, nvals)
            %feat = MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals);
            %return;
            dim = size(data, 2);
            try
                feat = true(size(data, 1), size(patterns, 1));
            catch e
                if strcmp(e.identifier, 'MATLAB:nomem')
                    feat = MaxEntropyGeneral.ToFeaturesSparse(data, patterns, nvals);
                end
            end
            %%
            for d=1:dim
                D = data(:, d);
                P = patterns(:, d);
                for v=0:nvals-1
                    m1 = D == v;
                    m2 = P == v | P == 0;
                    feat(m1, ~m2) = false;
                end
            end
        end

        function me = InitializeModel(data, patterns, nvals)
            %%
            isweighted = false;
            %%
            [full, ~, idx] = MaxEntropyGeneral.Unique(data, nvals);
            count = histc(idx, 1:size(full, 1));
            %%
            match = MaxEntropyGeneral.ToFeatures(full, patterns, nvals);
            match = [match, true(size(match, 1), 1)];
            p = count / size(data, 1);
            warning('off', 'MATLAB:lscov:RankDefDesignMat');
            if isweighted
                w = lscov(double(match), log(p), p)';
            else
                w = (match\log(p(:)))';
            end
            me.Weights = w(1:end-1);
            warning('on', 'MATLAB:lscov:RankDefDesignMat');
            me.Patterns = patterns;
            me.nVals = nvals;
        end
        
    end
    
    methods (Static = true, Access = public)

        function [C, ia, ic] = Unique(data, nvals)
            [C, ia, ic] = unique(InfoTheory.Base2Dec(data, nvals));
            C = InfoTheory.Dec2Base(C, size(data, 2), nvals);
        end
        
        function pat = GeneratePatterns(dim, order, nvals)
            %%
            if nargin < 3
                nvals = 2;
            end
%             pat = MaxEntropyGeneral.QuickGeneratePatterns(dim, order, nvals);
%             return;
%             
%             if 2^dim * dim < 1e7 % slow and horrible
%                 pat = MaxEntropyGeneral.QuickGeneratePatterns(dim, order, nvals);
%                 return;
%             end
            % quick and dirty
            pat = [];
            for o=1:order
                pat = [pat; MaxEntropyGeneral.GeneratePatternsAux(dim, o, nvals)];
            end
            [~, idx] = sort(InfoTheory.Base2Dec(pat, nvals));
            pat = pat(idx, :);
        end
        
        function pat = QuickGeneratePatterns(dim, order, nvals)
            perms = InfoTheory.Dec2Base(1:nvals^dim-1, dim, nvals);
            pat = perms(sum(perms~=0, 2) <= order, :);
        end
        
        function pat = GeneratePatternsAux(dim, order, nvals)
            %%
            pat = zeros(nchoosek(dim, order) * (nvals - 1), dim);
            idx = 1;
            for i=1:dim-order+1
                if order == 1
                    for j=1:nvals-1
                        pat(idx, i) = j;
                        idx = idx + 1;
                    end
                else
                    curr = MaxEntropyGeneral.GeneratePatternsAux(dim-i, order-1, nvals);
                    for j=1:nvals-1
                        pat(idx:idx+size(curr, 1)-1, i) = j;
                        pat(idx:idx+size(curr, 1)-1, i+1:end) = curr;
                        idx = idx + size(curr, 1);
                    end
                end
            end
        end
        
    end
end