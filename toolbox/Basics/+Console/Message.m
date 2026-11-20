function Message(varargin)
% Display a message
styles = {@(x) Console.Bold(x), @(x) fprintf(x)};

level = max(length(dbstack)-1, 1);
if isnumeric(varargin{1})
    level = level + varargin{1};
    varargin = varargin(2:end);
end
s = sprintf(varargin{:});
fprintf('# ');
if level > 1
    fprintf([repmat(' ', 1, (level-2)*2) '- ']);
end
styles{min(level, length(styles))}(s);
Console.NewLine;
