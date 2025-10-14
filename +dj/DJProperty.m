classdef DJProperty < handle
    %% Property caller for datajoint instances
    %
    properties
        
        parent % parent datajoint class
        value = []

    end
    properties (Access = protected)
               
        
        identity_vars_        
        getMethod %method name to call property

    end

    properties (Dependent)
        
        n_rows
        identity_vars % if multiple rows have the same values for 
        % these columns the property associated with these rows are 
        % expected to be the same. comes from the parent
        
    end

    methods

        function self = DJProperty(parent, getMethod, pv)

            % DJProperty often fetches info on-demand from instances. It
            % can be initiated as an empty instance. 

            arguments
                
                parent dj.DJInstance
                getMethod function_handle
                % Use the following options when the property has different
                % identity variables than the primary keys of the parent
                % table
                pv.add_identity_var (1,:) cell = {}
                pv.remove_identity_var (1,:) cell = {}
                pv.set_identity_var (1,:) cell = {}

            end

            self.parent = parent;
            self.getMethod = getMethod;

            if isempty(pv.set_identity_var)

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
                       
            
        end

        function self = demand(self)
            
            % method to call properties per row
            % get_method must have been defined within the instance class

            tbl = self.parent;
            tpls = fetchtable(self.parent,self.identity_vars{:});
            [gru_idx, op] = findgroups(tpls(:,self.identity_vars));
            tpls = table2struct(tpls);
            
            % only fetch unique entries (rows)
            isDiffGru = diff(gru_idx);
            isDiffGru = isDiffGru(:)'; % make it row
            only_fetch = find([1, isDiffGru]);            
            n_uniq_gru = sum(only_fetch ~= 0);
            props = cell(1, n_uniq_gru);

            % looks convoluted to fetch unique entries like this, might be
            % improved by using unique(...,'rows') but currently it is
            % compatible with the cases in which identity_vars can be
            % different than the primary keys of the parent table
            for ii = 1:n_uniq_gru

                rowN = tbl & tpls(only_fetch(ii));
                props{ii} = self.get_method(rowN);

            end

            op.value = props(:);
            % if only a single row, simply output op.value
            if height(op) == 1
                op = op.value{1};
            end
            self.value = op;

        end

        function value = get_method(self, key)

            value = self.getMethod(key);

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

        function i = isempty(self)

            i = builtin('isempty',self) || isempty(self.value);

        end

    end

end
