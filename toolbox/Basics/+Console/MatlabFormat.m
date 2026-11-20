function str = MatlabFormat(v)
% MatlabFormat can convert data of (almost) any type to string
if ischar(v)
    v = regexprep(v, '\n', '\\n');
    v = regexprep(v, '\r', '\\r');
    v = regexprep(v, '\b', '\\b');
    str = ['''' v ''''];
    return;
end
if iscell(v)
    str = '';
    for i=1:length(v)
        if i>1
            str = sprintf('%s, %s', str, Console.MatlabFormat(v{i}));
        else
            str = Console.MatlabFormat(v{i});
        end
    end
    str = sprintf('{ %s }', str);
elseif isscalar(v)
    str = sprintf('%g', v);
elseif isvector(v)
    if isempty(v)
        str = '[]';
    else
        str = ['[' sprintf('%g, ', v(1:end-1)) sprintf('%g', v(end)) ']'];
    end
elseif ismatrix(v)
    sz = size(v);
    str = '[';
    for i=1:size(v, 1)
        if i<size(v, 1)
            suff = '; ';
        else
            suff = '';
        end
        if ndims(v) > 2 %#ok<ISMAT>
            str = [str, Console.MatlabFormat(reshape(v(i, :), sz(2:end))), suff]; %#ok<AGROW>
        else
            str = [str, Console.MatlabFormat(v(i, :)), suff]; %#ok<AGROW>
        end
    end
    str = [str, ']'];
end
