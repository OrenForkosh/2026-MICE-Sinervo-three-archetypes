classdef MyFigure
    methods (Static)
        function mimicaxis(ax, dims)
            arguments
                ax 
                dims = [1, 2]
            end
            %%
            X = [inf -inf];
            Y = [inf -inf];
            for i = 1:length(ax)
                x = get(ax(i), 'XLim'); 
                X = [min(X(1), x(1)), max(X(2), x(2))];
                y = get(ax(i), 'YLim');
                Y = [min(Y(1), y(1)), max(Y(2), y(2))];
            end
            for i = 1:length(ax)
                if ismember(1, dims)
                    set(ax(i), 'XLim', X); 
                end
                if ismember(2, dims)
                    set(ax(i), 'YLim', Y); 
                end
            end

        end

        function fix(fig, opt)
            arguments
                fig = gcf;
                opt.nticks = 5
                opt.fontSizeMultiplier = 1
                opt.box = 'off'
            end
            %%
            function ticks = niceTicks(limits, n)
                span = limits(2) - limits(1);
                rawStep = span/(n-1);
                expo = floor(log10(rawStep));
                frac = rawStep/10^expo;
                if frac < 1.5
                    niceFrac = 1;
                elseif frac < 3
                    niceFrac = 2;
                elseif frac < 7
                    niceFrac = 5;
                else
                    niceFrac = 10;
                end
                step = niceFrac*10^expo;
                t0 = ceil(limits(1)/step)*step;
                t1 = floor(limits(2)/step)*step;
                ticks = t0:step:t1;
            end
            %%
            fig.Color = 'w';     
            %
            set(findall(fig, "-property", "FontName"), ...
                "FontName", MyTheme.fontName);            
            %%
            objs = findall(fig, 'Type', 'Axes');
            %%
            for i = 1:length(objs)
                o = objs(i);
                o.FontSizeMode = "auto";
                o.FontName = MyTheme.fontName;
                o.FontSize = MyTheme.ticksFontSize * opt.fontSizeMultiplier;
                o.LabelFontSizeMultiplier = MyTheme.labelFontSize / MyTheme.ticksFontSize * opt.fontSizeMultiplier;
                o.XLabel.FontName = MyTheme.fontName;
                o.YLabel.FontName = MyTheme.fontName;
                o.Title.FontName = MyTheme.fontName;
                o.TitleFontSizeMultiplier = MyTheme.titleFontSize / MyTheme.ticksFontSize * opt.fontSizeMultiplier;
                %%
                o.XMinorTick = 'off';
                o.YMinorTick = 'off';
                % o.TickDir = "out";
                
                %%
                % desired number of ticks
                tickCount = opt.nticks;
                ax = gca;

                % apply to x, y, and z if present
                for dim = {'X','Y','Z'}
                    if ax.([dim{1} 'TickMode']) == "auto"
                        lim = ax.([dim{1} 'Lim']);
                        ax.([dim{1} 'Tick']) = niceTicks(lim, tickCount);
                    end
                end

                % helper nested below (or put in its own file)
                
                %%
                set(o, 'Box', opt.box);
                %%
                MyFigure.addCaptions(fig);
            end
        end

        function addCaptions(fig)
            arguments
                fig = gcf;
            end
            objs = findall(fig, 'Type', 'Axes');
            %%
            prev_captions = findall(gcf, 'Tag', 'MyFigure');
            delete(prev_captions);            
            %% order axis by position
            if ~isempty(objs)
                pos = cat(1, objs.InnerPosition);
                pos(:, 2) = 1 - pos(:, 2);
                [~, order] = sortrows(round(pos(:, [2 1]) * 100));
                objs = objs(order);
            end
            %% adds captions
            for i = 1:length(objs)                
                o = objs(i);
                pos = tightPosition(o, IncludeLabels=true);
                h = annotation('textbox', [pos(1) - 0.01, pos(2) + pos(4) + 0.01, 0.01, 0.01], ...
                    'String', MyTheme.captionCapitalization(char(i + 64)), ...
                    'EdgeColor', 'none', ...
                    'FontName', MyTheme.captionFontName, ...
                    'FontSize', MyTheme.captionFontSize, ...
                    'FontWeight', MyTheme.captionFontWeight, ...
                    'VerticalAlignment', 'top', ...
                    'HorizontalAlignment', 'left' ...
                    );
                h.Tag = 'MyFigure';
            end
            %%
            % set(fig, 'SizeChangedFcn' ,@(~,~)figureCallback(yourTimer));
        end

        function vLine(pos, LineSpec, varargin)
            arguments
                pos 
                LineSpec = 'k:'
            end
            arguments (Repeating)
                varargin
            end
            h = ishold;
            hold on
            plot([pos pos], ylim, LineSpec, varargin{:});
            hold(h)
        end

        function hLine(pos, LineSpec, varargin)
            arguments
                pos 
                LineSpec = 'k:'
            end
            arguments (Repeating)
                varargin
            end
            h = ishold;
            hold on
            plot(xlim, [pos pos], LineSpec, varargin{:});
            hold(h)
        end        
        
        function t = title(str, varargin, opt)
            arguments
                str
            end
            arguments (Repeating)
                varargin 
            end
            arguments
                opt.FontName = MyTheme.titleFontName;
                opt.FontSize = MyTheme.titleFontSize;
            end
            ax = gca;
            ax.TitleFontSizeMultiplier = MyTheme.titleFontSize / MyTheme.ticksFontSize;

            t = title(str, varargin{:}, ...
                "FontName", opt.FontName ...
                );
        end

        function filename = saveSVG(fig, filename, opt)
            % saveSVG__Saves a figure as an editable SVG (live text, unsplit shapes).
            %   Thin wrapper around MySVG.save, which writes the SVG itself
            %   instead of going through MATLAB's vector export.
            %
            %   Options
            %       Background (string or RGB, default "none"): Page background;
            %           "none", "figure", or a colour.
            %
            %   Example
            %       MyFigure.saveSVG(gcf, fullfile(tempdir, "figure1.svg"));
            arguments
                fig (1,1) matlab.ui.Figure
                filename (1,1) string
                opt.Background = "none"
            end
            filename = MySVG.save(fig, filename, Background=opt.Background);
        end

        function labels(x, y, varargin, opt)
            arguments
                x  
                y 
            end
            arguments (Repeating)
                varargin 
            end
            arguments
                opt.FontName = MyTheme.labelFontName;
                opt.FontSize = MyTheme.labelFontSize();
            end
            xlabel(x, ...
                "FontName", opt.FontName, ...
                "FontSize", opt.FontSize, ...
                varargin{:});
            ylabel(y, ...
                "FontName", opt.FontName, ...
                "FontSize", opt.FontSize, ...
                varargin{:});
        end
    end
end