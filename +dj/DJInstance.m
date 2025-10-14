classdef (Abstract) DJInstance < handle

    % A utility wrapper class for Datajoint table instances to use indexing

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
        

    end   

    methods (Access = private)

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

                    [varargout{1:nargout}] = cat(1,tpl.(col_name{:}));
                end
            else

               [varargout{1:nargout}]  = tpl;

            end


        end

    end


end