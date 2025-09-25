classdef DJProperty < handle
    %% Property caller for datajoint instances
    %
    properties (Access = protected)
               
        parent dj.DJInstance% parent datajoint class
        identity_vars_
        value = []

    end

    properties (Dependent)
        
        n_rows
        identity_vars % if multiple rows have the same values for 
        % these columns the property associated with these rows are 
        % expected to be the same. comes from the parent
        
    end

    methods (Abstract, Access = protected)

        get_method(self, key) %method to call property
        
    end

    methods

        function self = DJProperty(parent, prop_name, pv)

            arguments
                
                parent dj.DJInstance
                prop_name {mustBeText}

                % Use the following options when the property has different
                % 
                pv.add_identity_var (1,:) cell = {}
                pv.remove_identity_var (1,:) cell = {}
                pv.set_identity_var (1,:) cell = {}

            end

            self.parent = parent;

            if ~isempty(pv.set_identity_var)

                self.identity_vars = self.parent.primaryKey;
            
            else

                self.identity_vars = pv.set_identity_var;

            end

            if ~isempty(pv.add_identity_var)

                self.identity_vars = [self.identity_vars, pv.add_identity_var];

            end

            if ~isempty(pv.remove_identity_var)

                self.identity_vars = setdiff(self.identity_vars, pv.remove_identity_var);
                
            end
            addlistener(parent, prop_name, 'PreGet', self.make());


        end

        function self = make(self)
            
            % method to call properties per row
            % get_method must have been defined within the instance class
            if ~isempty(self.value), return; end

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

        function vars = get.identity_vars(self)

            vars = self.identity_vars_;

        end

        function set.identity_vars(self, val)
            % if the property has different identity variable set than the
            % parent, you can overwrite
            self.identity_vars_ = val;
            
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