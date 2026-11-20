function Warning(varargin)
% Warning    Show warning message.
%   Warning(me) displays the warning message in the
%   'MException' object me (including call stack)
%
%   Warning(me, format, ...) displays the warning message with the
%   header as defined in format (same as sprintf syntax)
%
%   Warning(format, ...) displays the warning message as
%   defined in format (sprintf syntax)
%%
if isa(varargin{1}, 'MException')
    %%
    err = varargin{1};
    if nargin > 1
        str = sprintf(varargin{2:end});
        Console.Red('#! %s: %s\n', str, err.message);
    else
        Console.Red('#! %s\n', err.message);
    end
    for i=1:length(err.stack)
        Console.Red('#! - <a href="matlab: opentoline(''%s'', %d)">%s (line %d)</a>\n', err.stack(i).file, err.stack(i).line, err.stack(i).name, err.stack(i).line);
    end
else
    Console.Red('#! %s\n', sprintf(varargin{:}));
end
