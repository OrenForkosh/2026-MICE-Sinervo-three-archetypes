classdef MyProgress < handle
    % MYPROGRESS Class for tracking and displaying progress
    %   Provides functionality for tracking progress in serial or parallel
    %   processing, including sub-progress management.

    properties (SetAccess = private, Hidden)
        total double   % Total number of iterations
        counter = 0    % Current count of iterations
        queue = []     % Queue for parallel processing
        logger Console.Logger % Logger used for outputs (defulat: MyConsole.getInstance)

        % Progress display options
        title string   % Title of the progress
        wait duration  % Wait time between updates
        level          % Indentation level for display
        barLength      % Length of the progress bar
        starttime      % Start time of progress
        timestamp      % Timestamp for throttling updates
        postfix        % Postfix text for additional display info
        showtimes      % Flag to display remaining time estimation
        showrate       % Flag to display progress rate
        rateWindow     % Duration window for rate smoothing
        rateMinSteps   % Minimum steps before updating rate
        rateTimestamp  % Timestamp of last rate update
        rateCounter    % Counter snapshot at last rate update
        rateValue      % Cached rate (steps/s)

        % Sub-progress support
        resolution = 0 % Resolution for sub-progress
        source = []    % Reference to parent progress tracker
        notifiedParent logical = false % whether this sub already advanced its parent by one step
    end

    methods
        function self = MyProgress(total, title, opt)
            % MYPROGRESS Construct a progress tracker
            %   self = MyProgress(total, Name-Value arguments)
            %   Initializes the progress tracker with the total number of
            %   iterations and optional display settings.
            arguments
                total
                title = []
                opt.logger Console.Logger = MyConsole.getInstance
                opt.title = [];
                opt.wait duration = seconds(0.25);
                opt.level = 2;
                opt.barLength = 10;
                opt.timestamp = [];
                opt.starttime = [];
                opt.postfix string = "";
                % time display options
                opt.showtimes = true;
                % rate display options
                opt.showrate = true;
                opt.rateWindow duration = seconds(4);
                opt.rateMinSteps double = 25;
            end
            self.total = total;
            self.logger = opt.logger;
            %%
            self.title = "step";
            if ~isempty(title)
                self.title = string(title);
            end
            if ~isempty(opt.title)
                self.title = string(opt.title);
            end
            
            self.wait = opt.wait;
            self.level = opt.level;
            self.barLength = opt.barLength;
            self.timestamp = opt.timestamp;
            self.starttime = opt.starttime;
            self.postfix = opt.postfix;
            self.showtimes = opt.showtimes;
            self.showrate = opt.showrate;
            self.rateWindow = opt.rateWindow;
            self.rateMinSteps = opt.rateMinSteps;
            %%
            self.rateTimestamp = [];
            self.rateCounter = 0;
            self.rateValue = NaN;
            %%
            self.queue = parallel.pool.DataQueue;
            afterEach(self.queue, @(v) self.incrementCounter(v));
            %%
                % self.logger.reset;
            self.update(0)
        end

        function prog = sub(self, total, title)
            % SUB Create a nested progress tracker for a sub-task.
            %   prog = sub(self, total) creates a child MyProgress that
            %   shares this tracker's logger and prints one indent level
            %   deeper. When the child finishes - via done(), or its
            %   counter reaching its own total through plain update()
            %   calls - it automatically advances this (parent) tracker
            %   by one step, so completing N sub-progress cycles inside a
            %   loop of N iterations drives the parent forward without
            %   the caller ever calling update() on the parent directly.
            %
            %   prog = sub(self, total, title) also sets the child's title.
            arguments
                self
                total = 100
                title = []
            end
            prog = MyProgress(total, title, logger=self.logger, level=self.level + 1);
            prog.source = self;
        end

        % Method to update the progress bar
        function update(self, value, opt)
            % @AI: a sub-progress used to default its no-argument
            % increment to 1/self.total (its OWN total) instead of 1, so
            % without an explicit value/by, a sub would need total^2
            % calls to reach 100% - unifying this with the non-sub
            % default (a plain +1 per call) fixes that; a sub advancing
            % its own parent is now handled in incrementCounter instead.
            arguments
                self
                value = []
                opt.by = []
            end
            if ~isempty(opt.by)
                value = struct('by', opt.by);
            end
            if isempty(getCurrentJob())
                self.incrementCounter(value);  % Serial processing
            else
                send(self.queue, value);   % Parallel processing
            end
        end

        function done(self)
            self.update(inf);
        end

        % Destructor to clean up
        function delete(self)
            delete(self.queue);
        end
    end

    methods (Static)
        function demo()
            % demo__Simple demonstration of MyProgress usage, including
            %   nested sub-progress bars.
            %   Runs an outer loop of 5 steps, each driving an inner
            %   sub-progress bar of 20 steps (100 steps total, ~30
            %   seconds). Completing each inner sub-progress bar
            %   automatically advances the outer one by a single step -
            %   see sub().
            nOuter = 5;
            nInner = 20;
            outer = MyProgress(nOuter, showtimes=true, showrate=true, title="outer");
            for i = 1:nOuter
                inner = outer.sub(nInner, "inner");
                for j = 1:nInner
                    pause(0.3); % simulate work
                    inner.update();
                end
                inner.done();
            end
            outer.done();
        end
    end

    methods (Access = private)
        % Increment counter and display progress
        function incrementCounter(self, value)
            arguments
                self 
                value = [] 
            end
            if self.counter == 0 || isempty(self.starttime)
                self.starttime = tic;
            end
            if isempty(self.timestamp)
                self.timestamp = tic;
            end
            if isempty(value)
                self.counter = min(self.counter + 1, self.total);
            elseif isstruct(value)
                if isfield(value, 'value')
                    self.counter = min(value.value, self.total);
                else
                    self.counter = min(self.counter + value.by, self.total);
                end
            else
                self.counter = min(value, self.total);
            end
            %% Sub-progress: advance the parent by one step when this completes
            if ~isempty(self.source) && ~self.notifiedParent && self.counter >= self.total
                self.notifiedParent = true;
                self.source.update();
            end
            %%
            if self.counter < self.total && toc(self.starttime) > 5 && toc(self.timestamp) < 0.1
                return
            end
            self.timestamp = tic;
            %%
            ndigits = numel(num2str(prod(self.total)));
            if mod(self.counter,1) < eps
                format = ['%s %' num2str(ndigits, '%d') 'd/%d (%5.1f%%)'];
            else
                format = ['%s %' num2str(ndigits, '%d') '.2f/%d (%5.1f%%)'];
            end
            fraction = self.counter / prod(self.total);
            if self.barLength > 0
                block = flip(['█', '▉', '▊', '▋', '▌', '▍', '▎', '▏', ' '], 2);
                full = floor(fraction * self.barLength);
                if fraction < 1
                    part = floor(mod(fraction * self.barLength, 1) * (length(block) - 1)) + 1;
                else
                    part = '';
                end
                format = [format, ' [', repmat('█', 1, full), block(part), repmat(' ', 1, self.barLength - full - 1), ']'];
            end
            % @AI: the remaining-time string, rate suffix, and postfix
            % used to be spliced directly into `format` (the sprintf
            % FORMAT template) as literal text, so any of them containing
            % a literal '%' (e.g. a postfix like "loss: 5%") would break
            % the format string or be misread as a conversion specifier.
            % Each is now appended as a %s placeholder and passed as a
            % separate argument instead, so their content is inserted
            % verbatim and can never be reinterpreted as format syntax.
            extraArgs = {};
            if self.showtimes && self.counter > 0
                remaining = duration(seconds(toc(self.starttime) / self.counter * (self.total - self.counter)));
                format = append(format, ' %s');
                extraArgs{end+1} = MyString.durationToStr(remaining, compact = true);
            end
            if self.showrate && self.counter > 0
                if isempty(self.rateTimestamp)
                    self.rateTimestamp = tic;
                    self.rateCounter = self.counter;
                    self.rateValue = NaN;
                end
                elapsedRate = toc(self.rateTimestamp);
                stepDelta = self.counter - self.rateCounter;
                if elapsedRate >= seconds(self.rateWindow) % || stepDelta >= self.rateMinSteps
                    if elapsedRate > 0 && stepDelta > 0
                        self.rateValue = stepDelta / elapsedRate;
                    end
                    self.rateCounter = self.counter;
                    self.rateTimestamp = tic;
                end
                if ~isnan(self.rateValue)
                    format = append(format, ' %s');
                    if self.rateValue < 0.1
                        extraArgs{end+1} = sprintf('%.2f steps/min', self.rateValue * 60);
                    else
                        extraArgs{end+1} = sprintf('%.2f steps/s', self.rateValue);
                    end
                end
            end
            if strlength(self.postfix) > 0
                format = append(format, ": %s");
                extraArgs{end+1} = self.postfix;
            end
            % MyConsole.print(format, self.title, self.counter, prod(self.total), fraction * 100, level=self.level, endline='\012');

            if isnumeric(value) && ~isempty(value) && isinf(value)
                self.logger.reprint(format, self.title, self.total, prod(self.total), fraction * 100, extraArgs{:}, level=self.level, eventType=Console.LoggerEventTypes.PROGRESS ,index_=prod(self.total), total_=prod(self.total), wait=seconds(0));
                self.logger.newline
                % fprintf(newline);
                % MyConsole.caretPos(0);
            else
                self.logger.reprint(format, self.title, self.counter, prod(self.total), fraction * 100, extraArgs{:}, level=self.level, eventType=Console.LoggerEventTypes.PROGRESS, index_=self.counter, total_=prod(self.total));
            end
        end
    end
end
