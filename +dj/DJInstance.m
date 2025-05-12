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
                % For all other indexing, use the built-in subsref
                % This ensures that C1.Property, C1{...}, C1(other_indices), etc.
                % work as expected.

                % nargoutchk is important to correctly handle cases like:
                % val = C1.Data; (nargout = 1)
                % C1.someMethod(); (nargout = 0)
                if nargout > 0
                    [varargout{1:nargout}] = builtin('subsref', djTbl, s);
                else
                    builtin('subsref', djTbl, s);
                end
            end
        end

        function n = numArgumentsFromSubscript(djTbl, ~, ~)           

            n = numel(djTbl);

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
                    
                    [varargout{1:nargout}] = [gen.force_mergestruct(tpl.(col_name{:}))];                      
                else

                    [varargout{1:nargout}] = [tpl.(col_name{:})];
                end
            else

               [varargout{1:nargout}]  = tpl;

            end


        end

    end


end