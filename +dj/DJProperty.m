classdef (Abstract) DJProperty < handle
    %% Property caller for datajoint instances
    %

    properties
        
        value
    end
    properties (Abstract, Access = protected)
               
        parent % parent datajoint class

    end

    properties (Abstract, Access =protected, Constant)
        identity_vars cell % if multiple rows have the same values for 
        % these columns the property associated with these rows are 
        % expected to be the same.
    end

    properties (Dependent)
        
        n_rows
        
    end

    methods (Abstract, Access = protected)

        get_method(self, key) %method to call property
        
    end

    methods

        function self = make(self)
            
            % method to call properties per row
            % get_method must have been defined within the instance class

            tbl = self.parent;
            tpls = fetchtable(self.parent,self.identity_vars{:});
            [gru, op] = findgroups(tpls(:,self.identity_vars));
            tpls = table2struct(tpls);
            
            only_fetch = find([1, gen.make_row(diff(gru))]);            
            n_uniq_gru = sum(only_fetch ~= 0);
            props = cell(1, n_uniq_gru);

            for ii = 1:n_uniq_gru

                rowN = tbl & tpls(only_fetch(ii));
                props{ii} = self.get_method(rowN);

            end

            op.value = gen.make_column(props);
            if height(op) == 1 || isequal(props{:})
                op = op.value{1};
            end
            self.value = op;

        end
        
        function n = get.n_rows(self)

            n = count(self.parent);

        end

        
        function parent = get_parent(self)

            parent = self.parent;

        end

        function self = update(self, new_parent)

            if isempty(self) || ~isequal(self.parent, new_parent)

                self.parent = new_parent;
                self.make();
                
            end
        end

    end

end