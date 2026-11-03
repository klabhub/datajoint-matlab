classdef Diagram < dj.ERD
    methods
        function self = Diagram(connection,nodes)
            self@dj.ERD();
            self.conn = connection;
            self.nodes = nodes;
        end
    end
end
