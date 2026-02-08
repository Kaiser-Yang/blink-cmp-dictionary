--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for substring search similar to grep -F
--- It runs synchronously and may have performance issues with large dictionaries

local M = {}

--- @class blink-cmp-dictionary.FallbackCache
--- @field words string[] # Cached dictionary words
--- @field loaded boolean # Whether the cache is loaded

--- @type blink-cmp-dictionary.FallbackCache
local cache = {
    words = {},
    loaded = false,
}

--- Load dictionary files into memory
--- @param files string[] # List of dictionary file paths
--- @return boolean # Success status
function M.load_dictionaries(files)
    if not files or #files == 0 then
        cache.loaded = true
        cache.words = {}
        return true
    end
    
    local words = {}
    local word_set = {} -- For deduplication
    
    for _, file in ipairs(files) do
        local f = io.open(file, 'r')
        if f then
            for line in f:lines() do
                local word = line:match("^%s*(.-)%s*$") -- trim whitespace
                if word and word ~= "" and not word_set[word] then
                    table.insert(words, word)
                    word_set[word] = true
                end
            end
            f:close()
        end
    end
    
    cache.words = words
    cache.loaded = true
    return true
end

--- Search for words containing the given prefix (case-insensitive substring match)
--- @param prefix string # The search prefix
--- @param max_results? number # Maximum number of results to return (default: 100)
--- @return string[] # List of matching words
function M.search(prefix, max_results)
    max_results = max_results or 100
    
    if not cache.loaded then
        return {}
    end
    
    if not prefix or prefix == "" then
        return {}
    end
    
    local results = {}
    local lower_prefix = prefix:lower()
    local count = 0
    
    -- Perform case-insensitive substring search
    for _, word in ipairs(cache.words) do
        if count >= max_results then
            break
        end
        
        local lower_word = word:lower()
        -- Check if prefix is a substring of word
        if lower_word:find(lower_prefix, 1, true) then
            table.insert(results, word)
            count = count + 1
        end
    end
    
    return results
end

--- Clear the cache
function M.clear_cache()
    cache.words = {}
    cache.loaded = false
end

--- Check if cache is loaded
--- @return boolean
function M.is_loaded()
    return cache.loaded
end

--- Get cache statistics
--- @return { word_count: number, loaded: boolean }
function M.get_stats()
    return {
        word_count = #cache.words,
        loaded = cache.loaded,
    }
end

return M
