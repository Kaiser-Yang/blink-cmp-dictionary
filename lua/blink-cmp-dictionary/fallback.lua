--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for substring search similar to grep -F
--- It runs synchronously and may have performance issues with large dictionaries

local M = {}

--- @class blink-cmp-dictionary.FileCache
--- @field words string[] # Cached words from this file
--- @field mtime number # Modification time of the file

--- @type table<string, blink-cmp-dictionary.FileCache>
local file_caches = {}

--- Get file modification time
--- @param filepath string
--- @return number|nil
local function get_file_mtime(filepath)
    local stat = vim.loop.fs_stat(filepath)
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
    
    -- Remove cached files that are no longer in the list
    for filepath, _ in pairs(file_caches) do
        if not current_files[filepath] then
            file_caches[filepath] = nil
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
            }
        end
    end
    
    return true
end

--- Search for words containing the given prefix (case-insensitive substring match)
--- @param prefix string # The search prefix
--- @param max_results? number # Maximum number of results to return (default: 100)
--- @return string[] # List of matching words
function M.search(prefix, max_results)
    max_results = max_results or 100
    
    if not prefix or prefix == "" then
        return {}
    end
    
    local results = {}
    local result_set = {} -- For deduplication across files
    local lower_prefix = prefix:lower()
    local count = 0
    
    -- Search across all cached files
    for _, cache in pairs(file_caches) do
        if count >= max_results then
            break
        end
        
        for _, word in ipairs(cache.words) do
            if count >= max_results then
                break
            end
            
            -- Skip if already in results
            if not result_set[word] then
                local lower_word = word:lower()
                -- Check if prefix is a substring of word
                if lower_word:find(lower_prefix, 1, true) then
                    table.insert(results, word)
                    result_set[word] = true
                    count = count + 1
                end
            end
        end
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
    for _, cache in pairs(file_caches) do
        total_words = total_words + #cache.words
    end
    
    local file_count = 0
    for _ in pairs(file_caches) do
        file_count = file_count + 1
    end
    
    return {
        word_count = total_words,
        file_count = file_count,
    }
end

return M
