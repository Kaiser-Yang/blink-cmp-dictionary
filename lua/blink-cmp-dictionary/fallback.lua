--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for fuzzy search similar to fzf
--- It runs synchronously and may have performance issues with large dictionaries

local M = {}

--- @class blink-cmp-dictionary.FileCache
--- @field words string[] # Cached words from this file
--- @field mtime number # Modification time of the file
--- @field enabled boolean # Whether this cache entry is currently enabled

--- @type table<string, blink-cmp-dictionary.FileCache>
local file_caches = {}

--- Get file modification time
--- @param filepath string
--- @return number|nil
local function get_file_mtime(filepath)
    local stat = vim.uv.fs_stat(filepath)
    return stat and stat.mtime.sec or nil
end

--- Load a single dictionary file into cache
--- @param filepath string
--- @return string[] # Words from this file
local function load_file(filepath)
    local words = {}
    local f = io.open(filepath, 'r')
    if f then
        for line in f:lines() do
            local word = line:match("^%s*(.-)%s*$") -- trim whitespace
            if word and word ~= "" then
                table.insert(words, word)
            end
        end
        f:close()
    end
    return words
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
    local last_pos = 0
    
    for _, pos in ipairs(match_positions) do
        -- Bonus for matches at the beginning
        if pos == 1 then
            score = score + 100
        end
        
        -- Bonus for consecutive matches
        if pos == last_pos + 1 then
            score = score + 50
        end
        
        -- Penalty for later positions (prefer earlier matches)
        score = score - pos
        
        last_pos = pos
    end
    
    -- Bonus for shorter words (prefer exact or close matches)
    score = score + (100 - #word_lower)
    
    return score
end

--- Load dictionary files into memory with file-based caching
--- @param files string[] # List of dictionary file paths
--- @return boolean # Success status
function M.load_dictionaries(files)
    if not files or #files == 0 then
        file_caches = {}
        return true
    end
    
    -- Create a set of current files for quick lookup
    local current_files = {}
    for _, file in ipairs(files) do
        current_files[file] = true
    end
    
    -- Mark cached files that are no longer in the list as disabled
    for filepath, cache in pairs(file_caches) do
        if not current_files[filepath] then
            cache.enabled = false
        end
    end
    
    -- Load or refresh files as needed
    for _, filepath in ipairs(files) do
        local mtime = get_file_mtime(filepath)
        local cached = file_caches[filepath]
        
        -- Load file if not cached or if modified
        if not cached or not mtime or cached.mtime ~= mtime then
            local words = load_file(filepath)
            file_caches[filepath] = {
                words = words,
                mtime = mtime or 0,
                enabled = true,
            }
        else
            -- Re-enable if it was disabled
            cached.enabled = true
        end
    end
    
    return true
end

--- Search for words matching the given prefix with fuzzy matching
--- @param prefix string # The search prefix
--- @param max_results? number # Maximum number of results to return (default: 100)
--- @return string[] # List of matching words, sorted by relevance
function M.search(prefix, max_results)
    max_results = max_results or 100
    
    if not prefix or prefix == "" then
        return {}
    end
    
    local matches = {} -- Store {word, score} pairs
    local result_set = {} -- For deduplication across files
    
    -- Search across all cached files
    for _, file_cache in pairs(file_caches) do
        -- Skip disabled caches
        if not file_cache.enabled then
            goto continue
        end
        
        for _, word in ipairs(file_cache.words) do
            -- Skip if already in results
            if not result_set[word] then
                local score = fuzzy_match_score(word, prefix)
                if score then
                    table.insert(matches, {word = word, score = score})
                    result_set[word] = true
                end
            end
        end
        
        ::continue::
    end
    
    -- Sort by score (higher is better)
    table.sort(matches, function(a, b)
        return a.score > b.score
    end)
    
    -- Extract top results
    local results = {}
    for i = 1, math.min(#matches, max_results) do
        table.insert(results, matches[i].word)
    end
    
    return results
end

--- Clear the cache
function M.clear_cache()
    file_caches = {}
end

--- Get cache statistics
--- @return { word_count: number, file_count: number }
function M.get_stats()
    local total_words = 0
    local file_count = 0
    
    for _, file_cache in pairs(file_caches) do
        if file_cache.enabled then
            total_words = total_words + #file_cache.words
            file_count = file_count + 1
        end
    end
    
    return {
        word_count = total_words,
        file_count = file_count,
    }
end

return M
