function [rels, counts, isCapped, isApprox] = planDelete(self, limit)
    %planDelete - Build a read-only cascading deletion plan
    %   [RELS,COUNTS,ISCAPPED,ISAPPROX] = dj.planDelete(ROOT,LIMIT) returns
    %   affected relations in parent-first order and their count semantics.
    %   LIMIT defaults to dj.config('countLimit'). This function neither
    %   changes data nor starts or cancels transactions.
    %
    %   Complete key sets of up to min(1000,LIMIT) rows flatten the next
    %   level's restrictions. Exact empty paths are pruned, while alternate
    %   foreign-key paths remain active. At most 1001 keys are fetched per
    %   relation. Larger branches retain capped root counts or approximate
    %   descendant estimates and are never pruned on an estimated zero.
    %
    %   See also dj.Relvar.del
    if nargin < 2
        limit = dj.config('countLimit');
    end
    if ~isscalar(limit) || isnan(limit) || limit < 1 || ...
            (~isinf(limit) && limit ~= floor(limit))
        error('DataJoint:invalidCountLimit', ...
            'The count limit must be a positive integer or Inf.');
    end
    keyLimit = min(1000,limit);
    list = self.descendants;
    rels = cellfun(@(name) dj.Relvar(name),list,'UniformOutput',false);
    rels = [rels{:}];
    tableNames = arrayfun(@(rel) rel.fullTableName,rels,'UniformOutput',false);
    foreignKeys = self.schema.conn.foreignKeys;
    counts = zeros(size(rels));
    isCapped = false(size(rels));
    isApprox = false(size(rels));
    routes = cell(size(rels));
    simpleRoutes = true(size(rels));

    for i = 1:numel(rels)
        isRoot = strcmp(tableNames{i},self.fullTableName);
        if isRoot
            rels(i) = rels(i) & self.restrictions;
        elseif isempty(routes{i})
            % Every affected incoming path was proven empty. Do not
            % query this relation or propagate to its children.
            rels(i) = rels(i) & 'FALSE';
            continue;
        else
            % Deletion through any foreign key affects a child row.
            % A separate nonempty path survives an empty parent path.
            rels(i).restrict(['(' strjoin(routes{i},' OR ') ')']);
        end

        outgoing = foreignKeys;
        if ~isempty(foreignKeys)
            outgoing = foreignKeys(strcmp(tableNames{i},{foreignKeys.ref}));
        end
        keys = struct([]);
        complete = false;
        if simpleRoutes(i)
            attributes = {};
            for k = 1:numel(outgoing)
                attributes = [attributes outgoing(k).ref_attrs]; %#ok<AGROW>
            end
            attributes = unique(attributes,'stable');
            keys = fetch(rels(i),attributes{:},sprintf('LIMIT %d',keyLimit+1));
            complete = numel(keys) <= keyLimit;
        end
        if complete
            counts(i) = numel(keys);
        else
            [counts(i),isCapped(i),isApprox(i)] = ...
                rels(i).estimatedDeleteCount(limit,isRoot);
            if ~isempty(keys)
                % An observed key is stronger evidence than EXPLAIN.
                counts(i) = max(counts(i),min(numel(keys),limit));
            end
        end
        if counts(i) == 0 && ~isCapped(i) && ~isApprox(i)
            continue;
        end

        parent = rels(i);
        if complete
            % Replace all ancestor joins by this complete key set.
            parent = dj.Relvar(list{i}) & keys;
        end
        for k = 1:numel(outgoing)
            child = find(strcmp(outgoing(k).from,tableNames));
            if isempty(child)
                continue;
            end
            assert(isscalar(child) && child > i, ...
                'DataJoint:DeletePlan:DependencyOrder', ...
                'Deletion dependencies must be in parent-first order.');
            childAttrs = cellfun(@(a) ['`' a '`'],outgoing(k).attrs, ...
                'UniformOutput',false);
            parentAttrs = cellfun(@(a) ['`' a '`'],outgoing(k).ref_attrs, ...
                'UniformOutput',false);
            route = sprintf('(%s) IN (SELECT %s FROM %s)', ...
                strjoin(childAttrs,','),strjoin(parentAttrs,','),parent.sql);
            routes{child}{end+1} = route;
            simpleRoutes(child) = simpleRoutes(child) && complete;
        end
    end
end
