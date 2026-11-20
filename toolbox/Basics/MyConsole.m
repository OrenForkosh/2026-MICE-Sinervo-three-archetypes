classdef MyConsole < Console.Logger
    % MYCONSOLE Class for formatted console output and logging
    %   Provides static methods for printing formatted messages, handling warnings,
    %   and managing console output with indentation levels.
    %   
    % This class is a static version of the Console.Logger class
    methods (Static)
        function obj = getInstance(renew)
            arguments
                renew = false
            end
            % GETINSTANCE Access the singleton instance of the logger
            %   obj = MyConsole.getInstance() returns the singleton instance
            %   of the logger used for managing console output and warnings.
            persistent instance
            if renew || isempty(instance) || ~isvalid(instance)
                instance = Console.Logger();
            end
            obj = instance;
        end
    end

    methods (Static)
        function nchars = print(fmt, varargin, opt)
            % PRINT Print a formatted message to the console
            %   nchars = MyConsole.print(fmt, args) prints a formatted message
            %   to the console, with optional indentation and f-string parsing.
            %
            %   Optional Name-Value arguments:
            %       'level'   - Indentation level (default: 1)
            %       'wait'    - Minimum time between prints (default: 0)
            %       'endline' - Line ending character (default: newline)
            %       'fstring' - Enable f-string parsing (default: true)
            %       'stream'  - Output stream (default: 1)
            %       'raw'     - Skip the level prefix (default: false), to
            %                   continue a line an earlier call left open
            %                   with endline="", e.g.
            %                       MyConsole.print("step... ", endline="");
            %                       MyConsole.print("[done]", raw=true);
            arguments
                fmt string
            end
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = true
            end

            %% F-string parsing
            if opt.fstring
                [begi, endi] = regexp(fmt, '\{[^}]*\}');
                while ~isempty(begi)
                    fmt = replaceBetween(fmt, begi(1), endi(1), ...
                        string(evalin('caller', extractBetween(fmt, begi(1) + 1, endi(1) - 1))));
                    [begi, endi] = regexp(fmt, '\{[^}]*\}');
                end
            end

            %%
            msg = MyConsole.getInstance();
            pre_length = msg.print(fmt, varargin{:}, fstring=false);

            if nargout > 0
                nchars = pre_length;
            end
        end
        
        function nchars = disp(varargin)
            msg = MyConsole.getInstance();
            pre_length = msg.disp(varargin{:});

            if nargout > 0
                nchars = pre_length;
            end
        end

        function guard = pushLevel(opt)
            % PUSHLEVEL Increase the indent offset applied to every
            %   subsequent MyConsole.print/disp/reprint/warning/error
            %   call, so nested calls (including in subfunctions that pass
            %   their own local level=1/2/...) print one level deeper.
            %
            %   guard = MyConsole.pushLevel() is the only supported call
            %   form - the output MUST be captured. It returns an
            %   onCleanup object; assign it to a local variable and the
            %   offset is restored automatically when that variable is
            %   cleared - on normal return, break, or as the stack
            %   unwinds from a thrown error - so this nests correctly
            %   through arbitrarily many functions-within-functions with
            %   no explicit popLevel/try-catch needed:
            %       function doSomethingThatPrints()
            %           guard = MyConsole.pushLevel(); %#ok<NASGU>
            %           MyConsole.print("a sub message");
            %           anotherFunctionThatPrints(); % nests further, same way
            %       end
            %
            %   @AI: calling pushLevel() without capturing its output now
            %   throws, rather than silently pushing an offset that is
            %   never restored - that uncaught-output form used to be
            %   allowed (paired with a manual popLevel()) and is exactly
            %   what caused a real offset leak in practice.
            %
            %   Options
            %       by (double, default 1): amount to increase the offset by.
            arguments
                opt.by (1,1) double = 1
            end
            if nargout == 0
                error("MyConsole:pushLevel:UncapturedOutput", ...
                    "pushLevel() must be called with its output captured, e.g. 'guard = MyConsole.pushLevel(); ' - called as a bare statement, the offset is pushed but never automatically restored.");
            end
            msg = MyConsole.getInstance();
            guard = msg.pushLevel(by=opt.by);
        end

        function popLevel(opt)
            % POPLEVEL Undo a matching MyConsole.pushLevel() call.
            %
            %   Options
            %       by (double, default 1): amount to decrease the offset by.
            arguments
                opt.by (1,1) double = 1
            end
            msg = MyConsole.getInstance();
            msg.popLevel(by=opt.by);
        end

        function resetLevel()
            % RESETLEVEL Zero the indent offset directly.
            %   A safety valve for recovering from mismatched pushLevel/
            %   popLevel calls (e.g. a function that pushes on every call
            %   but never pops) without restarting MATLAB.
            msg = MyConsole.getInstance();
            msg.resetLevel();
        end

        function nchars = reprint(fmt, varargin, opt)
            % REPRINT Overwrite the previous console line with a new message
            %   nchars = MyConsole.reprint(fmt, args) overwrites the previous
            %   console line with a new formatted message.
            %
            %   Optional Name-Value arguments:
            %       'fstring' - Enable f-string parsing (default: true)
            arguments
                fmt string
            end
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = true
            end

            %% F-string parsing
            if opt.fstring
                [begi, endi] = regexp(fmt, '\{[^}]*\}');
                while ~isempty(begi)
                    fmt = replaceBetween(fmt, begi(1), endi(1), ...
                        string(evalin('caller', extractBetween(fmt, begi(1) + 1, endi(1) - 1))));
                    [begi, endi] = regexp(fmt, '\{[^}]*\}');
                end
            end

            %%
            msg = MyConsole.getInstance();
            pre_length = msg.reprint(fmt, varargin{:}, fstring=false);

            if nargout > 0
                nchars = pre_length;
            end
        end

        function warnOnce(varargin)
            % WARNONCE Display a warning only once for a given code location
            %   MyConsole.warnOnce(msg) displays a warning message only once
            %   per code location (file and line number).
            msg = MyConsole.getInstance();
            msg.warnOnce(varargin{:});
        end

        function warning(varargin, opt)
            % WARNING Display a warning message with stack trace information
            %   MyConsole.warning(me, fmt, args) displays a warning message
            %   with optional exception information and stack trace.
            %
            %   Optional Name-Value arguments:
            %       'wait'    - Minimum time between warnings (default: 0)
            %       'level'   - Indentation level (default: 1)
            %       'fstring' - Enable f-string parsing (default: true)
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = true
            end

            %% Process exception (if passed)
            if ~isa(varargin{1}, "MException")
                me = [];
            else
                me = varargin{1};
                varargin(1) = [];
            end

            %% Format the warning message
            try
                fmt = string(varargin{1});
                varargin(1) = [];
            catch
                fmt = "";
            end

            %% F-string parsing
            if opt.fstring
                [begi, endi] = regexp(fmt, '\{[^}]*\}');
                while ~isempty(begi)
                    fmt = replaceBetween(fmt, begi(1), endi(1), ...
                        string(evalin('caller', extractBetween(fmt, begi(1) + 1, endi(1) - 1))));
                    [begi, endi] = regexp(fmt, '\{[^}]*\}');
                end
            end    

            %%
            msg = MyConsole.getInstance();
            if isempty(me)
                msg.warning(fmt, varargin{:}, fstring=false);
            else
                msg.warning(me, fmt, varargin{:}, fstring=false);
            end
        end

        function error(varargin, opt)
            % WARNING Display a warning message with stack trace information
            %   MyConsole.warning(me, fmt, args) displays a warning message
            %   with optional exception information and stack trace.
            %
            %   Optional Name-Value arguments:
            %       'wait'    - Minimum time between warnings (default: 0)
            %       'level'   - Indentation level (default: 1)
            %       'fstring' - Enable f-string parsing (default: true)
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = true
            end

            %% Process exception (if passed)
            if ~isa(varargin{1}, "MException")
                me = [];
            else
                me = varargin{1};
                varargin(1) = [];
            end

            %% Format the warning message
            try
                fmt = string(varargin{1});
                varargin(1) = [];
            catch
                fmt = "";
            end

            %% F-string parsing
            if opt.fstring
                [begi, endi] = regexp(fmt, '\{[^}]*\}');
                while ~isempty(begi)
                    fmt = replaceBetween(fmt, begi(1), endi(1), ...
                        string(evalin('caller', extractBetween(fmt, begi(1) + 1, endi(1) - 1))));
                    [begi, endi] = regexp(fmt, '\{[^}]*\}');
                end
            end    

            %%
            msg = MyConsole.getInstance();
            if isempty(me)
                msg.error(fmt, varargin{:}, fstring=false);
            else
                msg.error(me, fmt, varargin{:}, fstring=false);
            end
        end        
    end
end
