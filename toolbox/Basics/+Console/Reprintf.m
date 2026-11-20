function n = Reprintf(varargin)
% Display text while overwriting previous text
persistent curr;
if isempty(curr)
    curr = 0;
end
if isnumeric(varargin{1})
    prev = varargin{1};
    in = varargin(2:end);
else
    if curr > 0
        prev = curr;
    else
        prev = 0;
    end
    in = varargin;
end
for i=1:prev
    fprintf('\b');
end
s = sprintf(in{:});
n = length(s);
curr = n;
s = regexprep(s, '%', '%%');
fprintf(s);
