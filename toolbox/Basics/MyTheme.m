classdef MyTheme
    properties (Constant)
        fontName = 'Assistant'

        captionFontName = MyTheme.fontName
        captionFontSize = 12
        captionFontWeight = 'normal' % 'normal' or 'bold'
        captionCapitalization = @upper

        titleFontName = MyTheme.fontName
        titleFontSize = 14

        subTitleFontSize = 12
        
        ticksFontName = MyTheme.fontName
        ticksFontSize = 10

        labelFontName = MyTheme.fontName
        labelFontSize = 12
        
        annotationFontName = MyTheme.fontName
        annotationFontSize = 12
        annotationColor = [0.15, 0.15, 0.15]

        panelBackgroundColor = [0.94,0.94,0.94]
    end
end