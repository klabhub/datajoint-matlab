classdef (Abstract) DJInstance < handle

    % A utility wrapper class for Datajoint table instances to use indexing
    properties (Dependent)

        Table % handle to the unrestricted table
        variable_names % variable names in header
        useGPU % whether to useGPU
        n_gpu
        isSLURM % true if running a SLURM job

    end

    properties
    
        % if multitask is true, each makeTuple will assume to have been 
        % assigned multiple cpus per task and run in parallel
        % submitted script must first instantiate the table, and set
        % multitask = true before calling parpopulate
        multiproc (1,1) logical = false 

    end

    properties (Access=protected)

        pool_ % cpu pool to use within makeTuples
        temp_dir_ = tempdir% directory in which the temp results are written
        useGPU_ = false

    end

    properties (Constant)

        query_operators_dj_ = {'in', 'not in', '=', '>', '>=', '<', '<=', ...
            '<>', '~=', '<<', '>>', 'between', '~<<', '~>>','not between'}
        query_operators_ = {'in', 'not in', '=', '>', '>=', '<', '<=', ...
            '<>', '<>', 'between', 'between', 'between', 'not between', 'not between', 'not between'}        
        query_operator_map_ = containers.Map(dj.DJInstance.query_operators_dj_, ...
            dj.DJInstance.query_operators_)
        
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

        function self = request(self, var, rel, val, pv)

            % queries 
            arguments (Input)
                self 
            end

            arguments (Input, Repeating)                
                var {mustBeTableVar_(self, var)}
                rel {mustBeQueryOperator_(rel)}
                val 
            end

            arguments
                pv.statement = 'and' % 'and', 'or', 
                % not yet developed: '*', '-', '+'
            end

            if nargin==1, return; end
            [var, rel, val, pv.statement] = configureQueryConstituents_( ...
                var, rel, val, pv.statement);
            query_str = makeQuery_(var, rel, val, pv.statement);
            self = self & query_str;

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
            check_class_uniformity_(tables{:});

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
        
        % --- Get Methods ---
        function djTbl = get.Table(self)
            % get the unsrestricted datajoint table of the instance
            djTbl = feval(class(self));
        end

        function vars = get.variable_names(self)
            vars = self.header.names;
        end

        function u = get.useGPU(self)

            u = self.useGPU_;

        end

        function set.useGPU(self,val)

            arguments
                self
                val (1,1) logical
            end
            self.useGPU_ = canUseGPU() && val;

        end

        function n = get.n_gpu(self)
            
            n = self.useGPU * gpuDeviceCount();

        end

        function i = get.isSLURM(~)
            % whether running a slirm job or not
            i=~isempty(getenv('SLURM_JOB_ID')); 

        end
        


    end   

    methods (Access = protected)

        % makeTuple
        function setup_pool(self, varargin)

            if self.multiproc
                % setup pool, assign pool
                % parfor: subclass method
                self.pool_ = setup_pool_(self.isSLURM, ...
                    temp_dir=self.temp_dir_);

            end

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

        function isUniform = check_superclass_uniformity_(varargin)

            % checks if all tables belong to the same class
            types = cellfun(@(x) string(class(x)), varargin);
            uniq_type = unique(types);
            isUniform = ~isscalar(uniq_type);            

        end

        function assign_gpu(n_gpu)

            arguments

                n_gpu (1,1) {mustBePositive, mustBeInteger}

            end
            % RUN THIS WITHIN PARFOR
            % Check whether it can use gpu
            % Get the current worker object
            task = getCurrentTask();
            if isempty(task), return; end

            % Calculate which GPU this worker should use.
            % t.ID is the worker ID (1, 2, ..., 8).
            % We map this to GPU IDs (1, 2) using modulo.
            gpu_idx = mod(task.ID - 1, n_gpu) + 1;
            % Select the GPU for this specific worker iteration
            g = gpuDevice(gpu_idx);

        end

    end

end

function x = makeStringIfChar(x)
% Force convert to string if x is a character

if ischar(x)
    x = string(x);
end

end

function check_class_uniformity_(varargin)

types = cellfun(@(x) string(class(x)), varargin);
uniq_type = unique(types);
assert(isscalar(uniq_type), 'AssertionError:NonuniformInputClasses', 'Input classes must be uniform.');

end


function pool = setup_pool_(isSLURM, options)
% SETUP_POOL Initializes a parallel pool with robust path handling.
%
%   Args:
%       numWorkers (int): Number of workers. If empty or 0, attempts to read
%                         SLURM_CPUS_PER_TASK, otherwise defaults to local core count.
%       jobStorageRoot (string/char): The absolute path to the parent directory
%                                     where temporary job folders will be created.
%                                     Must be an existing folder.

arguments
    isSLURM (1,1) logical
    % Default: Empty (triggers auto-detection)
    options.n_workers (1,1) double {mustBeNonnegative, mustBeInteger} = 0

    % Default: The system's temporary directory (OS agnostic)
    % Validation: {mustBeFolder} ensures the path exists before code runs
    options.temp_dir (1,:) char {mustBeNonempty, mustBeFolder} = tempdir
end

n_workers = options.n_workers;
% --- 1. Determine Worker Count ---
if n_workers == 0 && isSLURM
    % Try to get Slurm CPU count
    slurmCPUs = getenv('SLURM_CPUS_PER_TASK');
    assert(~isempty(slurmCPUs), 'NO SLURM CPUs WERE DETECTED!!');
    n_workers = str2double(slurmCPUs);
    % --- 2. Setup Job Storage Location ---
    % Get Slurm Job ID for unique folder naming (prevents collisions)
    jobID = getenv('SLURM_JOB_ID');

else

    if n_workers == 0 % default to all cores
        n_workers = feature('numCores');
    end
    jobID = sprintf("localJob%10d",randi(2^32));

end



% Create the specific subfolder for this job instance
% Structure: /path/to/storage/matlab_job_12345/
folderName = sprintf('matlab_job_%s',jobID);
specificJobDir = fullfile(options.temp_dir, folderName);

% Ensure directory exists (creates it if missing)
if ~exist(specificJobDir, 'dir')
    mkdir(specificJobDir);
end
% --- 3. Configure and Start Cluster ---
% Clean up any existing pool
pool = gcp('nocreate');
if ~isempty(pool)
    % If a pool exists with WRONG size or location, kill it.
    % If it matches perfectly, just return it (saves time).
    if pool.NumWorkers == n_workers       
        return;
    else
        delete(pool);
    end
end

c = parcluster('local');
c.NumWorkers = n_workers;
c.JobStorageLocation = specificJobDir;

fprintf('Starting parallel pool...\n');
fprintf('   Workers: %d\n', n_workers);
fprintf('   Storage: %s\n', specificJobDir);

% Launch the pool
% 'SpmdEnabled', false if only using parfor and parfeval. it blocks
% inter-worker communication
pool = parpool(c, n_workers, SpmdEnabled = false);
end



%% === Input Validation Functions ===

function mustBeQueryOperator_(op)
mustBeMember(op, dj.DJInstance.query_operator_map_.keys);
end

function mustBeTableVar_(self, var)

%% function to check is var exists in table
mustBeMember(var, self.variable_names);
end

function [var, rel, val, statement] = configureQueryConstituents_(var, rel, val, statement)

n_args = numel(var);

for ii = 1:n_args

    switch var{ii}

        case {'<>', '=', '~='}
            assert(isscalar(val{ii}) || ischar(val{ii}))
        case {'<<', '~<<'}
            assert( ...
                isnumeric(val{ii}) && numel(val{ii}) == 2 && diff(val{ii})>0, ...
                "Use '<<' operator with an increasing numeric array of 2.");
            
        case {'>>', '~>>'}
            assert( ...
                isnumeric(val{ii}) && numel(val{ii}) == 2 && diff(val{ii})<0, ...
                "Use '>>' operator with a decreasing numeric array of 2.");
        case {'in', 'not in', 'like'}                        
            continue
        otherwise
            assert(isnumeric(val{ii}), "Query value must be numeric.")
    end
end

% and/or operators
if ~iscell(statement), statement = {statement}; end
n_statement = numel(statement);
if n_statement==1
    
    statement = repelem(statement, n_args-1);
    n_statement = numel(statement);
end
assert(n_args==1 || n_statement==n_args-1, "Logical statement does not match number of queries requested.");

end

function q = makeQuery_(var, rel, val, statement)

n_args = numel(var);



operators = cellfun(@(rel, val) dj.DJInstance.query_operator_map_(rel), ...
    rel, UniformOutput=false);
queries = cell(1,n_args);
for ii = 1:n_args

    switch operators{ii}
        case {'<>','='}

            val_str = string(val{ii});
        case {'between', 'not between'}
            valN = val{ii};
            val_str = sprintf('%f and %f', val{ii}(1), val{ii}(2));
            
        case {'in', 'not in'}                        
            val_str = sprintf('(%s)', join(string(val{ii}),","));
        otherwise
            error('not developed yet')
    end

    queries{ii} = sprintf('%s %s %s', var{ii}, operators{ii}, val_str);

end

if n_args > 1
    q = sprintf(join(string(queries), ' %s '), statement{:});
else
    q = queries{1};
end

end