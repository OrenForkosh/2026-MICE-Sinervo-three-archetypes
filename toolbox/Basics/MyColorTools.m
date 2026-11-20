classdef MyColorTools
    methods (Static)
        function colors = toColormap(color, opt)
            arguments (Repeating)
                color
            end
            arguments
                opt.n = 256
                opt.flip = false
            end
            source = MyColorTools.toRGB(color{:});
            colors = nan(opt.n, 3);
            colors(round(linspace(1, opt.n, size(source, 1))), :) = source;
            colors = fillmissing(colors, 'linear');
            if opt.flip
                colors = flip(colors, 1);
            end
        end

        function show(c)
            imagesc(reshape(c, [size(c, 1), 1, 3]));
        end

        function cmap = makePalette(n, flavour)
            % MAKEPALETTE  Generate a perceptually pleasing colormap with N colors.
            %
            %   cmap = makePalette(n)
            %   cmap = makePalette(n, flavour)
            %
            %   The colormap is built in HSV space by distributing hues around the
            %   colour wheel using the golden-angle offset so that neighbouring
            %   colours are maximally distinct.  The optional FLAVOUR string controls
            %   the overall feel of the palette.
            %
            %   INPUTS
            %       n        –  number of colours (positive integer, default 256)
            %       flavour  –  string selecting the colour personality (default 'retro')
            %                    'retro'    – warm, muted, 1970s / vintage feel
            %                    'vibrant'  – bold, saturated, full-spectrum colours
            %                    'pastel'   – soft, light, candy-like tones
            %                    'neon'     – electric, high-energy, glowing colours
            %                    'earth'    – natural browns, greens, and terracotta
            %                    'jewel'    – rich, deep gemstone colours
            %                    'ocean'    – cool blues, teals, and aquamarines
            %
            %   OUTPUT
            %       cmap  –  n-by-3 matrix of RGB values in [0, 1]
            %
            %   EXAMPLES
            %       colormap(makePalette(12))                 % vibrant (default)
            %       colormap(makePalette(64, 'pastel'))       % soft pastels
            %       cmap = makePalette(8, 'retro');           % 8 vintage colours
            %       surf(peaks); colormap(makePalette(256, 'ocean')); colorbar;
            %
            %   See also HSV2RGB, COLORMAP.

            % ---- Defaults --------------------------------------------------------
            if nargin < 1 || isempty(n),       n = 256;            end
            if nargin < 2 || isempty(flavour), flavour = 'retro'; end
            validateattributes(n, {'numeric'}, {'scalar','positive','integer'});
            flavour = lower(char(flavour));

            % ---- Hue generation (shared by all flavours) -------------------------
            golden_ratio_inv = 0.6180339887;           % 1 / phi
            idx = (0:n-1)';
            t   = linspace(0, 2*pi, n)';              % smooth oscillation index

            % ---- Flavour-specific parameters -------------------------------------
            %   Each flavour defines:
            %       start_hue  – where on the colour wheel we begin
            %       hue_span   – fraction of the wheel we use (1 = full circle)
            %       sat_base / sat_amp  – saturation centre and wave amplitude
            %       val_base / val_amp  – brightness  centre and wave amplitude

            switch flavour

                case 'vibrant'
                    start_hue = 0.00;   hue_span = 1.00;
                    sat_base  = 0.82;   sat_amp  = 0.10;
                    val_base  = 0.92;   val_amp  = 0.06;

                case 'pastel'
                    start_hue = 0.00;   hue_span = 1.00;
                    sat_base  = 0.35;   sat_amp  = 0.10;
                    val_base  = 0.95;   val_amp  = 0.04;

                case 'retro'
                    start_hue = 0.02;   hue_span = 0.75;   % skip cool blues
                    sat_base  = 0.55;   sat_amp  = 0.12;
                    val_base  = 0.72;   val_amp  = 0.10;

                case 'neon'
                    start_hue = 0.00;   hue_span = 1.00;
                    sat_base  = 0.95;   sat_amp  = 0.05;
                    val_base  = 1.00;   val_amp  = 0.00;

                case 'earth'
                    start_hue = 0.02;   hue_span = 0.45;   % reds through greens
                    sat_base  = 0.50;   sat_amp  = 0.15;
                    val_base  = 0.60;   val_amp  = 0.15;

                case 'jewel'
                    start_hue = 0.00;   hue_span = 1.00;
                    sat_base  = 0.80;   sat_amp  = 0.10;
                    val_base  = 0.55;   val_amp  = 0.12;

                case 'ocean'
                    start_hue = 0.45;   hue_span = 0.30;   % teals through blues
                    sat_base  = 0.65;   sat_amp  = 0.15;
                    val_base  = 0.80;   val_amp  = 0.12;

                otherwise
                    valid = {'vibrant','pastel','retro','neon','earth','jewel','ocean'};
                    error('makePalette:badFlavour', ...
                        'Unknown flavour "%s". Choose from: %s', ...
                        flavour, strjoin(valid, ', '));
            end

            % ---- Build HSV -------------------------------------------------------
            % Golden-angle walk, but scaled to the hue_span window
            hues = mod(start_hue + idx * golden_ratio_inv * hue_span, hue_span) ...
                + start_hue;
            hues = mod(hues, 1);                       % wrap into [0, 1]

            sats = sat_base + sat_amp * sin(t);
            vals = val_base + val_amp * cos(1.5 * t);  % offset frequency for variety

            % Clamp to valid range
            sats = max(0, min(1, sats));
            vals = max(0, min(1, vals));

            % ---- Convert to RGB --------------------------------------------------
            cmap = hsv2rgb([hues, sats, vals]);

            % ---- Apply directly if no output requested ---------------------------
            if nargout == 0
                colormap(gca, cmap);
                clear cmap;
            end
        end

        function optimalTextColor = textOverlay(varargin)
            % textOverlay Determines the optimal text color (black or white)
            % for a given background color based on its relative luminance.
            %
            % Syntax:
            %   optimalTextColor = textOverlay(backgroundColor)
            %
            % Description:
            %   The function takes an RGB triplet as input representing the background color.
            %   It computes the relative luminance of the background color using the weighted
            %   RGB formula and determines whether black or white text will provide better contrast
            %   for readability.
            %
            % Input:
            %   backgroundColor - 1x3 vector containing RGB values in the range [0, 255]
            %                     representing the background color.
            %
            % Output:
            %   optimalTextColor - String, either 'Black' or 'White', representing the optimal
            %                      text color for overlaying on the given background.
            %
            % Example:
            %   backgroundColor = [120, 200, 150]; % RGB color
            %   optimalTextColor = textOverlay(backgroundColor);
            %
            %   This example computes the optimal text color for a background of RGB [120, 200, 150].
            %
            % See also: none
            backgroundColor = MyColorTools.toRGB(varargin{:});

            % Compute the relative luminance using the weighted RGB components
            luminance = 0.2126 * backgroundColor(1) + ...
                0.7152 * backgroundColor(2) + ...
                0.0722 * backgroundColor(3);

            % Determine the optimal text color based on the luminance
            if luminance > 0.5
                optimalTextColor = [0 0 0];
            else
                optimalTextColor = [1 1 1];
            end
        end


        function colors = fromHex(varargin)
            % FROMHEX Converts hexadecimal color codes to RGB vectors.
            %
            %   COLOR = FROMHEX(HEX1, HEX2, ..., HEXN) converts the hexadecimal
            %   color codes HEX1, HEX2, ..., HEXN to RGB color vectors. The output
            %   COLOR is an Nx3 matrix where N is the number of input hex codes,
            %   and each row is an RGB triplet with values in the range [0, 1].
            %
            %   Input arguments:
            %       HEX1, HEX2, ..., HEXN - Strings representing hexadecimal color
            %                               codes in the form 'RRGGBB' or '#RRGGBB'.
            %                               The function extracts the last 6
            %                               characters for conversion.
            %
            %   Output arguments:
            %       COLOR - An Nx3 matrix where each row corresponds to an RGB
            %               vector for each input hexadecimal code.
            %
            %   Example:
            %       % Convert a single hex color
            %       rgb = fromHex('#FF0000');
            %       % Output: [1 0 0]
            %
            %       % Convert multiple hex colors
            %       colors = fromHex('#FF0000', '00FF00', '#0000FF');
            %       % Output: [1 0 0; 0 1 0; 0 0 1]
            %
            %       % Convert multiple hex colors
            %       colors = fromHex(["FF0000", "00FF00", "0000FF"]);
            %       % Output: [1 0 0; 0 1 0; 0 0 1]
            %
            %   Notes:
            %       - If the input includes a '#' symbol, it will be ignored, and
            %         only the last 6 characters will be used for conversion.
            %       - The RGB values are normalized between 0 and 1.
            %
            count = 0;
            for i = 1:length(varargin)
                if ischar(varargin{i})
                    varargin{i} = string(varargin{i});
                end
                count = count + length(varargin{i});
            end
            colors = zeros(count, 3);
            idx = 1;
            for i = 1:length(varargin)
                for j = 1:length(varargin{i})
                    h = char(varargin{i}(j));
                    h = h(end-5:end);
                    colors(idx, :) = [hex2dec(h(1:2)) hex2dec(h(3:4)) hex2dec(h(5:6))] / 255;
                    idx = idx + 1;
                end
            end
        end

        function output = darken(colors, factor)
            % DARKEN Darkens an RGB color by a given factor.
            %   darkenedColor = darkenColor(colors, factor) returns a darkened version
            %   of the input RGB color. The input value 'colors' can be a
            %   matrix of size Nx3. Factor is a scalar between 0 and 1,
            %   where 1 is completely darkened (black), and 0 is no change.
            arguments
                colors
                factor = 0.25
            end
            % Ensure the factor is between 0 and 1
            factor = max(-1, min(1, factor));

            % Darken the color by scaling it towards black (0,0,0)
            hsv = rgb2hsv(colors);
            hsv(3) = hsv(3) * (1 - factor);
            hsv(2) = hsv(2) + factor * 0.5 * (1 - hsv(2));

            hsv = max(0, min(1, hsv));

            % Ensure the result is within valid RGB range [0, 1]
            output = hsv2rgb(hsv);
        end

        function rgbMatrix = toRGB(varargin)
            % toRGB Convert different color input formats to RGB values in [0, 1].
            %
            % Syntax:
            %   rgbMatrix = toRGB(colors)
            %   rgbMatrix = toRGB(color1, color2, ...)
            %
            % Description:
            %   The function accepts various types of color inputs and converts them to
            %   an Nx3 matrix where each row represents a color's RGB values in the range [0, 1].
            %   Accepted formats include:
            %     - Nx3 matrix of integers in [0, 255]
            %     - Nx3 matrix of doubles in [0, 1]
            %     - Hexadecimal color codes as strings (e.g., '#FF0000', '00FF00')
            %     - Cell arrays of hex strings
            %     - Colors passed as separate inputs
            %
            % Input:
            %   varargin - Variable number of arguments, which could include:
            %              - Nx3 matrix of RGB values (integers [0, 255] or doubles [0, 1])
            %              - Hex color code as a string or character array
            %              - Cell array of hex color codes
            %              - Separate inputs for each color
            %
            % Output:
            %   rgbMatrix - Nx3 matrix of RGB values, with each row representing a color
            %               and each value between 0 and 1.
            %
            % Example:
            %   % Example 1: Matrix of integers
            %   colors = [255 0 0; 0 255 0; 0 0 255];
            %   rgbMatrix = toRGB(colors);
            %
            %   % Example 2: Hex color codes
            %   rgbMatrix = toRGB('#FF0000', '00FF00', '#0000FF');
            %
            % See also: fromHex

            % Initialize an empty list for RGB values
            rgbMatrix = [];

            % Loop through each input
            for i = 1:length(varargin)
                inputArg = varargin{i};

                % Check if the input is a cell array (of hex strings)
                if iscell(inputArg)
                    % Call fromHex function to convert all hex values in the cell array
                    rgbMatrix = [rgbMatrix; MyColorTools.fromHex(inputArg{:})];

                    % Check if the input is a char array or string (hex color code)
                elseif ischar(inputArg) || isstring(inputArg)
                    % Call fromHex to convert the hex color to RGB values
                    rgbMatrix = [rgbMatrix; MyColorTools.fromHex(inputArg)];

                    % Check if the input is an Nx3 matrix of RGB values
                elseif isnumeric(inputArg) && size(inputArg, 2) == 3
                    % If RGB values are between 0 and 255, normalize them to [0, 1]
                    if max(inputArg(:)) > 1
                        rgbMatrix = [rgbMatrix; inputArg / 255];
                    else
                        % Already in range [0, 1], just append
                        rgbMatrix = [rgbMatrix; inputArg];
                    end

                    % Check if input is separate R, G, B values passed as different arguments
                elseif isnumeric(inputArg) && numel(inputArg) == 3
                    % Normalize values if they are in the 0-255 range
                    if max(inputArg(:)) > 1
                        rgbMatrix = [rgbMatrix; inputArg / 255];
                    else
                        rgbMatrix = [rgbMatrix; inputArg];
                    end

                else
                    error('Invalid input format. Provide Nx3 matrix, hex codes, or separate RGB values.');
                end
            end
        end
    end
end