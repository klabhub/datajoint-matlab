classdef DJProperty < handle
    %% Property caller for datajoint instances
    %
    properties
        
        value

    end
    properties (Access = protected)
               
        parent % parent datajoint class
        identity_vars_        
        getMethod function_handle %method to call property

    end

    properties (Dependent)
        
        n_rows
        identity_vars % if multiple rows have the same values for 
        % these columns the property associated with these rows are 
        % expected to be the same. comes from the parent
        
    end

    methods

        function self = DJProperty(parent, pub_prop_name, pv)

            % DJProperty often fetches info on-demand from instances. It
            % can be initiated as an empty instance. 

            arguments
                
                parent dj.DJInstance
                pub_prop_name {mustBeText} % Name of the public dependent property to listen to;
                pv.getMethodHandle function_handle = get_method_handle(parent, pub_prop_name) 
                % Use the following options when the property has different
                % identity variables than the primary keys of the parent
                % table
                pv.add_identity_var (1,:) cell = {}
                pv.remove_identity_var (1,:) cell = {}
                pv.set_identity_var (1,:) cell = {}

            end

            self.parent = parent;
            self.getMethod = pv.getMethodHandle;

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
            try
             addlistener(parent, pub_prop_name, 'PreGet', @self.demand);
            catch e
                e
            end


        end

        function self = demand(self, ~, ~)
            
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
            if height(op) == 1% || isequal(props{:})
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

    end

end

function func = get_method_handle(parent, pub_prop_name)

func_str = regexprep(pub_prop_name,{'^.','_(\w)'},{'get${upper($0)}','${upper($1)}'});
mc = meta.class.fromName(class(parent));
method_list = mc.MethodList;
method = method_list(strcmp({method_list.Name}, func_str));
func = @(varargin) parent.(method.Name)(varargin{:});

end
