function candidate = parentKeyFilter(table,restrictions)
%parentKeyFilter - Select an unambiguous indexed parent-key restriction
%   Uses cached schema metadata only. Returns [] unless a nonnullable,
%   unrenamed primary foreign key and a leading parent index column match
%   simple positive key equalities. Original child predicates are retained.
candidate = [];
header = table.tableHeader;
foreignKeys = table.schema.conn.foreignKeys;
if isempty(foreignKeys)
    return
end
[names,conditions] = keyEqualities(restrictions,header.primaryKey);
if isempty(names)
    return
end
links = foreignKeys(strcmp({foreignKeys.from},table.fullTableName) & ...
    ~strcmp({foreignKeys.ref},table.fullTableName) & ...
    [foreignKeys.primary] & ~[foreignKeys.aliased]);
bestScore = 0;
tied = false;
for link = links(:)'
    if ~isequal(link.attrs,link.ref_attrs)
        continue
    end
    childAttributes = header.attributes(ismember({header.attributes.name},link.attrs));
    if numel(childAttributes) ~= numel(link.attrs) || any([childAttributes.isnullable])
        continue
    end
    target = regexp(link.ref,'^`(?<database>[^`]+)`\.`(?<table>[^`]+)`$', ...
        'names','once');
    if isempty(target)
        continue
    end
    schemas = table.schema.conn.schemas;
    parentSchema = table.schema;
    if ~strcmp(target.database,parentSchema.dbname) || ~isKey(parentSchema.headers,target.table)
        if ~isKey(schemas,target.database)
            continue
        end
        parentSchema = schemas(target.database);
    end
    headers = parentSchema.headers;
    if ~isKey(headers,target.table)
        continue
    end
    parentHeader = headers(target.table);
    if ~isequal(sort(parentHeader.primaryKey),sort(link.ref_attrs))
        continue
    end
    selected = ismember(names,link.attrs);
    selectedNames = names(selected);
    % Primary keys and foreign keys have backing indexes. Require a known
    % leading column, rather than probing indexes/EXPLAIN for every SELECT.
    leading = parentHeader.primaryKey(1);
    for parentLink = foreignKeys(strcmp({foreignKeys.from},link.ref))
        leading{end+1} = parentLink.attrs{1}; %#ok<AGROW>
    end
    if ~any(ismember(selectedNames,leading))
        continue
    end
    score = numel(unique(selectedNames));
    if score > bestScore
        candidate = struct('table',link.ref,'header',parentHeader, ...
            'attributes',{link.attrs},'restrictions',{conditions(selected)});
        bestScore = score;
        tied = false;
    elseif score == bestScore
        tied = true;
    end
end
if tied
    candidate = [];
end
end

function [names,conditions] = keyEqualities(restrictions,keys)
names = {};
conditions = {};
negated = false;
literal = ['(?:''[A-Za-z0-9_.:/ -]*''|"[A-Za-z0-9_.:/ -]*"|' ...
    '[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?)'];
pattern = ['^\s*([A-Za-z_][A-Za-z0-9_]*|`[A-Za-z_][A-Za-z0-9_]*`)\s*=\s*' literal '\s*$'];
for entry = restrictions
    value = entry{1};
    isText = ischar(value) && isrow(value) || isstring(value) && isscalar(value);
    if isText && strcmpi(value,'NOT')
        negated = true;
        continue
    end
    if negated
        negated = false;
        continue
    end
    if isText
        token = regexp(char(value),pattern,'tokens','once');
        if ~isempty(token)
            name = strrep(token{1},'`','');
            if ismember(name,keys)
                names{end+1} = name; %#ok<AGROW>
                conditions{end+1} = char(value); %#ok<AGROW>
            end
        end
    elseif isstruct(value) && isscalar(value)
        fields = intersect(fieldnames(value),keys,'stable');
        for index = 1:numel(fields)
            field = fields(index);
            item = value.(field{1});
            simple = ischar(item) && isrow(item) || ...
                isstring(item) && isscalar(item) && ~ismissing(item) || ...
                (isnumeric(item) || islogical(item)) && isscalar(item) && ...
                isreal(item) && isfinite(item);
            if simple
                names{end+1} = field{1}; %#ok<AGROW>
                conditions{end+1} = struct(field{1},item); %#ok<AGROW>
            end
        end
    end
end
end
