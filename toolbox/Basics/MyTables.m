classdef MyTables
    methods (Static)
        function value = asDict(t, key)
            % treats table as keys and values
            assert(size(t, 2) == 2);
            assert(length(unique(t{:, 1})) == size(t,1));

            d = dictionary(t{:, 1}, t{:, 2});
            value = d(key);
        end

        function bar(t, key, value, opts)
        %bar__Bar plot of table data grouped by a key column.
        %
        %   MyTables.bar(t, key, value)
        %   MyTables.bar(t, key, value, Name=Value)
        %
        %   INPUTS
        %       t      - Input table.
        %       key    - Column name whose unique values form the x-axis groups.
        %       value  - Column to quantify.
        %                  Type="mean" : must be numeric — shows mean ± SEM.
        %                  Type="hist" : any type — shows stacked count histogram.
        %
        %   OPTIONS
        %       Secondary  - Column for within-key sub-grouping.            ("")
        %                    Creates grouped bars (mean) or grouped stacked
        %                    bars (hist) with one bar per (key, secondary) pair.
        %       Type       - "mean" (default) or "hist".                    ("mean")
        %       Legend     - Show a legend.                                 (false)
        %                    mean+secondary : secondary group names.
        %                    hist           : value-level names.
        %       Colormap     - Nx3 RGB matrix to override the default palette.  ([])
        %       ValueColors  - dictionary mapping value (or secondary-group)
        %                      names to RGB triples.  Pinned entries override
        %                      the palette; all other values use it normally.
        %                      Example: pin "Uncertain" to grey, "Sociability"
        %                      to red:
        %                        ValueColors = dictionary( ...
        %                          ["Uncertain","Sociability"], ...
        %                          {[0.6 0.6 0.6], [1 0 0]})
        %       YLabel     - Y-axis label.  Defaults to "Mean ± SEM"/"Count".("")
        %       Title      - Plot title.                                    ("")
        %
        %   NOTES
        %       key, Secondary, and value columns may be numeric, categorical,
        %       string, or cell-of-char — all are handled uniformly.

            arguments
                t                               table
                key          (1,1)  string
                value        (1,1)  string
                opts.Secondary        (1,1)  string  = ""
                opts.Type             (1,1)  string  = "mean"
                opts.Legend           (1,1)  logical = false
                opts.Colormap                double     = []
                opts.ValueColors             dictionary = dictionary()
                opts.YLabel           (1,1)  string  = ""
                opts.Title            (1,1)  string  = ""
            end

            % ---- Resolve grouping columns to string arrays --------------
            keyStrs    = mtb_toStrings(t.(key));
            uniqueKeys = unique(keyStrs, 'stable');
            nKeys      = numel(uniqueKeys);

            hasSecondary = strlength(opts.Secondary) > 0;
            if hasSecondary
                secStrs    = mtb_toStrings(t.(opts.Secondary));
                uniqueSecs = unique(secStrs, 'stable');
                nSecs      = numel(uniqueSecs);
            else
                secStrs    = repmat("", height(t), 1);
                uniqueSecs = "";
                nSecs      = 1;
            end

            % ---- Colour palette -----------------------------------------
            if ~isempty(opts.Colormap)
                palette = opts.Colormap;
            else
                try
                    palette = Colors.Default;
                catch
                    palette = lines(20);
                end
            end
            nColors = size(palette, 1);

            % ---- Dispatch -----------------------------------------------
            switch lower(opts.Type)
                case "mean"
                    if ~isnumeric(t.(value)) && ~islogical(t.(value))
                        error('MyTables:bar:nonNumericValue', ...
                              'For Type="mean" the value column must be numeric. ' + ...
                              'Column "%s" is %s.', value, class(t.(value)));
                    end
                    defaultYLabel = "Mean ± SEM";
                    mtb_plotMean(t, value, keyStrs, uniqueKeys, nKeys, ...
                                 secStrs, uniqueSecs, nSecs, hasSecondary, ...
                                 palette, nColors, opts);

                case "hist"
                    defaultYLabel = "Count";
                    mtb_plotHist(t, value, keyStrs, uniqueKeys, nKeys, ...
                                 secStrs, uniqueSecs, nSecs, hasSecondary, ...
                                 palette, nColors, opts);

                otherwise
                    error('MyTables:bar:badType', ...
                          'Type must be "mean" or "hist". Got "%s".', opts.Type);
            end

            % ---- Labels -------------------------------------------------
            ylabel(mtb_pick(opts.YLabel, defaultYLabel));
            if strlength(opts.Title) > 0
                title(opts.Title);
            end

        end

        function tbl = merge(t1, t2, key, opt)
            arguments
                t1 
                t2 
                key 
                opt.cols = [] 
            end
            %%
            
            [tf, loc] = ismember(t1{:, key}, t2{:, key});


        end

        function tbl = groupFunc(func, tbl, by, opt)
            % runs a function ('func') on the groups defined by 'by' returning a
            % table of similar size as 'tbl'
            arguments
                func 
                tbl 
                by = []
                opt.dataVars = []
                opt.group = []
            end
            if isempty(opt.dataVars)
                opt.dataVars = 1:size(tbl, 2);
            end
            if isempty(by) && isempty(opt.group)
                error('Grouping variable "by" must be specified.');
            end
            if isempty(opt.group)
                groups = findgroups(tbl.(by)); % Identify groups based on the 'by' variable
            else
                groups = opt.group;
            end
            newtable = tbl(:, opt.dataVars); % Initialize newtable with the original table
            for g = unique(groups)' % Iterate over each unique group
                for v = 1:size(newtable, 2)
                    groupData = newtable{groups == g, v}; % Extract data for the current group
                    newtable{groups == g, v} = func(groupData); % Apply the function and store results
                end
            end
            tbl(:, opt.dataVars) = newtable;
        end

        function grpd = groupStat(tbl, by, opt)
            % Similar to Matlab's grpstats but can handle non-numeric
            % columns by choosing the most common value
            arguments
                tbl 
                by 
                opt.measure = 'mean'
                opt.dataVars = []
                opt.countColName string = "Count"
                opt.ignoreFailed = false % ignore columns where the summary failed
            end
            %%
            cols_names = tbl.Properties.VariableNames;
            cols_class = cellfun(@(x) class(tbl.(x)), tbl.Properties.VariableNames, 'UniformOutput', false);
            non_numeric = struct('name', {}, 'class', {}, 'vals', {});
            count = 1;
            failed = {};
            for i = find(ismember(cols_class, ["categorical", "cell", "string"]))
                try
                    col = tbl.Properties.VariableNames{i};
                    entry = struct(...
                        'name', col, ...
                        'class', class(tbl.(col)), ...
                        'vals', [] ...
                        );
                    %
                    [vals, ~, idx] = unique(tbl.(tbl.Properties.VariableNames{i}));
                    entry.vals = vals;
                    tbl.(col) = idx;
                    non_numeric(count) = entry;
                    count = count + 1;
                catch me
                    if ~opt.ignoreFailed
                        rethrow(me)
                    end
                    failed{end+1} = col;
                end
            end
            tbl(:, failed) = [];
            cols_names(ismember(cols_names, failed)) = [];
            %%
            if isempty(opt.dataVars)
                opt.dataVars = 1:size(tbl, 2);
            end
            %% removing variables that are both in 'by' and 'dataVars'
            vars_data = tbl([], opt.dataVars).Properties.VariableNames;
            vars_by = tbl([], by).Properties.VariableNames;
            vars_data(ismember(vars_data, vars_by)) = [];

            %%
            index = 1;
            count_col_name = opt.countColName;
            while ismember(count_col_name, vars_data) || ismember(count_col_name, vars_by)
                count_col_name = sprintf('%s_%d', opt.countColName, index);
                index = index + 1;
            end
            var_names = [string(vars_by), count_col_name, string(vars_data)];
            grpd = grpstats(tbl, by, opt.measure, 'DataVars', vars_data, 'VarNames', var_names);
            modd = grpstats(tbl, by, 'mode', 'DataVars', vars_data, 'VarNames', var_names);
            
            %% correct non-numeric cols
            for i = 1:length(non_numeric)
                if ismember(non_numeric(i).name, grpd.Properties.VariableNames)
                    grpd.(non_numeric(i).name) = non_numeric(i).vals(modd.(non_numeric(i).name));
                end
            end

            %%
            grpd = grpd(:, cols_names);
        end
    end
end


% ======================================================================
%  Local helpers — visible to all MyTables methods, not to outside code
% ======================================================================

function mtb_plotMean(t, value, keyStrs, uniqueKeys, nKeys, ...
                      secStrs, uniqueSecs, nSecs, hasSecondary, ...
                      palette, nColors, opts)

    means = nan(nKeys, nSecs);
    sems  = nan(nKeys, nSecs);

    for ii = 1:nKeys
        for jj = 1:nSecs
            mask = keyStrs == uniqueKeys(ii) & secStrs == uniqueSecs(jj);
            vals = double(t.(value)(mask));
            vals = vals(~isnan(vals));
            if ~isempty(vals)
                means(ii, jj) = mean(vals);
                sems(ii, jj)  = std(vals, 0) / sqrt(numel(vals));
            end
        end
    end

    h = bar(1:nKeys, means);

    for jj = 1:nSecs
        h(jj).FaceColor = mtb_resolveColor(uniqueSecs(jj), palette, jj, opts);
        h(jj).EdgeColor = 'none';
    end

    % Overlay error bars at the exact centre of each bar
    hold on;
    for jj = 1:nSecs
        xpos = h(jj).XData + h(jj).XOffset;
        errorbar(xpos, means(:, jj)', sems(:, jj)', ...
            'Color',     [0.15 0.15 0.15], ...
            'LineStyle', 'none', ...
            'LineWidth', 1.5, ...
            'CapSize',   6);
    end
    hold off;

    xticks(1:nKeys);
    xticklabels(uniqueKeys);

    if opts.Legend && hasSecondary
        legend(h, uniqueSecs, 'Location', 'bestoutside');
    end
end


function mtb_plotHist(t, value, keyStrs, uniqueKeys, nKeys, ...
                      secStrs, uniqueSecs, nSecs, hasSecondary, ...
                      palette, nColors, opts)

    valStrs    = mtb_toStrings(t.(value));
    uniqueVals = unique(valStrs, 'stable');
    nVals      = numel(uniqueVals);

    if ~hasSecondary
        % ---- Simple stacked bar: one bar per key ------------------------
        counts = zeros(nKeys, nVals);
        for ii = 1:nKeys
            mask = keyStrs == uniqueKeys(ii);
            for vv = 1:nVals
                counts(ii, vv) = sum(mask & valStrs == uniqueVals(vv));
            end
        end

        h = bar(1:nKeys, counts, 'stacked');
        for vv = 1:nVals
            h(vv).FaceColor = mtb_resolveColor(uniqueVals(vv), palette, vv, opts);
            h(vv).EdgeColor = 'none';
        end
        xticks(1:nKeys);
        xticklabels(uniqueKeys);

    else
        % ---- Grouped stacked bar: (key, secondary) pairs ----------------
        % Mirror MATLAB's grouped-bar spacing: bars within a group are
        % centred on the integer key index, spaced barW apart.
        barW  = 0.8 / nSecs;
        nBars = nKeys * nSecs;

        xpos       = zeros(1, nBars);
        tickLabels = strings(1, nBars);
        counts     = zeros(nBars, nVals);

        for ii = 1:nKeys
            offsets = ((1:nSecs) - (nSecs + 1) / 2) * barW;
            for jj = 1:nSecs
                idx = (ii - 1) * nSecs + jj;
                xpos(idx)       = ii + offsets(jj);
                tickLabels(idx) = uniqueKeys(ii) + "–" + uniqueSecs(jj);
                mask = keyStrs == uniqueKeys(ii) & secStrs == uniqueSecs(jj);
                for vv = 1:nVals
                    counts(idx, vv) = sum(mask & valStrs == uniqueVals(vv));
                end
            end
        end

        % BarWidth=0.9 fills 90% of the within-group spacing (barW)
        h = bar(xpos, counts, 'stacked', 'BarWidth', 0.9);
        for vv = 1:nVals
            h(vv).FaceColor = mtb_resolveColor(uniqueVals(vv), palette, vv, opts);
            h(vv).EdgeColor = 'none';
        end
        xticks(xpos);
        xticklabels(tickLabels);
        xtickangle(45);
    end

    if opts.Legend
        legend(h, uniqueVals, 'Location', 'bestoutside');
    end
end


function strs = mtb_toStrings(col)
    strs = string(col(:));
end


function out = mtb_pick(user, default)
    if strlength(user) > 0
        out = user;
    else
        out = default;
    end
end


function rgb = mtb_resolveColor(label, palette, paletteIdx, opts)
    % Return the pinned color for label if one was specified, else palette fallback.
    if isConfigured(opts.ValueColors) && isKey(opts.ValueColors, string(label))
        val = opts.ValueColors(string(label));
        if iscell(val), val = val{1}; end
        rgb = val;
        return
    end
    rgb = palette(mod(paletteIdx - 1, size(palette, 1)) + 1, :);
end