classdef (Abstract) DJInstance < handle
    % A utility wrapper class for Datajoint table instances to use indexing
    
    properties (Dependent)

        Table % handle to the unrestricted table
        attributes table
        keys
        primary
        secondary
    end
    
    methods

        function varargout = subsref(djTbl, s)
            % obj: The object instance (e.g., C1)
            % s: A structure array with fields:
            %    s.type: Type of indexing: '()', '{}', or '.'
            %    s.subs: Cell array of actual indices or field name

            isQry = strcmp(s(1).type, '()');
            isFetch = strcmp(s(1).type, '{}');

            % Check for the specific case: C1(1,:)
            if isQry || isFetch

                assert(isscalar(s(1).subs) || numel(s(1).subs) <= 2, ...
                    'Invalid indexing.');
                assert(isFetch || (isscalar(s(1).subs) || strcmp(s(1).subs(2),':')), ...
                    ['Invalid indexing in the second dimension. Only row' ...
                    ' indices must be provided with "{}".'])
                % This is the C1(1,:) case
                % If it's just C1(1,:) and not C1(1,:).something_else
                if isQry

                    varargout{1} = djTbl.restrict_(s(1).subs{1});

                else % fetch

                    varargout{1} = djTbl.fetch_(s(1).subs{:});

                end
                if ~isscalar(s)

                    % Handle chained indexing starting with C1(1,:),
                    % e.g., C1(1,:).PropertyName or C1(1,:)(further_indices)

                    % Then, apply the rest of the indexing operations to this tempResult
                    % This often means calling builtin subsref on the tempResult
                    if nargout > 0
                        [varargout{1:nargout}] = builtin('subsref', varargout{1}, s(2:end));
                    else
                        builtin('subsref', varargout{1}, s(2:end)); % For cases like C1(1,:).someMethod()
                    end
                end

            else

                % Default handling for dot-indexing like obj.property or obj.method()

                % Check if this is a method with zero declared outputs
                isZeroOutputMethod = false;
                if strcmp(s(1).type, '.')
                    % Use metaclass to be robust
                    mc = metaclass(djTbl);
                    method_meta = mc.MethodList(strcmp({mc.MethodList.Name}, s(1).subs));
                    if ~isempty(method_meta) && isempty(method_meta.OutputNames)
                        isZeroOutputMethod = true;
                    end
                end

                % --- Corrected Decision Logic ---
                if isZeroOutputMethod && nargout > 0
                    % Special Case: Caller wants an output, but the method has none.

                    % 1. Call the method, requesting no outputs from it.
                    builtin('subsref', djTbl, s);

                    % 2. Satisfy the caller by creating and assigning empty outputs.
                    varargout = cell(1, nargout);
                    [varargout{:}] = deal([]);

                else
                    % Normal Case: It's a property, a method with outputs, or the
                    % caller wants no outputs. Let builtin handle it normally.
                    [varargout{1:nargout}] = builtin('subsref', djTbl, s);
                end

            end
        end

        function djTbl = cat(varargin)
            % stacks djTbl instances
            djTbl = stack(varargin{:});
        end
        
        function djTbl = horzcat(varargin)
            % stacks djTbl instances
            djTbl = stack(varargin{:});

        end

        function djTbl = vertcat(varargin)
            % stacks djTbl instances
            djTbl = stack(varargin{:});
                        
        end

        function djTbl = stack(tables)

            arguments (Repeating)

                tables dj.DJInstance

            end

            if nargin == 1, djTbl = tables{1}; return; end
            
            % union of multiple djInstances of same type                      
            verify_class_uniformity_(tables{:});

            self = tables{1}; 
            tables = cellfun(@(x) proj(x), tables, UniformOutput=false);
            unrestricted_table = self.Table;
            djTbl = unrestricted_table & (proj(tables{1}) | proj(tables{2}));
            for iArg = 3:nargin
                
                djTbl = unrestricted_table & (proj(djTbl) | proj(tables{iArg}));

            end

        end

        function n = numArgumentsFromSubscript(djTbl, ~, ~)           

            n = numel(djTbl);

        end

        function val = get_dj_property(djTbl, djProp, getMethod, varargin)

            % Wrapper function to call djProperty values
            arguments

                djTbl
                djProp dj.DJProperty
                getMethod function_handle

            end

            arguments (Repeating)
                varargin
            end

            if isempty(djProp) || djProp.parent ~= djTbl

                djProp = dj.DJProperty(djTbl, getMethod, varargin{:});
                djProp.demand();

            end
            val = djProp.value;

        end        
        
        function uniq_vals = unique(self, keys, pv)
            % returns unique values of key(s)
            %   returns a vector if a single key requested, otherwise
            %   returns a table of combinations
            arguments
                self                 
            end

            arguments (Repeating)
                keys char
            end

            arguments
                pv.runtime (1,1) double {mustBePositive} = 5 % Max runtime in seconds
            end


            assert(all(ismember(keys, self.keys)), 'Unrecognized key(s)!!')

            sql_qry = sprintf('SET STATEMENT max_statement_time=%g FOR SELECT DISTINCT %s FROM %s', pv.runtime, strjoin(keys, ', '), self.sql);
            
            try
                % Execute using the current instance's connection
                uniq_vals = query(self.schema.conn, sql_qry);
            catch ME
                if contains(ME.message, 'max_statement_time', 'IgnoreCase', true)
                    error('dj:unique:Timeout', 'Query exceeded the maximum runtime of %g seconds.', pv.runtime);
                else
                    rethrow(ME);
                end
            end

            if isscalar(keys)
                uniq_vals = uniq_vals.(keys{1});
            else
                uniq_vals = struct2table(uniq_vals);
            end

        end % UNIQUE()

        function self = query(self, varargin)
            n_arg = numel(varargin);
            ii = 1;
            table_op = '&';
            
            while ii <= n_arg
                arg = varargin{ii};
                
                if ischar(arg) || isstring(arg)
                    arg = char(arg);
                    
                    if ismember(arg, {'*', '&', '-', '+'})
                        table_op = arg;
                        ii = ii + 1;
                        continue;
                    end
                    
                    is_raw_string = (ii == n_arg) || ...
                        isa(varargin{ii+1}, 'dj.DJInstance') || ...
                        (ischar(varargin{ii+1}) && ismember(char(varargin{ii+1}), {'*', '&', '-', '+'}));
                    
                    if is_raw_string
                        self = self.applyOperator(table_op, arg);
                        table_op = '&';
                        ii = ii + 1;
                    else
                        key = arg;
                        val = varargin{ii+1};
                        
                        tokens = split(strtrim(key), ' ');
                        field_name = tokens{1};
                        
                        if numel(tokens) > 1
                            rel_op = strjoin(tokens(2:end), ' ');
                        else
                            if numel(val) > 1 && isnumeric(val)
                                rel_op = 'IN';
                            else
                                rel_op = '=';
                            end
                        end
                        
                        % 2. Conform types
                        val = self.conform_data(field_name, val);
                        
                        % Format value for SQL string
                        rel_op_upper = upper(strtrim(rel_op));
                        is_str_val = isstring(val) || ischar(val) || iscellstr(val);
                        
                        if ismember(rel_op_upper, {'IN', 'NOT IN'})
                            if is_str_val
                                val_str = sprintf('"%s",', val);
                            else
                                val_str = sprintf('%g,', val);
                            end
                            val_str = sprintf('(%s)', val_str(1:end-1));
                        elseif ismember(rel_op_upper, {'IS', 'IS NOT'})
                            val_str = char(val); % e.g., NULL
                        else
                            if is_str_val
                                val_str = sprintf('"%s"', char(val));
                            else
                                val_str = num2str(val);
                            end
                        end
                        
                        % 3. Create and apply query
                        sql_cond = sprintf('%s %s %s', field_name, rel_op, val_str);
                        self = self.applyOperator(table_op, sql_cond);
                        
                        table_op = '&';
                        ii = ii + 2;
                    end
                    
                elseif isa(arg, 'dj.Relational')
                    self = self.applyOperator(table_op, arg);
                    table_op = '&';
                    ii = ii + 1;
                else
                    error('Unsupported argument type at index %d', ii);
                end
            end

        end % END query()

        function val = conform_data(self, field_name, val)
            % Translates MATLAB datatypes to match DataJoint table attributes
            attr = self.attributes;
            
            if ismember(field_name, attr.name)
                field_type = attr.type{strcmp(attr.name, field_name)};
                is_string_type = contains(field_type, {'char', 'date', 'time', 'enum'}, 'IgnoreCase', true);
                
                if is_string_type
                    % Convert numeric or char to string array
                    if isnumeric(val) || islogical(val) || ischar(val)
                        val = string(val);
                    end
                else
                    % Convert string or char to double for numeric fields
                    if isstring(val) || ischar(val)
                        val = str2double(val);
                    end
                end
            else
                % Default string conversion for safety if field is unlisted
                if ischar(val)
                    val = string(val);
                end
            end
        end % END convert()

        % --- Get Methods ---
        function djTbl = get.Table(self)
            % get the unsrestricted datajoint table of the instance
            djTbl = feval(class(self));

        end

        function attr = get.attributes(self)

            attr = struct2table(self.header.attributes);

        end

        function varnames = get.keys(self)
            % all keys
            varnames = self.attributes.name;
        end
        
        function varnames = get.primary(self)
            % primary keys
            varnames = self.primaryKey;
        end

        function varnames = get.secondary(self)
            % secondary keys
            varnames = setdiff(self.keys, self.primary);
        end


    end   

    methods (Access = private)

        function obj = applyOperator(obj, op, right_operand)
            switch op
                case '&'
                    obj = obj & right_operand;
                case '-'
                    obj = obj - right_operand;
                case '*'
                    obj = obj * right_operand;
                case '+'
                    obj = obj + right_operand;
                otherwise
                    error('Unsupported table operator: %s', op);
            end
        end

        function rstrDJTbl = restrict_(djTbl,idx)

            tbl = fetch(djTbl);
            rstrDJTbl = djTbl & tbl(idx);

        end

        function varargout = fetch_(djTbl, varargin)

            % add option to fetch multiple columns by variable name

            n_arg = nargin - 1;
            assert(n_arg <= 2, 'Invalid indexing with "{}".');

            subs1 = varargin{1};
            if ~(isnumeric(subs1) || strcmp(subs1,':'))

                col_name = {char(subs1)};
                subs1 = ':';
            else

                col_name = {'*'};

            end

            if n_arg == 2 && ~ strcmp(varargin{2}, ':')

                col_name = {char(varargin{2})};

            end

            tpl = fetch(djTbl.restrict_(subs1), col_name{:});

            if ~strcmp(col_name, '*')

                if all(cellfun(@(x) isstruct(x), {tpl.(col_name{:})}))

                    % if column contains structs, return struct array
                    [varargout{1:nargout}] = catstruct(1, tpl.(col_name{:}));

                else

                    try
                        rows = cellfun(@(x) makeStringIfChar(x), {tpl.(col_name{:})});
                        [varargout{1:nargout}] = cat(1,rows);
                    catch ME

                        switch ME.identifier

                            case 'MATLAB:cellfun:NotAScalarOutput'

                                % return cell array
                                rows = cellfun(@(x) makeStringIfChar(x), {tpl.(col_name{:})}, UniformOutput=false);

                                try % return concatenated array of the original datatype if possible
                                    [varargout{1:nargout}] = cat(1,rows{:});

                                catch ME2

                                    switch ME2

                                        case 'MATLAB:catenate:dimensionMismatch'
                                            % return as cell array
                                            [varargout{1:nargout}] = cat(1,rows);

                                        otherwise

                                            rethrow(ME2);

                                    end

                                end

                            otherwise

                                rethrow(ME);

                        end
                    end


                end
            else

                [varargout{1:nargout}]  = tpl;

            end


        end       

    end

    methods (Access = protected, Static)

        function isUniform = verify_superclass_uniformity_(varargin)

            % checks if all tables belong to the same class
            types = cellfun(@(x) string(class(x)), varargin);
            uniq_type = unique(types);
            isUniform = ~isscalar(uniq_type);            

        end

    end

end

function x = makeStringIfChar(x)
% Force convert to string if x is a character

if ischar(x)
    x = string(x);
end

end

function verify_class_uniformity_(varargin)

types = cellfun(@(x) string(class(x)), varargin);
uniq_type = unique(types);
assert(isscalar(uniq_type), 'AssertionError:NonuniformInputClasses', 'Input classes must be uniform.');

end


