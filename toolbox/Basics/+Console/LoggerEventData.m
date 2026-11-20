classdef LoggerEventData < event.EventData
    properties
        type Console.LoggerEventTypes
        title string
        message string
        level
        index int16
        total int16
    end
    
    methods
        function obj = LoggerEventData(type, title, message, level, index, total)
            % Constructor to initialize the properties
            obj.type = type;
            obj.title = title;
            obj.message = message;
            obj.level = level;
            obj.index = index;
            obj.total = total;
        end
    end
end
