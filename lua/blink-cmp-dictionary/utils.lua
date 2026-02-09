local M = {}

-- Cache for individual dictionary file contents
-- Key: file path, Value: { content = string } or { loading = true, pending_callbacks = {callbacks} }
local file_cache = {}
local uv = vim.uv or vim.loop

function M.get_option(opt, ...)
    if type(opt) == 'function' then
        return opt(...)
    else
        return opt
    end
end

function M.truthy(value)
    if type(value) == 'boolean' then
        return value
    elseif type(value) == 'function' then
        return M.truthy(value())
    elseif type(value) == 'table' then
        return not vim.tbl_isempty(value)
    elseif type(value) == 'string' then
        return value ~= ''
    elseif type(value) == 'number' then
        return value ~= 0
    elseif type(value) == 'nil' then
        return false
    else
        return true
    end
end

--- Transform arguments to string, and concatenate them with a space.
function M.str(...)
    local args = { ... }
    for i, v in ipairs(args) do
        args[i] = type(args[i]) == 'string' and args[i] or vim.inspect(v)
    end
    return table.concat(args, ' ')
end

function M.command_found(command)
    return vim.fn.executable(command) == 1
end

---@param s string # The string to be capitalized
---@param capitalize_whole_word boolean # If true, capitalize the whole word, otherwise only the first letter
---@return string
function M.capitalize(s, capitalize_whole_word)
    local res = s:gsub('^%l', string.upper)
    if capitalize_whole_word then
        res = s:gsub('%l', string.upper)
    end
    return res
end

---@param s string # The string to be decapitalized
---@param decapitalize_whole_word boolean # If true, decapitalize the whole word, otherwise only the first letter
---@return string
function M.decapitalize(s, decapitalize_whole_word)
    local res = s:gsub("^%u", string.lower)
    if decapitalize_whole_word then
        res = s:gsub("%u", string.lower)
    end
    return res
end

--- Calculate fuzzy match score for a word against a pattern
--- Returns a score (higher is better) or nil if no match
--- Based on fzy algorithm: consecutive matches and position bonuses
--- @param word string
--- @param pattern string
--- @return number|nil # Score or nil if no match
local function fuzzy_match_score(word, pattern)
    if pattern == "" then
        return 0
    end
    
    local word_lower = word:lower()
    local pattern_lower = pattern:lower()
    
    -- Check if all pattern characters exist in word (in order)
    local word_idx = 1
    local pattern_idx = 1
    local match_positions = {}
    
    while pattern_idx <= #pattern_lower and word_idx <= #word_lower do
        if word_lower:sub(word_idx, word_idx) == pattern_lower:sub(pattern_idx, pattern_idx) then
            table.insert(match_positions, word_idx)
            pattern_idx = pattern_idx + 1
        end
        word_idx = word_idx + 1
    end
    
    -- If not all pattern characters matched, no match
    if pattern_idx <= #pattern_lower then
        return nil
    end
    
    -- Calculate score based on match positions
    local score = 0
    local last_pos = nil
    
    for i, pos in ipairs(match_positions) do
        -- Bonus for matches at the beginning
        if pos == 1 then
            score = score + 100
        end
        
        -- Bonus for consecutive matches (skip first match)
        if last_pos and pos == last_pos + 1 then
            score = score + 50
        end
        
        -- Penalty for later positions (prefer earlier matches)
        score = score - pos
        
        last_pos = pos
    end
    
    -- Bonus for shorter words (prefer exact or close matches)
    -- Cap at 0 to avoid negative bonuses for long words
    score = score + math.max(0, 100 - #word_lower)
    
    return score
end

--- Get top N items by fuzzy match score using quickselect algorithm
--- Based on nth_element from C++ STL, uses partition from quicksort
--- Average O(n) complexity, better than heap-based O(n + k log k)
--- @param items string[] # List of items to score
--- @param pattern string # Pattern to match against
--- @param max_items number # Maximum number of items to return
--- @return string[] # Top N items (not guaranteed to be sorted)
function M.get_top_matches(items, pattern, max_items)
    if not items or #items == 0 then
        return {}
    end
    
    -- Score all items
    local scored = {}
    for _, item in ipairs(items) do
        local score = fuzzy_match_score(item, pattern)
        if score then
            table.insert(scored, {item = item, score = score})
        end
    end
    
    local n = #scored
    if n == 0 then
        return {}
    end
    
    -- If we have fewer items than max_items, return all
    if n <= max_items then
        local results = {}
        for i = 1, n do
            table.insert(results, scored[i].item)
        end
        return results
    end
    
    -- Partition function: rearranges elements so that elements >= pivot are on the left
    -- Returns the final position of the pivot
    local function partition(arr, left, right, pivot_idx)
        local pivot_score = arr[pivot_idx].score
        -- Move pivot to end
        arr[pivot_idx], arr[right] = arr[right], arr[pivot_idx]
        
        local store_idx = left
        for i = left, right - 1 do
            -- We want larger scores first, so use >= instead of <=
            if arr[i].score >= pivot_score then
                arr[store_idx], arr[i] = arr[i], arr[store_idx]
                store_idx = store_idx + 1
            end
        end
        
        -- Move pivot to its final position
        arr[store_idx], arr[right] = arr[right], arr[store_idx]
        return store_idx
    end
    
    -- Iterative quickselect to find top k elements
    -- After this, the first max_items elements will be the top scoring ones
    local left = 1
    local right = n
    local k = max_items
    
    while left < right do
        -- Choose pivot (median-of-three for better performance)
        local mid = math.floor((left + right) / 2)
        local pivot_idx
        
        if scored[left].score >= scored[mid].score then
            if scored[mid].score >= scored[right].score then
                pivot_idx = mid
            elseif scored[left].score >= scored[right].score then
                pivot_idx = right
            else
                pivot_idx = left
            end
        else
            if scored[left].score >= scored[right].score then
                pivot_idx = left
            elseif scored[mid].score >= scored[right].score then
                pivot_idx = right
            else
                pivot_idx = mid
            end
        end
        
        pivot_idx = partition(scored, left, right, pivot_idx)
        
        if pivot_idx == k then
            break
        elseif pivot_idx < k then
            left = pivot_idx + 1
        else
            right = pivot_idx - 1
        end
    end
    
    -- Extract top k items
    local results = {}
    for i = 1, max_items do
        table.insert(results, scored[i].item)
    end
    
    return results
end

--- Read a single file asynchronously using libuv with caching (internal function)
--- @param filepath string
--- @param callback function(string|nil, string|nil) Called with (content, error)
--- @param use_cache? boolean # Whether to use file cache (default: true)
local function read_file_async(filepath, callback, use_cache)
    use_cache = use_cache ~= false  -- Default to true unless explicitly false
    
    -- Check if already cached (only if caching is enabled)
    if use_cache and file_cache[filepath] and file_cache[filepath].content then
        callback(file_cache[filepath].content, nil)
        return
    end
    
    -- Check if already loading (only if caching is enabled)
    if use_cache and file_cache[filepath] and file_cache[filepath].loading then
        -- Add callback to pending list
        table.insert(file_cache[filepath].pending_callbacks, callback)
        return
    end
    
    -- Mark as loading and add the initial callback to pending list (only if caching is enabled)
    if use_cache then
        file_cache[filepath] = { loading = true, pending_callbacks = { callback } }
    end
    
    -- Helper to handle errors for this specific filepath
    local function handle_error(error_msg)
        if use_cache then
            local pending = file_cache[filepath] and file_cache[filepath].pending_callbacks or {}
            file_cache[filepath] = nil
            vim.schedule(function()
                for _, cb in ipairs(pending) do
                    cb(nil, error_msg)
                end
            end)
        else
            vim.schedule(function()
                callback(nil, error_msg)
            end)
        end
    end
    
    uv.fs_open(filepath, 'r', 438, function(err_open, fd)
        if err_open or not fd then
            handle_error(err_open or 'Failed to open file')
            return
        end
        
        uv.fs_fstat(fd, function(err_stat, stat)
            if err_stat or not stat then
                uv.fs_close(fd, function() end)
                handle_error(err_stat or 'Failed to stat file')
                return
            end
            
            uv.fs_read(fd, stat.size, 0, function(err_read, data)
                uv.fs_close(fd, function() end)
                
                if err_read then
                    handle_error(err_read)
                else
                    if use_cache then
                        local pending = file_cache[filepath] and file_cache[filepath].pending_callbacks or {}
                        file_cache[filepath] = { content = data }
                        vim.schedule(function()
                            for _, cb in ipairs(pending) do
                                cb(data, nil)
                            end
                        end)
                    else
                        vim.schedule(function()
                            callback(data, nil)
                        end)
                    end
                end
            end)
        end)
    end)
end

--- Read dictionary files asynchronously and concatenate the content
--- Accepts either a single file path (string) or multiple file paths (string[])
--- @param files string|string[] # Single file path or list of dictionary file paths
--- @param callback function(string|nil) Called with content or nil on error
--- @param use_cache? boolean # Whether to use file cache (default: true)
function M.read_dictionary_files_async(files, callback, use_cache)
    use_cache = use_cache ~= false  -- Default to true unless explicitly false
    
    -- Handle single file case - convert to array
    if type(files) == 'string' then
        files = { files }
    end
    
    if not files or #files == 0 then
        callback(nil)
        return
    end
    
    -- Read all files asynchronously (each file uses per-file caching based on use_cache)
    local content_parts = {}
    local remaining = #files
    
    for i, filepath in ipairs(files) do
        read_file_async(filepath, function(content, err)
            -- Treat errors as empty content and continue
            content_parts[i] = (not err and content) or ''
            
            remaining = remaining - 1
            
            if remaining == 0 then
                -- All files processed (some may have failed)
                local full_content = table.concat(content_parts, '\n')
                -- Only return nil if content is empty or whitespace only
                if full_content == '' or full_content:match('^%s*$') then
                    callback(nil)
                else
                    callback(full_content)
                end
            end
        end, use_cache)
    end
end

return M
