classdef Master < handle
    % mix-in class for dj.Relvar classes to make them process parts in a
    % master/part relationship.
    
    methods
        function list = getParts(self)
            % find classnames that begin with me and are dj.Part
            info = meta.class.fromName(class(self));
            classNames = {info.ContainingPackage.ClassList.Name};  
            match = ~cellfun(@isempty,regexp(classNames,['\<' class(self) '[A-Z]+'],"start"));    
            % Part tables always have to be in the same database as the
            % Master: pass self.dbName
            list = cellfun(@(x)feval(x,self.dbName),classNames(match) , 'uni', false);
            list = list(cellfun(@(x) isa(x, 'dj.Part'), list));
        end
    end
end
