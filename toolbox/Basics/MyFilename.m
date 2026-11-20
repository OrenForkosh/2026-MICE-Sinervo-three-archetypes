classdef MyFilename
    % MyFilename is a class that holds filenames for easy manipulation
    properties
        Path char = '.';
        Name char = '';
        Ext char = '';
    end

    properties (Dependent)
        NameAndExt
    end
    
    methods
        function val = get.NameAndExt(fname)
            val = [fname.Name fname.Ext];
        end
    end
    methods
        function obj = MyFilename(fname)
            % MyFilename Constructor
            %   MyFilename(filename) starts the class with the provided
            %   filename
            if isa(fname, 'MyFilename')
                obj = fname;
            elseif isa(fname, 'struct')
                [obj.Path, obj.Name, obj.Ext] = fileparts(fullfile(fname.folder, fname.name));
            else
                [obj.Path, obj.Name, obj.Ext] = fileparts(fname);
            end
        end
        
        function fname = Full(obj)
            % Return full filename
            if isempty(obj.Path)
                obj.Path = '.';
            end
            fname = [obj.Path filesep obj.Name obj.Ext];
        end
        
        function obj = AddPrefix(obj, prefix)
            % adds a prefix to the name of the file (between path and name)
            obj.Name = [prefix, obj.Name];
        end
        
        function obj = SetPath(obj, path)
            % Change the path of the file
            obj.Path = path;
        end

        function obj = SetName(obj, name)
            % Change the name of the file
            obj.Name = name;
        end

        function obj = SetExt(obj, ext)
            % Change the extension of the file
            obj.Ext = ext;
        end
        
        function d = CreationDate(obj)
            % Get the creation date of the file
            data = dir(obj.Full);
            d = data(1).datenum;
        end

        function is_exist = IsExist(obj)
            is_exist = isfile(obj.Full) || isfolder(obj.Full);
        end
        
    end
    
    methods (Static)
        function files = Dir(folders, opt)
            %% Dir(folders, patterns={}, wildcards={})
            %%   folders is a string or a cell list of folders to search 
            %%   patterns (optional) is a cell list of regexp patterns to match the filenames
            %%
            %% for example:
            %%      MyFilename.Dir({'c:\ls\'}, {'\.bat$'})
            arguments
                folders
                opt.patterns = {}
                opt.wildcards = {}
            end
            if ~iscell(folders)
                files = MyFilename.Dir({folders}, patterns=opt.patterns, wildcards=opt.wildcards);
                return;
            end
            %%
            wcpatterns = cellfun(@(x) ['^', x, '$'], regexprep(regexprep(regexprep(opt.wildcards, '\.', '\\.'), '\*', '.*'), '\?', '.'), 'UniformOutput', false);
            opt.patterns = [opt.patterns(:), wcpatterns(:)];
            %%
            files = [];
            for fidx = 1:length(folders)
                allfiles = dir(folders{fidx});
                if isempty(opt.patterns)
                    files = [files, allfiles];
                else
                    for pidx = 1:length(opt.patterns)
                        map = cellfun(@(x) ~isempty(x), regexp({allfiles.name}, opt.patterns{pidx}));
                        files = [files, allfiles(map)];
                    end
                end
            end            
        end

        function folder = GetPath(folder)
            folder = MyFilename(folder).Path;
        end

        function filename = ChangeExt(filename, ext)
            filename = MyFilename(filename);
            filename.SetExt(ext);
        end
        
        function EnsurePath(folder)
            if ~isfolder(folder)
                mkdir(folder);
            end
        end
        
        function varargout = subdir(varargin)
            % based on 'subdir' from Kelly Kearney
            % https://www.mathworks.com/matlabcentral/fileexchange/15859-subdir-a-recursive-file-search
            if nargin == 0
                folder = pwd;
                filter = '*';
            else
                [folder, name, ext] = fileparts(varargin{1});
                if isempty(folder)
                    folder = pwd;
                end
                if isempty(ext)
                    if isfolder(fullfile(folder, name))
                        folder = fullfile(folder, name);
                        filter = '*';
                    else
                        filter = [name ext];
                    end
                else
                    filter = [name ext];
                end
                if ~isfolder(folder)
                    error('Folder (%s) not found', folder);
                end
            end
            %---------------------------
            % Search all folders
            %---------------------------
            pathstr = MyFilename.genpathLocal_(folder);
            pathfolders = regexp(pathstr, pathsep, 'split');  % Same as strsplit without the error checking
            pathfolders = pathfolders(~cellfun('isempty', pathfolders));  % Remove any empty cells
            Files = [];
            pathandfilt = fullfile(pathfolders, filter);
            for ifolder = 1:length(pathandfilt)
                NewFiles = dir(pathandfilt{ifolder});
                if ~isempty(NewFiles)
                    fullnames = cellfun(@(a) fullfile(pathfolders{ifolder}, a), {NewFiles.name}, 'UniformOutput', false);
                    [NewFiles.name] = deal(fullnames{:});
                    Files = [Files; NewFiles];
                end
            end
            %---------------------------
            % Prune . and ..
            %---------------------------
            if ~isempty(Files)
                [~, ~, tail] = cellfun(@fileparts, {Files(:).name}, 'UniformOutput', false);
                dottest = cellfun(@(x) isempty(regexp(x, '\.+(\w+$)', 'once')), tail);
                Files(dottest & [Files(:).isdir]) = [];
            end
            %---------------------------
            % Output
            %---------------------------
            
            if nargout == 0
                if ~isempty(Files)
                    fprintf('\n');
                    fprintf('%s\n', Files.name);
                    fprintf('\n');
                end
            elseif nargout == 1
                varargout{1} = Files;
            end

        end
        
        function mypath = BasePath(opt)
            arguments
                opt.name = 'Mice';
            end
            %%
            mypath = MyFilename.ScriptPath();
            [begf, endf] = regexp(mypath, opt.name);
            if isempty(begf)
                error
            end
            mypath(endf(end) + 1:end) = [];
        end

        function mypath = ScriptPath()
            stack = dbstack('-completenames');
            mypath = MyFilename.GetPath(stack(min(2, end)).file);
        end

        function [p] = genpathLocal_(d)
            % Modified genpath that doesn't ignore:
            %     - Folders named 'private'
            %     - MATLAB class folders (folder name starts with '@')
            %     - MATLAB package folders (folder name starts with '+')
            files = dir(d);
            if isempty(files)
                return
            end
            p = '';  % Initialize output
            % Add d to the path even if it is empty.
            p = [p d pathsep];
            % Set logical vector for subdirectory entries in d
            isdir = logical(cat(1,files.isdir));
            dirs = files(isdir);  % Select only directory entries from the current listing
            for i=1:length(dirs)
                dirname = dirs(i).name;
                if    ~strcmp( dirname,'.') && ~strcmp( dirname,'..')
                    p = [p MyFilename.genpathLocal_(fullfile(d,dirname))];  % Recursive calling of this function.
                end
            end
        end
    end
end