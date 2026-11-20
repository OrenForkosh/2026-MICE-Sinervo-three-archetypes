classdef Tables
    methods (Static = true, Hidden) 
        function by = getColumnAux(tt, by)
            % getColumnAux  Gets the column specified by 'by'.
            %   col = getColumnAux(tt, by) returns the 'by' col from 'tt.
            %   It allows to specify 'by' as a column index, column name, 
            %   table column, or vector of indices. 
            if (isnumeric(by) && isvector(by) && length(by) == size(tt, 1)) 
            elseif istable(by)
                assert(size(by, 2) == 1);
                by = by{:, 1};
            else
                by = tt{:, by};
            end            
        end
    end

    methods (Static = true)
        function ttt = accumrows(tt, by, func, opt)
            % accumrows    Simialr to Matlab's accumarray for tables. 
            % ttt = accumrows(tt, by, func, opt) runs the function 'func'
            % on each row of the table 'tt' after grouping according to
            % values in 'by'. The keys can be provided as a column index, 
            % column name, table column, or vector of indices. 
            arguments 
                tt table
                by
                func = "mean"
                %%
                opt.ignoreVariables = [];
            end
            by = Tables.getColumnAux(tt, by);
            [~, ~, idx] = unique(by, 'rows');
            ttt = [table(idx, 'VariableNames', {'idx__'}), tt];
            ttt = groupsummary(ttt, "idx__", func);
            ttt(:, [1, 2]) = [];
            ttt.Properties.VariableNames = tt.Properties.VariableNames;
            if ~isempty(opt.ignoreVariables)
                ttt(:, opt.ignoreVariables) = [];
            end
        end

        function dict = toDictionary(tt, by)
            % toDictionary    Turns a table into a dictionary.
            %   dict = toDictionary(tt, by) turns the data in table 'tt'
            %   into a dictionary according to the keys specified in 'by'.
            %   The keys can be provided as a column index, column name,
            %   table column, or vector of indices. All values in 'by' most
            %   be unique!
            %
            by = Tables.getColumnAux(tt, by);
            assert(length(unique(by)) == length(by));
            dict = dictionary(by, table2struct(tt));
        end

        function to = merge(to, src, by, opt)
            % merge  Merges two tables into one according to the 'by' column.
            %   to = merge(to, src, by, options) matches rows in 'src' to rows in
            %   'to' according to the column 'by'. Note that both tables
            %   need to have the same number of rows.
            %
            % options
            %   - IgnoreDuplicates (logical, optional): if set to true
            %   the function ignores column in 'src' with the same name in
            %   'to'.
            arguments
                to table
                src table
                by
                opt.IgnoreDuplicates = false;
            end
            %%
            [uniqueBySrc, ~, srcRows] = unique(src(:, by), 'rows');
            byToSrcRow = dictionary(srcRows, (1:size(src, 1))');
            assert(byToSrcRow.numEntries == length(srcRows));
            srcCopy = src;
            srcCopy(:, by) = [];
            %%
            [~, tgtRows] = ismember(to{:, by}, uniqueBySrc{:, :}, 'rows');
            %%
            if opt.IgnoreDuplicates
                srcCopy(:, ismember(srcCopy.Properties.VariableNames, to.Properties.VariableNames)) = [];
            end
            valid = tgtRows > 0;
            to = [to(valid, :), srcCopy(byToSrcRow(tgtRows(valid)), :)];
        end
        

        function [row, rowidx] = getRows(t, varargin)
            % returns all rows in the table that match a rule. For example
            % getRows(cars, model=tesla, year=2026)
            map = true;
            for i = 1:2:length(varargin)
                map = map & t.(varargin{i}) == varargin{i + 1};
            end
            row = t(map, :);
            if nargout > 1
                rowidx = find(map);
            end
        end

        function [row, rowidx] = getRow(t, varargin)
            % similar to getRows but ensures there is exactly one solution
            % or throws exception
            [row, rowidx] = Tables.getRows(t, varargin);
            assert(length(rowidx) == 1);
        end

        function s = IsVar(t, v)
            s = any(strcmp(t.Properties.VariableNames, v));
        end

        function t = InitIfMissing(t, v, val)
            if ~Tables.IsVar(t, v)
                if isnumeric(val)
                    t.(v) = repmat(val, size(t, 1), 1);
                else
                    t.(v) = repmat({val}, size(t, 1), 1);
                end
            end
        end
        
        function ListVariables(tt, sep)
            if nargin < 2
                sep = ', ';
            end
            for i=1:length(tt.Properties.VariableNames)
                if i>1
                    fprintf(sep);
                end
                fprintf('%s', tt.Properties.VariableNames{i});
            end
            fprintf('\n');
        end
        
        function tt = UniqueID(tt, field)
            [~, ~, tt.(field)] = unique(tt.(field));
        end
        
        function T = Sprintf(fmt, varargin)
            %%
            T = table();
            for i=1:size(varargin{1}, 1)
                %%
                line = cell(1, length(varargin));
                for j=1:length(varargin)
                    curr = varargin{j}(i);
                    if iscell(curr)
                        line{j} = curr{1};
                    else
                        line{j} = curr;
                    end
                end
                t = table({sprintf(fmt, line{:})}, 'VariableNames', {'sprintf'});
                T = [T; t];
            end
        end
        
        function Compare(t1, t2)
            %%
            map1 = ~ismember(t1.Properties.VariableNames, t2.Properties.VariableNames);
            map2 = ~ismember(t2.Properties.VariableNames, t1.Properties.VariableNames);
            fprintf('%-35s only in 1\n', t1.Properties.VariableNames{map1});
            fprintf('%-35s only in 2\n', t2.Properties.VariableNames{map2});
        end
        
        function Diff(t1, t2, key)
            if nargin < 3
                key = {};
            end
            %%
            t1name = inputname(1);
            t2name = inputname(2);
            %%
            maxlen = max(cellfun(@length, union(t1.Properties.VariableNames, t2.Properties.VariableNames)));
            %%
            tt = table({}, {}, 'VariableNames', {t1name, t2name});
            %
            in2 = ismember(t1.Properties.VariableNames, t2.Properties.VariableNames);
            not_in2 = t1.Properties.VariableNames(~in2);
            for i = 1:length(not_in2)
                idx = size(tt, 1) + 1;
                tt(idx, :) = {'-', sprintf('%s [%s]', not_in2{i}, class(t1.(not_in2{i})))};
            end
            %
            in1 = ismember(t2.Properties.VariableNames, t1.Properties.VariableNames);
            not_in1 = t2.Properties.VariableNames(~in1);
            for i = 1:length(not_in1)
                idx = size(tt, 1) + 1;
                tt(idx, :) = {'-', sprintf('%s [%s]', not_in1{i}, class(t2.(not_in1{i})))};
            end
            %
            tt
            if size(t1, 1) ~= size(t2, 1)
                fprintf('Sizes do not match (%d != %d)\n', size(t1, 1), size(t2, 1));
                if isempty(key)
                    return
                end
            end
            %%
            fixstr = @(x) sprintf(['''%-' num2str(maxlen) 's'''], x);
            fprintf('Changes:\n')
            if ~isempty(key)
                %%
                maxv = max([t1.(key); t2.(key)]);
                both = intersect(t2.Properties.VariableNames, t1.Properties.VariableNames);
                for fid = 1:length(both)
                    %%
                    try
                    field = both{fid};
                    v1 = Q.accumrows(t1.(key), t1.(field), @nanmean, nan);
                    v2 = Q.accumrows(t2.(key), t2.(field), @nanmean, nan);
                    v1(end+1:maxv) = nan;
                    v2(end+1:maxv) = nan;
                    plot(v1, v2, '.')
                    d = v1 == v2;
                    m = mean(d(~isnan(v1)));
                    if m < 1
                        fprintf(' - %s differ in %.2f%%\n', fixstr(field), (1-m) * 100)
                    end
                    catch
                        fprintf(' - did not compare %s\n', field)
                    end
                end
                
            end
            %%
            
            
            
        end
        
        function t = Append(base, newt, default)
            %%
            if nargin < 3
                default = 0;
            end
            fixed = repmat(base(1, :), size(newt,1), 1);
            fixed.Properties.RowNames = newt.Properties.RowNames;
            for i=1:length(base.Properties.VariableNames)
                name = base.Properties.VariableNames{i};
                if ~any(strcmp(newt.Properties.VariableNames, name))
                    if isfloat(base.(name))
                        newt.(name) = ones(size(newt, 1), size(base.(name), 2)) * default;
                    elseif isnumeric(base.(name))
                        newt.(name) = ones(size(newt, 1), size(base.(name), 2), class(base.(name))) * default;
                    elseif isdatetime(base.(name))
                        newt.(name) = repmat(datetime, size(newt, 1), 1);
                    else
                        newt.(name) = cell(size(newt, 1), 1);
                    end
                end
                %%newt.(name) = Tables.AuxCellToNum(newt.(name));
                %%base.(name) = Tables.AuxCellToNum(base.(name));
                if ~isa(newt.(name), class(base.(name)))
                    if isnumeric(newt.(name)) && all(isnan(newt.(name)))
                        newt.(name) = cell(size(newt, 1), 1);
                    elseif isnumeric(base.(name)) && all(isnan(base.(name)))
                        base.(name) = cell(size(base, 1), 1);
                    else
                        
                    end
                end                    
                fixed.(base.Properties.VariableNames{i}) = newt.(base.Properties.VariableNames{i});
            end
            t = [base; fixed];
        end
        
        function [col, succ] = AuxCellToNum(col)
            if ~iscell(col)
                succ = false;
                return
            end
            %%
            types = unique(cellfun(@class, col, 'UniformOutput', false));
            succ = true;
            res = zeros(length(col), 1);
            for i=1:length(col)
                if isnumeric(col{i})
                    res(i) = col{i};
                elseif isstr(col{i})
                    if isempty(col{i})
                        res(i) = nan;
                    else
                        c = str2num(col{i});
                        if isempty(c)
                            succ = false;
                            break;
                        end
                        res(i) = c;
                    end
                end
            end
            if succ
                col = res;
            end
        end
        
    end
end