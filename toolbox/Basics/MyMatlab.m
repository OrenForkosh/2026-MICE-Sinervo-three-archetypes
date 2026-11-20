classdef MyMatlab
    methods (Static)
        function mypath = gitPath()
            target = "git";
            stack = dbstack('-completenames');
            mypath = MyFilename.GetPath(stack(min(2, end)).file);
            pos = regexpi(mypath, target);
            if isempty(pos)
                mypath = pwd;
                pos = regexpi(mypath, target);
            end
            if ~isempty(pos)
                mypath(pos(end) + strlength(target):end) = [];
            else
                error("couldn't find git path");
            end
        end

        function mypath = scriptPath()
            stack = dbstack('-completenames');
            mypath = MyFilename.GetPath(stack(min(2, end)).file);
        end

        function sectionName = currentSectionName()
            st = dbstack('-completenames');

            if numel(st) < 2
                sectionName = "";
                return
            end

            callerFile = st(2).file;
            callerLine = st(2).line;

            lines = splitlines(string(fileread(callerFile)));
            lines = lines(1:min(callerLine, numel(lines)));

            sectionLines = find(~cellfun(@isempty, regexp(cellstr(lines), '^\s*%%\s*(.*)$', 'once')));

            if isempty(sectionLines)
                sectionName = "";
                return
            end

            lastSectionLine = lines(sectionLines(end));
            tokens = regexp(lastSectionLine, '^\s*%%\s*(.*)$', 'tokens', 'once');

            if isempty(tokens)
                sectionName = "";
            else
                sectionName = string(tokens{1});
            end
        end
        
        function editorCloseAllFiles()
            closeNoPrompt(matlab.desktop.editor.getAll);
        end

        function [cmdWin, jTextArea] = getCommandWindow()
            % from: https://undocumentedmatlab.com/articles/setprompt-setting-matlab-desktop-prompt
            jDesktop = com.mathworks.mde.desk.MLDesktop.getInstance;
            cmdWin = jDesktop.getClient('Command Window');
            jTextArea = cmdWin.getComponent(0).getViewport.getComponent(0);
        end

        function line_count = commandWindowLineCount()
            persistent jTextArea
            if isempty(jTextArea)
                [~, jTextArea] = MyMatlab.getCommandWindow();
            end
            line_count = jTextArea.getLineCount;
        end

        function pos = commandWindowCaretPos()
            persistent jTextArea
            if isempty(jTextArea)
                [~, jTextArea] = MyMatlab.getCommandWindow();
            end
            java_pos = jTextArea.modelToView(jTextArea.getCaretPosition);
            pos = [java_pos.x, java_pos.y];
        end

        function val = isLiveScript()
            % Check if current code is within live script
            % Get the stack information
            stackInfo = dbstack('-completenames');
            % Initialize the flag
            val = false;
            % Check if the stack is not empty
            if ~isempty(stackInfo)
                % Loop through each item in the call stack
                for i = 1:length(stackInfo)
                    [~, ~, ext] = fileparts(stackInfo(i).file);
                    % Check if the file extension is '.mlx'
                    if strcmp(ext, '.mlx')
                        val = true;
                        break;
                    end
                end
            end
        end

        function loaded = loadOnce(filename, varargin)
            %LOADONCE Load a file once and reuse it while it is unchanged.
            %   S = MyMatlab.loadOnce(FILE, ...) accepts the same file and
            %   variable-selection arguments as LOAD. Results are cached by
            %   absolute file name and LOAD arguments. The cache is reused
            %   only while the file modification time (and size) match.
            %
            %   With no output, variables are assigned in the caller's
            %   workspace, matching LOAD's usual MAT-file behavior.

            persistent fileCache

            if isempty(fileCache)
                fileCache = containers.Map('KeyType', 'char', ...
                    'ValueType', 'any');
            end

            if ~(ischar(filename) && (isrow(filename) || isempty(filename))) && ...
                    ~(isstring(filename) && isscalar(filename))
                error('MyMatlab:loadOnce:InvalidFilename', ...
                    'Filename must be a character vector or string scalar.');
            end

            requestedFile = char(filename);
            resolvedFile = MyMatlab.resolveLoadFilename(requestedFile);
            fileInfo = dir(resolvedFile);
            if numel(fileInfo) ~= 1
                error('MyMatlab:loadOnce:FileInfoUnavailable', ...
                    'Could not read file information for "%s".', resolvedFile);
            end

            cacheKey = MyMatlab.loadCacheKey(resolvedFile, varargin);
            cacheIsCurrent = false;
            if isKey(fileCache, cacheKey)
                cached = fileCache(cacheKey);
                cacheIsCurrent = cached.modifiedDatenum == fileInfo.datenum && ...
                    cached.bytes == fileInfo.bytes;
            end

            if cacheIsCurrent
                loaded = cached.data;
            else
                loaded = load(resolvedFile, varargin{:});
                fileCache(cacheKey) = struct( ...
                    'modifiedDatenum', fileInfo.datenum, ...
                    'bytes', fileInfo.bytes, ...
                    'data', loaded);
            end

            if nargout == 0
                if isstruct(loaded)
                    variableNames = fieldnames(loaded);
                    for variableIndex = 1:numel(variableNames)
                        variableName = variableNames{variableIndex};
                        assignin('caller', variableName, loaded.(variableName));
                    end
                else
                    [~, variableName] = fileparts(resolvedFile);
                    variableName = matlab.lang.makeValidName(variableName);
                    assignin('caller', variableName, loaded);
                end
                clear loaded
            end
        end

        function json = toJson(obj, opts)
            % toJson__Convert any MATLAB value to a JSON string, skipping unsupported types.
            %   Unlike jsonencode, handles function_handle (converted to string),
            %   objects (converted to struct via properties), and other types that
            %   would otherwise throw an error (silently dropped).
            %
            %   Options
            %       PrettyPrint (logical, default false): Format with indentation.
            %
            %   Example
            %       s.fn = @sin; s.x = 1:3;
            %       json = MyMatlab.toJson(s)
            arguments
                obj
                opts.PrettyPrint (1,1) logical = false
            end
            sanitized = MyMatlab.sanitizeForJson(obj);
            if opts.PrettyPrint
                json = jsonencode(sanitized, PrettyPrint=true);
            else
                json = jsonencode(sanitized);
            end
        end
    end

    methods (Static, Access=private)
        function resolvedFile = resolveLoadFilename(requestedFile)
            candidates = {requestedFile};
            [~, ~, extension] = fileparts(requestedFile);
            if isempty(extension)
                candidates{end + 1} = [requestedFile '.mat'];
            end

            resolvedFile = '';
            for candidateIndex = 1:numel(candidates)
                candidate = candidates{candidateIndex};
                if isfile(candidate)
                    [success, attributes] = fileattrib(candidate);
                    if success
                        resolvedFile = attributes.Name;
                    else
                        resolvedFile = fullfile(pwd, candidate);
                    end
                    break
                end

                locatedFile = which(candidate);
                if ~isempty(locatedFile) && isfile(locatedFile)
                    resolvedFile = locatedFile;
                    break
                end
            end

            if isempty(resolvedFile)
                error('MyMatlab:loadOnce:FileNotFound', ...
                    'Unable to find file "%s".', requestedFile);
            end
        end

        function cacheKey = loadCacheKey(resolvedFile, loadArguments)
            encodedArguments = strings(1, numel(loadArguments));
            for argumentIndex = 1:numel(loadArguments)
                argument = loadArguments{argumentIndex};
                if ischar(argument) && (isrow(argument) || isempty(argument))
                    argument = string(argument);
                elseif isstring(argument) && isscalar(argument)
                    % Already in the required form.
                else
                    error('MyMatlab:loadOnce:InvalidLoadArgument', ...
                        ['LOAD arguments must be character vectors or ' ...
                        'string scalars.']);
                end
                encodedArguments(argumentIndex) = compose('%d:%s', ...
                    strlength(argument), argument);
            end
            cacheKey = char(string(resolvedFile) + "|" + ...
                strjoin(encodedArguments, "|"));
        end

        function out = sanitizeForJson(val)
            % Recursively convert val to a JSON-safe representation.
            if isa(val, 'function_handle')
                out = func2str(val);
            elseif isstruct(val)
                out = MyMatlab.sanitizeStruct(val);
            elseif iscell(val)
                out = MyMatlab.sanitizeCell(val);
            elseif istable(val)
                out = MyMatlab.sanitizeStruct(table2struct(val, 'ToScalar', true));
            elseif isobject(val)
                try
                    s = struct(val);
                    out = MyMatlab.sanitizeStruct(s);
                catch
                    try
                        props = properties(val);
                        s = struct();
                        for i = 1:numel(props)
                            s.(props{i}) = val.(props{i});
                        end
                        out = MyMatlab.sanitizeStruct(s);
                    catch
                        out = [];
                    end
                end
            elseif isnumeric(val) || islogical(val) || isstring(val) || ischar(val)
                if isnumeric(val) && ~isreal(val)
                    out = real(val);
                else
                    out = val;
                end
            else
                out = [];
            end
        end

        function out = sanitizeStruct(s)
            if numel(s) > 1
                out = arrayfun(@MyMatlab.sanitizeStruct, s);
                return
            end
            out = struct();
            fields = fieldnames(s);
            for i = 1:numel(fields)
                f = fields{i};
                sanitized = MyMatlab.sanitizeForJson(s.(f));
                if ~isempty(sanitized) || isnumeric(sanitized) || islogical(sanitized) || ischar(sanitized) || isstring(sanitized)
                    out.(f) = sanitized;
                end
            end
        end

        function out = sanitizeCell(c)
            out = cell(size(c));
            for i = 1:numel(c)
                out{i} = MyMatlab.sanitizeForJson(c{i});
            end
        end
    end
end
