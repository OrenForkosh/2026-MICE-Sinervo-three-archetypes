classdef Logger < handle
    % LOGGER Class for formatted console output and logging
    %   Provides methods for printing formatted messages, handling warnings,
    %   managing console output, and raising events.

    properties (Hidden)
        previousWarnings = {}
        caretPos = 0
        levelOffset (1,1) double = 0 % cumulative indent set via pushLevel/popLevel; added to every print/warning/error/disp/reprint level
    end

    % Define events for capturing outputs
    events
        OutputIssued
    end

    properties (Access=protected, Transient)
        timestamp
    end

    methods
        function nchars = print(self, fmt, varargin, opt)
            % PRINT Print a formatted message to the console
            %   nchars = print(self, fmt, args, Name-Value arguments)
            %   Formats and prints a message to the console with optional
            %   f-string parsing, indentation, and event triggering.
            %
            %   Name-Value arguments:
            %       'level'   - Indentation level (default: 1). The
            %                   cumulative offset set via pushLevel/
            %                   popLevel is added to this value.
            %       'wait'    - Minimum time between prints (default: 0 seconds)
            %       'endline' - Line ending character (default: newline)
            %       'fstring' - Enable f-string parsing (default: true)
            %       'stream'  - Output stream (default: 1 for stdout)
            %       'eventType' - Type of event to trigger (default: Print)
            %       'raw'     - Skip the level prefix (default: false).
            %                   For continuing a line an earlier print(...,
            %                   endline="") left open, e.g.
            %                       print("step... ", endline="");
            %                       print("[done]", raw=true);
            %                   without 'raw', the second call would inject
            %                   its own indent prefix mid-line instead of
            %                   continuing flush against the first.
            arguments
                self Console.Logger
                fmt string
            end
            arguments (Repeating)
                varargin
            end
            arguments
                opt.level (1,1) double = 1
                opt.wait duration = seconds(0)
                opt.endline string = newline
                opt.fstring (1,1) logical = true
                opt.stream (1,1) double = 1
                opt.title string = ""
                opt.eventType Console.LoggerEventTypes = Console.LoggerEventTypes.PRINT
                opt.raw (1,1) logical = false
                %% private
                opt.index_ = []
                opt.total_ = []
            end

            %% Handle waiting
            if opt.wait > 0
                if ~isempty(self.timestamp) && toc(self.timestamp) < seconds(opt.wait)
                    return
                end
                self.timestamp = tic;
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

            %% Clear caret if reprinting
            if self.caretPos > 0
                self.newline(opt.endline);
                self.caretPos = 0;
            end

            %% Apply the cumulative indent set via pushLevel/popLevel
            level = opt.level + self.levelOffset;

            %% Format and print the message
            if opt.stream > 0
                str = sprintf(fmt, varargin{:});
                if opt.raw
                    prefix = "";
                else
                    prefix = Console.Logger.prefix(level);
                end
                message = regexprep(prefix + str, '%', '%%') + opt.endline;
                nchars_ = fprintf(opt.stream, message);
            else
                message = fmt;
                self.mydisp(message);
                nchars_ = strlength(message);
            end

            %% Trigger OutputIssued event
            notify(self, 'OutputIssued', Console.LoggerEventData(opt.eventType, opt.title, message, level, opt.index_, opt.total_));

            if nargout > 0
                nchars = nchars_;
            end
        end

        function nchars = disp(self, varargin)
            if nargout > 0
                nchars = self.print(varargin{:}, fstring=false, stream=0);
            else
                self.print(varargin{:}, fstring=false, stream=0);
            end
        end

        function newline(self, chr)
            % @AI: was `newline(~, chr)`, discarding self via ~ while the
            % body referenced self.caretPos - calling this (directly, or
            % via print()'s own "clear caret if reprinting" branch, hit
            % whenever a plain print runs right after a reprint left the
            % caret mid-line, and by MyProgress.done()) threw "Undefined
            % function or variable 'self'" every time.
            arguments
                self
                chr = newline
            end
            self.caretPos = 0;
            fprintf(chr);
        end

        function clearline(self)
            fprintf(repmat('\b', 1, self.caretPos));
            self.caretPos = 0;
        end

        function reset(self)
            self.caretPos = 0;
        end

        function guard = pushLevel(self, opt)
            % PUSHLEVEL Increase the indent offset applied to every
            %   subsequent print/disp/reprint/warning/error call (by
            %   default, callers still just pass their own local
            %   level=1/2/3/... - pushLevel shifts that whole subtree
            %   deeper without the callee needing to know how deep its
            %   caller already is).
            %
            %   guard = pushLevel(self) is the only supported call form -
            %   the output MUST be captured. It returns an onCleanup
            %   object; assigning it to a local variable restores the
            %   offset automatically whenever that variable is cleared -
            %   on normal function return, on break/return, or as the
            %   stack unwinds from a thrown error - so nesting stays
            %   correct through "essentially infinite" levels of
            %   subfunctions without any manual bookkeeping:
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
                self Console.Logger
                opt.by (1,1) double = 1
            end
            if nargout == 0
                error("Console:Logger:pushLevel:UncapturedOutput", ...
                    "pushLevel() must be called with its output captured, e.g. 'guard = ...pushLevel();' - called as a bare statement, the offset is pushed but never automatically restored.");
            end
            self.levelOffset = self.levelOffset + opt.by;
            guard = onCleanup(@() self.popLevel(by=opt.by));
        end

        function popLevel(self, opt)
            % POPLEVEL Undo a matching pushLevel(self) call.
            %
            %   Options
            %       by (double, default 1): amount to decrease the offset by.
            arguments
                self Console.Logger
                opt.by (1,1) double = 1
            end
            self.levelOffset = max(0, self.levelOffset - opt.by);
        end

        function resetLevel(self)
            % RESETLEVEL Zero the indent offset directly.
            %   A safety valve for recovering from mismatched pushLevel/
            %   popLevel calls (e.g. a function that pushes on every call
            %   but never pops) without restarting MATLAB.
            self.levelOffset = 0;
        end

        function nchars = reprint(self, fmt, varargin, opt)
            % REPRINT Overwrite the previous console line with a new message
            %   nchars = MyConsole.reprint(fmt, args) overwrites the previous
            %   console line with a new formatted message.
            %
            %   Optional Name-Value arguments:
            %       'level'   - Indentation level (default: 1)
            %       'fstring' - Enable f-string parsing (default: false)
            arguments
                self
                fmt string
            end
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = false % to increase speed
                opt.wait duration = seconds(0.1)
                %% protected
                opt.index_ int16 = []
                opt.total_ int16 = []
                opt.eventType Console.LoggerEventTypes = Console.LoggerEventTypes.REPRINT
            end

            %%
            if opt.wait > 0
                if ~isempty(self.timestamp) && toc(self.timestamp) < seconds(opt.wait)
                    return
                end
                self.timestamp = tic;
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

            %% Clear the previous line
            self.clearline;

            %% Print the new message
            pre_length = self.print(fmt, varargin{:}, endline="", eventType=opt.eventType, index_=opt.index_, total_=opt.total_);
            self.caretPos = pre_length;
            if nargout > 0
                nchars = pre_length;
            end
        end        

        function warnOnce(self, varargin)
            % WARNONCE Display a warning only once for a given code location
            %   Tracks the code location of warnings to ensure they are only 
            %   issued once.
            stack = dbstack;
            id = strcat(stack(end-1).file, '|', stack(end-1).name, '|', num2str(stack(end-1).line));
            if isempty(self.previousWarnings)
                self.previousWarnings = {};
            end
            if ~ismember(id, self.previousWarnings)
                self.previousWarnings{end + 1} = id;
                self.warning(varargin{:});
            end
        end

        function error(self, varargin, opt)
            % ERROR Display an error message with optional stack trace
            %   Handles exceptions or formatted error messages and prints them.
            %
            % See CONSOLE.PRINT for full list all arguments
            arguments
                self Console.Logger
            end
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = true
            end

            % Process exception (if passed)
            if ~isa(varargin{1}, "MException")
                me = [];
            else
                me = varargin{1};
                varargin(1) = [];
            end

            % Format the warning message
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
            warn = MyString.exceptionToStr(me, type="ERROR", title=sprintf(fmt, varargin{:}));
            self.print(warn, stream=2, eventType=Console.LoggerEventTypes.ERROR);
        end

        function warning(self, varargin, opt)
            % WARNING Display a warning message with stack trace information
            %   Formats a warning message and prints it to the console.
            %
            % See CONSOLE.PRINT for full list all arguments
            arguments
                self Console.Logger
            end
            arguments (Repeating)
                varargin
            end
            arguments
                opt.fstring (1,1) logical = true
            end

            % Process exception (if passed)
            if ~isa(varargin{1}, "MException")
                me = [];
            else
                me = varargin{1};
                varargin(1) = [];
            end

            % Format the warning message
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
            warn = MyString.exceptionToStr(me, type="WARNING", title=sprintf(fmt, varargin{:}));
            self.print(warn, stream=2, eventType=Console.LoggerEventTypes.WARNING);
        end
    end

    methods (Access=private)
        function mydisp(~, x)
            arguments
                ~ 
                x %#ok<INUSA>
            end
            %MYDISP A disp-like function implemented with fprintf

            % Capture MATLAB's disp output and trim leading/trailing whitespace
            txt = strtrim(evalc('disp(x)'));

            % Print using fprintf
            fprintf('%s\n', txt);
        end

    end

    methods (Static, Hidden)
        function str = prefix(level)
            % PREFIX Generate indentation prefix based on level
            switch level
                case 0
                    str = "";
                case 1
                    str = "";
                case 2
                    str = " - ";
                otherwise
                    % @AI: repmat on a scalar *string* tiles it into an
                    % array of repeated elements, not one repeated/tiled
                    % string - so for level >= 4 (level-2 >= 2) this used
                    % to hand fprintf a non-scalar string as its format
                    % argument, which fails with "Invalid format". Levels
                    % <=3 happened to work by coincidence: level-2 is 0 or
                    % 1, and repmat(...,1,1) degenerates to a scalar.
                    % join() concatenates the repeated elements into one
                    % scalar string.
                    str = " " + join(repmat("  ", 1, level - 2), "") + ". ";
            end
        end
    end
end
