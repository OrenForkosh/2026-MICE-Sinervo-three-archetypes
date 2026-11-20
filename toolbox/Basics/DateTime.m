classdef DateTime
    % DateTime Tools to work with date and time information
    methods (Static = true)
        function d = Now()
            % DateTime now
            d = now;
        end
        
        function curr = SetTime(curr, varargin)
            if isa(varargin{1}, 'datetime') || isstruct(varargin{1})
                target = varargin{1};
                curr.Hour = target.Hour;
                curr.Minute = target.Minute;
                curr.Second = target.Second;
            else
                if length(varargin) == 1
                    curr.Hour = varargin{1};
                    curr.Minute = 0;
                    curr.Second = 0;
                elseif length(varargin) == 2
                    curr.Hour = varargin{1};
                    curr.Minute = varargin{2};
                    curr.Second = 0;
                elseif length(varargin) == 3
                    curr.Hour = varargin{1};
                    curr.Minute = varargin{2};
                    curr.Second = varargin{4};
                else
                    error
                end
            end
        end
        
        function curr = ToPrevMidnight(curr, day_of_week)
            curr = dateshift(curr, 'start', 'day');
            if nargin == 2
                curr = dateshift(curr, 'dayofweek', day_of_week, 'previous');
            end
        end        
        
        function res = AddSecs(curr, dt)
            % Add specific number of seconds to object
            res = curr + DateTime.FromSecs(dt);
        end
        
        function res = FromSecs(t)
            % DateTime from seconds
            res = t / 60 / 60 / 24;
        end

        function res = FromMins(t)
            % DateTime from mins
            res = t / 60 / 24;
        end

        function res = FromHours(t)
            % DateTime from hours            
            res = t / 24;
        end
        
        function str = ToString(t, varargin)
            % DateTime to string
            if numel(t) > 1
                str = cell(size(t));
                for i=1:numel(t)
                    str{i} = datestr(t(i), varargin{:});
                end
            else
                str = datestr(t, varargin{:});
            end
        end

        function res = ToSecs(t)
            % DateTime to total number of seconds
            res = t * 60 * 60 * 24;
        end

        function res = ToFrames(t, sr)
            % DateTime to total number of frames (sr is the frame rate)
            res = (t) * 60 * 60 * 24 * (sr);
        end

        function s = SecToString(sec, sep)
            % Convert secs to string
            if nargin < 2
                sep = ':';
            end
            s = sprintf('%02d%s%02d%s%02d,%02d', floor(sec / 3600), sep, mod(floor(sec / 60), 60), sep, mod(floor(sec), 60), round((sec - floor(sec)) * 100));
        end

        function prev = Prev(t, event)
            % returns the previous event, for example last winter
            tz = t.TimeZone;
            ttype = 'season';
            switch lower(event)
                case 'winter' % since winter solstice
                    M = 12;
                    D = 21;
                case 'summer' % since winter solstice
                    M = 6;
                    D = 21;
                case 'autumn' % since winter solstice
                    M = 9;
                    D = 23;
                case 'spring' % since winter solstice
                    M = 3;
                    D = 20;
                otherwise error;
            end
            ref = datetime(year(t), M, D, 'TimeZone', tz);
            if t >= ref
                prev = ref;
            else
                prev = datetime(year(t) - 1, M, D, 'TimeZone', tz);
            end
        end

        function next = Next(t, event)
            % returns the previous event, for example last winter
            tz = t.TimeZone;
            ttype = 'season';
            switch lower(event)
                case 'winter' % since winter solstice
                    M = 12;
                    D = 21;
                case 'summer' % since winter solstice
                    M = 6;
                    D = 21;
                case 'autumn' % since winter solstice
                    M = 9;
                    D = 23;
                case 'spring' % since winter solstice
                    M = 3;
                    D = 20;
                otherwise error;
            end
            ref = datetime(year(t), M, D, 'TimeZone', tz);
            if t <= ref
                next = ref;
            else
                next = datetime(year(t) + 1, M, D, 'TimeZone', tz);
            end
        end

        function map = IsWinter(t)
            tz = t.TimeZone;
            beg = datetime(year(t), 12, 21, 'TimeZone', tz);
            fin = datetime(year(t), 12, 31, 'TimeZone', tz);
            map = isbetween(t, beg, fin, 'closed');

            beg = datetime(year(t), 1, 1, 'TimeZone', tz);
            fin = datetime(year(t), 3, 20, 'TimeZone', tz);
            map = map | isbetween(t, beg, fin, 'closed');
        end

        function map = IsSummer(t)
            tz = t.TimeZone;
            beg = datetime(year(t), 6, 21, 'TimeZone', tz);
            fin = datetime(year(t), 9, 23, 'TimeZone', tz);
            map = isbetween(t, beg, fin, 'openright');
        end

        function map = IsAutumn(t)
            tz = t.TimeZone;
            beg = datetime(year(t), 9, 23, 'TimeZone', tz);
            fin = datetime(year(t), 12, 21, 'TimeZone', tz);
            map = isbetween(t, beg, fin, 'openright');
        end

        function map = IsSpring(t)
            tz = t.TimeZone;
            beg = datetime(year(t), 3, 20, 'TimeZone', tz);
            fin = datetime(year(t), 6, 21, 'TimeZone', tz);
            map = isbetween(t, beg, fin, 'openright');
        end

        function season = Season(t)
            season = zeros(length(t), 1);
            season(DateTime.IsWinter(t)) = 1;
            season(DateTime.IsSpring(t)) = 2;
            season(DateTime.IsSummer(t)) = 3;
            season(DateTime.IsAutumn(t)) = 4;
            assert(all(season > 0));
        end
    end
end
