--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for fuzzy search
--- Uses async file reading and direct fuzzy matching without trie structures

local M = {}
local utils = require('blink-cmp-dictionary.utils')

--- @type table<string, string[]> # filepath -> list of words
local file_word_lists = {}

--- Load dictionary files into memory with file-based caching
--- @param files string[] # List of dictionary file paths
--- @param separate_output? function # Function to separate file content into words
--- @param callback function(boolean) # Callback called with success status
function M.load_dictionaries(files, separate_output, callback)
    if not files or #files == 0 then
        -- Clear all cached words
        file_word_lists = {}
        if callback then
            callback(true)
        end
        return
    end
    
    -- Create a set of current files for quick lookup
    local current_files = {}
    for _, file in ipairs(files) do
        current_files[file] = true
    end
    
    -- Remove words from files that are no longer in the list
    for filepath, _ in pairs(file_word_lists) do
        if not current_files[filepath] then
            file_word_lists[filepath] = nil
        end
    end
    
    -- Load new files asynchronously
    local files_to_load = {}
    for _, filepath in ipairs(files) do
        if not file_word_lists[filepath] then
            table.insert(files_to_load, filepath)
        end
    end
    
    if #files_to_load == 0 then
        -- All files already cached
        if callback then
            callback(true)
        end
        return
    end
    
    -- Use async file reading from utils
    local remaining = #files_to_load
    for _, filepath in ipairs(files_to_load) do
        utils.read_file_async(filepath, function(content, err)
            remaining = remaining - 1
            
            if content and not err then
                -- Parse content into words using separate_output
                local words = separate_output(content)
                file_word_lists[filepath] = words
            else
                file_word_lists[filepath] = {}
            end
            
            if remaining == 0 and callback then
                callback(true)
            end
        end)
    end
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
    
    -- Collect all words from all cached files
    local all_words = {}
    local seen = {}
    
    for _, word_list in pairs(file_word_lists) do
        for _, word in ipairs(word_list) do
            if not seen[word] then
                table.insert(all_words, word)
                seen[word] = true
            end
        end
    end
    
    -- Use get_top_matches to perform fuzzy matching and return top results
    return utils.get_top_matches(all_words, prefix, max_results)
end

--- Clear the cache
function M.clear_cache()
    file_word_lists = {}
end

--- Get cache statistics
--- @return { word_count: number, file_count: number }
function M.get_stats()
    local total_words = 0
    local file_count = 0
    local seen = {}
    
    for _, word_list in pairs(file_word_lists) do
        for _, word in ipairs(word_list) do
            if not seen[word] then
                total_words = total_words + 1
                seen[word] = true
            end
        end
        file_count = file_count + 1
    end
    
    return {
        word_count = total_words,
        file_count = file_count,
    }
end

return M
