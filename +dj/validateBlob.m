function [blobs, is_valid] = validateBlob(blobs)
    % VALIDATEBLOB Validates and auto-sanitizes DataJoint blobs.
    % Automatically converts MATLAB strings to mym-safe chars.
    
    fprintf('Starting recursive deep validation and sanitization of %d blobs...\n', numel(blobs));
    
    % We apply the recursive function to the top-level cell array
    % UniformOutput is false because it returns modified cells and booleans
    blobs_flat = blobs(:);
    indices = num2cell((1:numel(blobs_flat))');
    
    [cleaned_blobs_flat, oks] = cellfun(@(b, idx) sanitize_item(b, sprintf('blobs{%d}', idx)), ...
                                        blobs_flat, indices, 'UniformOutput', false);
    
    % Reconstruct the main array and combine the boolean flags
    blobs = reshape(cleaned_blobs_flat, size(blobs));
    is_valid = all([oks{:}]);
    
    if is_valid
        fprintf('\nSUCCESS: Blobs sanitized. Ready for insertion.\n');
    else
        fprintf('\nFAILED: Unsupported types still detected. mym will reject this insert.\n');
    end
end

function [item_out, is_ok] = sanitize_item(item, current_path)
    % SANITIZE_ITEM Recursively cleans and checks items.
    
    item_out = item; % Default: return the item unmodified
    is_ok = true;
    
    % --- 1. Base Cases: Hard Failures ---
    if istable(item)
        fprintf('  [!] ERROR at %s: Table objects cannot be serialized. Convert to scalar struct.\n', current_path);
        is_ok = false; return;
    elseif isa(item, 'graph') || isa(item, 'digraph')
        fprintf('  [!] ERROR at %s: Graph objects are MATLAB-specific. Extract nodes/edges to struct.\n', current_path);
        is_ok = false; return;
    elseif isa(item, 'function_handle')
        fprintf('  [!] ERROR at %s: Function handles cannot be stored in the database.\n', current_path);
        is_ok = false; return;
    elseif isdatetime(item) || iscategorical(item)
        fprintf('  [!] ERROR at %s: Datetime/Categorical arrays must be converted to character arrays.\n', current_path);
        is_ok = false; return;
    elseif isobject(item) && ~isstring(item)
        fprintf('  [!] ERROR at %s: Custom class instance (%s) detected. Extract properties to struct.\n', current_path, class(item));
        is_ok = false; return;
    end

    % --- 2. Auto-Correction: Fix Strings ---
    if isstring(item)
        fprintf('  [*] FIXED at %s: Converted "string" to "char".\n', current_path);
        if isscalar(item)
            item_out = char(item);
        else
            item_out = cellstr(item); 
        end
        return;
    end

    % --- 3. Recursive Step: Expandable Cells ---
    if iscell(item)
        item_flat = item(:);
        indices = num2cell((1:numel(item_flat))');
        
        [new_items, oks] = cellfun(@(x, idx) sanitize_item(x, sprintf('%s{%d}', current_path, idx)), ...
                                   item_flat, indices, 'UniformOutput', false);
        
        item_out = reshape(new_items, size(item));
        is_ok = all([oks{:}]);
        return;
        
    % --- 4. Recursive Step: Expandable Structs ---
    elseif isstruct(item)
        % 4a. Handle Struct Arrays (e.g., s(1), s(2))
        if numel(item) > 1
            indices = (1:numel(item))';
            
            [new_items, oks] = arrayfun(@(idx) sanitize_item(item(idx), sprintf('%s(%d)', current_path, idx)), ...
                                        indices, 'UniformOutput', false);
            
            item_out = reshape([new_items{:}], size(item));
            is_ok = all([oks{:}]);
            return;
        end
        
        % 4b. Handle Scalar Structs (expand the fields)
        fields = fieldnames(item);
        if ~isempty(fields)
            [new_vals, oks] = cellfun(@(fn) sanitize_item(item.(fn), sprintf('%s.%s', current_path, fn)), ...
                                      fields, 'UniformOutput', false);
            
            % cell2struct expects a cell array of values and a cell array of field names
            % The '1' specifies that the values are along the 1st dimension
            item_out = cell2struct(new_vals(:), fields(:), 1);
            is_ok = all([oks{:}]);
        end
        return;
        
    % --- 5. Base Cases: Valid Data Types ---
    elseif isnumeric(item) || islogical(item) || ischar(item)
        return; 
        
    % --- 6. Catch-all ---
    else
        fprintf('  [!] ERROR at %s: Unrecognized type (%s).\n', current_path, class(item));
        is_ok = false; return;
    end
end
% function [is_valid, blobs] = validateBlob(blobs)
%     % VALIDATEBLOB Validates DataJoint blobs using pure structural recursion.
%     % Identifies the exact path and reason for unsupported data types.
% 
%     fprintf('Starting recursive deep validation of %d blobs...\n', numel(blobs));
% 
%     % Kick off the recursion using cellfun across the root blobs
%     % We flatten the array (blobs(:)) to ensure dimension alignment
%     blobs_flat = blobs(:);
%     indices = num2cell(1:numel(blobs_flat));
% 
%     % cellfun applies check_item to every blob, naturally recalling the function
%     results = cellfun(@(b, idx) check_item(b, sprintf('blobs{%d}', idx)), blobs_flat(:), indices(:));
% 
%     is_valid = all(results);
% 
%     if is_valid
%         fprintf('\nSUCCESS: No unsupported types found. Ready for insertion.\n');
%     else
%         fprintf('\nFAILED: Unsupported types detected. mym will reject this insert.\n');
%     end
% end
% 
% function [item_out, is_ok] = check_item(item, current_path)
% 
% try
%     % CHECK_ITEM Recursively inspects items and returns true if valid.
%     item_out = item; % Default: return the item unmodified
%     is_ok = true;
%     % --- 1. Base/Terminal Cases: Catch Invalid Types (The "Why") ---
%     if istable(item)
%         fprintf('  [!] ERROR at %s: Table objects cannot be serialized. Convert to scalar struct.\n', current_path);
%         is_ok = false; return;
%     elseif isa(item, 'graph') || isa(item, 'digraph')
%         fprintf('  [!] ERROR at %s: Graph objects are MATLAB-specific. Extract nodes/edges to struct.\n', current_path);
%         is_ok = false; return;
%     elseif isa(item, 'function_handle')
%         fprintf('  [!] ERROR at %s: Function handles cannot be stored in the database.\n', current_path);
%         is_ok = false; return;
%     elseif isdatetime(item) || iscategorical(item)
%         fprintf('  [!] ERROR at %s: Datetime/Categorical arrays must be converted to character arrays.\n', current_path);
%         is_ok = false; return;
%     elseif isobject(item) && ~isstring(item)
%         fprintf('  [!] ERROR at %s: Custom class instance (%s) detected. Extract properties to struct.\n', current_path, class(item));
%         is_ok = false; return;
%     end
% 
%     % --- 2. Auto-Correction: Fix Strings ---
%     if isstring(item)
%         fprintf('  [*] FIXED at %s: Converted "string" array to "char".\n', current_path);
%         if isscalar(item)
%             % Single string becomes a standard char vector (e.g., 'hello')
%             item_out = char(item);
%         else
%             % Array of strings becomes a cell array of chars (e.g., {'a', 'b'})
%             % This prevents creating 2D char matrices which mym also rejects.
%             item_out = cellstr(item); 
%         end
%         return;
%     end
% 
%     % --- 3. Recursive Step: Expandable Cells ---
%     if iscell(item)
%         item_flat = item(:);
%         indices = num2cell(1:numel(item_flat))';
% 
%         % Recall check_item on every element of the cell array
%         res = cellfun(@(x, idx) check_item(x, sprintf('%s{%d}', current_path, idx)), item_flat, indices);
%         is_ok = all(res);
%         return;
% 
%     % --- 4. Recursive Step: Expandable Structs ---
%     elseif isstruct(item)
%         % 3a. Handle Struct Arrays (e.g., s(1), s(2))
%         if numel(item) > 1
%             indices = 1:numel(item);
%             % Recall check_item on each struct in the array
%             res = arrayfun(@(idx) check_item(item(idx), sprintf('%s(%d)', current_path, idx)), indices);
%             is_ok = all(res);
%             return;
%         end
% 
%         % 3b. Handle Scalar Structs (expand the fields)
%         fields = fieldnames(item);
%         if ~isempty(fields)
%             % Recall check_item on the contents of every field
%             res = cellfun(@(fn) check_item(item.(fn), sprintf('%s.%s', current_path, fn)), fields);
%             is_ok = all(res);
%         else
%             is_ok = true; % Empty struct is fine
%         end
%         return;
% 
%     % --- 4. Base/Terminal Cases: Valid Data Types ---
%     elseif isnumeric(item) || islogical(item) || ischar(item)
%         is_ok = true; return;
% 
%     % --- 5. Edge Cases & Warnings ---
%     elseif isstring(item)
%         fprintf('  [-] WARNING at %s: "string" array found. DataJoint prefers "char" arrays. Consider using char().\n', current_path);
%         is_ok = true; return;
% 
%     % --- Catch-all ---
%     else
%         fprintf('  [!] ERROR at %s: Unrecognized/Unsupported type (%s).\n', current_path, class(item));
%         is_ok = false; return;
%     end
% 
% catch e
% 
%     a
% 
% end
% end