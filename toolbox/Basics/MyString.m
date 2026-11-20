classdef MyString
    % MYSTRING A utility class for string and exception handling.
    %   This class provides methods for converting camelCase to readable text,
    %   formatting exceptions as strings, generating hyperlinks, and displaying
    %   hierarchical structures (structs or objects) in a tree-like format.

    methods (Static)
        function str = toString(data, opt)
            % Format can convert data of (almost) any type to string
            arguments
                data
                opt.separator = ' ';
            end
            if isstring(data)
                data = char(data);
            end
            if ischar(data)
                data = regexprep(data, '\n', '\\n');
                data = regexprep(data, '\r', '\\r');
                data = regexprep(data, '\b', '\\b');
                str = ['"' data '"'];
                return;
            end
            if isstruct(data)
                f = fields(data);
                str = ['{' opt.separator];
                for i = 1:length(f)
                    str = [str sprintf('"%s": %s', f{i}, Strings.toString(data.(f{i})))];
                    if i < length(f)
                        str = [str, ','];
                    end
                    str = [str, opt.separator];
                end
                str = [str '}' opt.separator];
            elseif isscalar(data)
                str = sprintf('%g', data);
            elseif iscell(data)
                str = '';
                for i=1:length(data)
                    if i>1
                        str = sprintf('%s, %s', str, Console.Format(data{i}));
                    else
                        str = Console.Format(data{i});
                    end
                end
                str = sprintf('{ %s }', str);
            elseif isvector(data)
                if isempty(data)
                    str = '[]';
                else
                    str = ['[' sprintf('%g, ', data(1:end-1)) sprintf('%g', data(end)) ']'];
                end
            elseif ismatrix(data)
                sz = size(data);
                str = '[';
                for i=1:size(data, 1)
                    if i<size(data, 1)
                        suff = ', ';
                    else
                        suff = '';
                    end
                    if ndims(data) > 2 %#ok<ISMAT>
                        str = [str, Console.Format(reshape(data(i, :), sz(2:end))), suff]; %#ok<AGROW>
                    else
                        str = [str, Console.Format(data(i, :)), suff]; %#ok<AGROW>
                    end
                end
                str = [str, ']'];
            end
        end
        function str = f(str)
            % F Parses f-style strings. 
            % 
            % Note! This code can't be nested in another function 
            % (becuase of how evalin works). Instead, copy this code in
            % full.
            %
            % EXAMPLE:
            %   a = "world";
            %   fprintf(MyString.f("hello {a}"));
            [begi, endi] = regexp(str, '\{[^}]*\}');
            while ~isempty(begi)
                str = replaceBetween(str, begi(1), endi(1), ...
                    string(evalin('caller', extractBetween(str, begi(1) + 1, endi(1) - 1))));
                [begi, endi] = regexp(str, '\{[^}]*\}');
            end            
        end

        function str = camelCaseToStr(str)
            % CAMELCASETOSTR Convert camelCase string to readable text.
            %   text = MyString.camelCaseToText(str) converts a camelCase
            %   string into a readable format by adding spaces before capital letters.
            %
            % INPUT:
            %   str - (char or string) A camelCase formatted string.
            %
            % OUTPUT:
            %   text - (string) A readable string with spaces before capital letters.
            %
            % EXAMPLE:
            %   text = MyString.camelCaseToStr('camelCaseString');
            %   % text = 'camel Case String'
            str = regexprep(str, '(.)([A-Z])', '$1 $2');
        end

        function str = exceptionToStr(me, opt)
            % EXCEPTIONTOSTR Convert an exception to a formatted string.
            %   str = MyString.exceptionToStr(me, type) converts an
            %   MException object to a formatted string, optionally
            %   including a specified type (e.g., "ERROR").
            %
            % INPUTS:
            %   me    - (MException) The exception object.
            %   type  - (string, optional) A label for the exception type.
            %           Default is "ERROR".
            %   title - (string, optional) A title to provide for the
            %   message
            %
            % OUTPUT:
            %   str - (string) A formatted string with exception details.
            %
            % EXAMPLE:
            %   try
            %       error('Test:ID', 'An error occurred.');
            %   catch me
            %       disp(MyString.exceptionToStr(me));
            %   end
            arguments
                me = []
                opt.type string = "ERROR"
                opt.title string = ""
            end

            if ~isempty(me)
                if isa(me, 'MException')
                    stack = string(me.message) + " [" + me.identifier + "] | Stack: " + MyString.stackToStr(me.stack);
                else
                    try
                        stack = "Stack: " + MyString.stackToStr(me);
                    catch
                        stack = "";
                    end
                end
            else
                stack = "";
            end

            if strlength(opt.title) > 0
                title = opt.title;
            else
                title = "";
            end

            if strlength(opt.type) > 0
                str = opt.type;
                if strlength(title) > 0 || strlength(stack) > 0
                    str = str + ": ";
                end
            else
                str = "";
            end
            str = str + title;
            if strlength(stack) > 0
                if strlength(title) > 0
                    str = str + " | " + stack;
                else
                    str = str + stack;
                end
            end
        end

        function str = stackToStr(stack)
            % STACKTOSTR Generate a string representation of a stack trace.
            %   str = MyString.stackToStr(stack) generates a string containing
            %   hyperlinks for each stack frame in the provided stack trace.
            %
            % INPUT:
            %   stack - (struct array) The stack trace, as returned by an
            %           MException object.
            %
            % OUTPUT:
            %   str - (string) A string representation of the stack trace
            %         with hyperlinks.
            %
            % EXAMPLE:
            %   try
            %       error('Test:ID', 'An error occurred.');
            %   catch me
            %       disp(MyString.stackToStr(me.stack));
            %   end
            str = "[";
            for i = 1:length(stack)
                filename = stack(i).file;
                [~, base, ext] = fileparts(stack(1).file);
                short = [base, ext];
                if isempty(which(filename))
                    filename = which(filename);
                end
                link = MyString.createLink(sprintf('%s:%d:%s', ...
                    short, stack(i).line, stack(i).name), ...
                    filename, stack(i).line);
                str = str + link;
                if i < length(stack)
                    str = str + " > ";
                end
            end
            str = str + "]";
        end

        function output = createLink(message, target, varargin)
            % CREATELINK Create a formatted hyperlink.
            %   output = MyString.createLink(message, target) creates a hyperlink
            %   with the specified message and target. The target can be a
            %   folder, file, or MATLAB function handle.
            %
            % INPUTS:
            %   message - (char or string) The link's display text.
            %   target  - (char or string) The link's target (e.g., file path).
            %   varargin - (optional) Additional arguments (e.g., line number for files).
            %
            % OUTPUT:
            %   output - (char) A formatted hyperlink.
            %
            % EXAMPLE:
            %   link = MyString.createLink('Open File', 'example.m', 10);
            %   disp(link);
            if nargin == 1
                target = message;
                message = 'link';
            end
            if isfolder(target)
                output = sprintf('<a href="matlab:system(''open %s'')">%s</a>', target, message);
            elseif ishandle(target)
                error('Not implemented yet for function handles.');
            else
                [~, ~, ext] = fileparts(target);
                if isfile(target) && strcmp(ext, '.m')
                    if ~isempty(varargin)
                        output = sprintf('<a href="matlab:opentoline(''%s'', %d)">%s</a>', target, varargin{1}, message);
                    else
                        output = sprintf('<a href="matlab:opentoline(''%s'', %d)">%s</a>', target, 0, message);
                    end
                else
                    output = sprintf('<a href="matlab:system(''open %s'')">%s</a>', target, message);
                end
            end
        end    

        function str = durationToStr(timeInput, opt)
            % durationToStr - Convert duration to a formatted string.
            %
            % Input:
            % - timeInput: Duration object or numeric value (in seconds).
            % - compact: Logical (true/false). If true, use hh:mm:ss style.
            %
            % Output:
            % - str: The formatted string representation of the duration.

            arguments
                timeInput
                opt.compact (1,1) logical = false
            end

            % Extract total seconds for custom formatting
            if ~isnumeric(timeInput)
                totalSeconds = seconds(timeInput);
            end

            if opt.compact
                % Compact format: hh:mm:ss, mm:ss, or ss
                if totalSeconds < 3600
                    minutes = floor(totalSeconds / 60);
                    secs = mod(totalSeconds, 60);
                    str = sprintf('%02d:%02d', minutes, round(secs)); % mm:ss
                else
                    hours = floor(totalSeconds / 3600);
                    remainingSeconds = mod(totalSeconds, 3600);
                    minutes = floor(remainingSeconds / 60);
                    secs = mod(remainingSeconds, 60);
                    str = sprintf('%02d:%02d:%02d', hours, minutes, round(secs)); % hh:mm:ss
                end
            else
                % Descriptive format
                if totalSeconds < 60
                    str = sprintf('%d seconds', round(totalSeconds));
                elseif totalSeconds < 3600
                    minutes = floor(totalSeconds / 60);
                    secs = mod(totalSeconds, 60);
                    str = sprintf('%d minutes, %d seconds', minutes, round(secs));
                elseif totalSeconds < 86400
                    hours = floor(totalSeconds / 3600);
                    remainingSeconds = mod(totalSeconds, 3600);
                    minutes = floor(remainingSeconds / 60);
                    secs = mod(remainingSeconds, 60);
                    str = sprintf('%d hours, %d minutes, %d seconds', hours, minutes, round(secs));
                else
                    days = floor(totalSeconds / 86400);
                    remainingSeconds = mod(totalSeconds, 86400);
                    hours = floor(remainingSeconds / 3600);
                    minutes = floor(mod(remainingSeconds, 3600) / 60);
                    str = sprintf('%d days, %d hours, %d minutes', days, hours, minutes);
                end
            end
        end




        function structToTree(obj, opt)
            % STRUCTTOTREE Display a struct or class in a tree-like format.
            %   struct2tree(obj, 'EnableRemarks', true) displays a struct or
            %   class object and its properties/fields in a hierarchical format,
            %   optionally including spaces for remarks.
            %
            % INPUT:
            %   obj - The struct or object to display.
            %
            % OPTIONAL NAME-VALUE ARGUMENTS:
            %   'EnableRemarks' - (logical) Include space for remarks.
            %                     Default: true.
            %
            % EXAMPLE:
            %   myStruct = struct('field1', 1, 'field2', struct('subfield', 'value'));
            %   MyString.structToTree(myStruct, "EnableRemarks", true);
            arguments
                obj
            end
            arguments
                opt.enableRemarks = true
            end
            
            % Start recursive display
            displayTreeRecursive(obj, '', '', enableRemarks);

            % Nested function for recursive tree display
            function displayTreeRecursive(obj, indent, branch, enableRemarks)
                remarkSpacing = 50; % Fixed distance for remarks

                if isstruct(obj)
                    % Handle struct fields
                    fields = fieldnames(obj);
                    numFields = numel(fields);
                    for i = 1:numFields
                        fieldName = fields{i};
                        fieldValue = obj.(fieldName);
                        isLastField = (i == numFields);

                        % Determine tree branch style
                        if isLastField
                            newBranch = [branch '└── '];
                            newIndent = [branch '    '];
                        else
                            newBranch = [branch '├── '];
                            newIndent = [branch '│   '];
                        end

                        if isstruct(fieldValue)
                            fprintf('%s%s:\n', newBranch, fieldName);
                            displayTreeRecursive(fieldValue, newIndent, newIndent, enableRemarks);
                        else
                            displayField(fieldName, fieldValue, newBranch, enableRemarks, remarkSpacing);
                        end
                    end
                elseif isobject(obj)
                    % Handle class properties using reflection
                    metaInfo = metaclass(obj);
                    properties = metaInfo.PropertyList;
                    numProperties = numel(properties);

                    for i = 1:numProperties
                        property = properties(i);
                        propertyName = property.Name;
                        if ~property.Hidden && property.HasDefault
                            propertyValue = obj.(propertyName);
                        else
                            propertyValue = '<Hidden or Undefined>';
                        end
                        isLastProperty = (i == numProperties);

                        % Determine tree branch style
                        if isLastProperty
                            newBranch = [branch '└── '];
                            newIndent = [branch '    '];
                        else
                            newBranch = [branch '├── '];
                            newIndent = [branch '│   '];
                        end

                        if isstruct(propertyValue) || isobject(propertyValue)
                            fprintf('%s%s:\n', newBranch, propertyName);
                            displayTreeRecursive(propertyValue, newIndent, newIndent, enableRemarks);
                        else
                            displayField(propertyName, propertyValue, newBranch, enableRemarks, remarkSpacing);
                        end
                    end
                else
                    % Handle other cases
                    fprintf('%s%s\n', branch, formatValue(obj));
                end
            end

            % Nested function to display individual fields/properties
            function displayField(name, value, branch, enableRemarks, spacing)
                formattedValue = formatValue(value);
                line = sprintf('%s%s: %s', branch, name, formattedValue);

                if enableRemarks
                    padding = max(0, spacing - numel(line));
                    remarkSpace = repmat(' ', 1, padding);
                    fprintf('%s%s%% \n', line, remarkSpace);
                else
                    fprintf('%s\n', line);
                end
            end

            % Nested function to format values for display
            function valueStr = formatValue(value)
                if isnumeric(value) || islogical(value)
                    valueStr = mat2str(value);
                elseif ischar(value)
                    valueStr = ['"' value '"'];
                elseif iscell(value)
                    valueStr = 'Cell Array';
                elseif isobject(value)
                    valueStr = sprintf('<%s Object>', class(value));
                else
                    valueStr = class(value);
                end
            end
        end


        function str = toTitleCase(str, opts)
            % toTitleCase__Convert a string to title case.
            %   Capitalises the first letter of every whitespace-delimited word
            %   and lowercases the rest.  Short function words (articles,
            %   conjunctions, prepositions) are left lowercase unless they
            %   appear at the first position.
            %
            %   Options
            %       SmartCase  (logical, default true): Skip capitalisation of
            %                  common function words (a, an, the, and, …).
            %       SkipWords  (string array): Override the built-in skip list.
            %
            %   Example
            %       MyString.toTitleCase("the quick brown fox")
            %           % -> "The Quick Brown Fox"
            %       MyString.toTitleCase("war and peace")
            %           % -> "War and Peace"
            %       MyString.toTitleCase("war and peace", SmartCase=false)
            %           % -> "War And Peace"
            %       MyString.toTitleCase(["war and peace", "the godfather"])
            %           % -> ["War and Peace", "The Godfather"]
            arguments
                str       (:,:) string
                opts.SmartCase (1,1) logical = true
                opts.SkipWords (1,:) string  = [ ...
                    "a", "an", "the", ...
                    "and", "but", "or", "nor", "for", "so", "yet", ...
                    "at", "by", "in", "of", "on", "to", "up", "as"]
            end

            for k = 1:numel(str)
                words = strsplit(str(k));
                for i = 1:numel(words)
                    w = words{i};
                    if strlength(w) == 0
                        continue
                    end
                    isFirst = (i == 1);
                    if opts.SmartCase && ~isFirst && any(lower(w) == opts.SkipWords)
                        words(i) = lower(w);
                    else
                        words(i) = string(upper(extractBefore(w, 2))) + string(lower(extractAfter(w, 1)));
                    end
                end
                str(k) = strjoin(words);
            end
        end

    end
end