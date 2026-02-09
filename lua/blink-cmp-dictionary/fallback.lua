--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for fuzzy search
--- Uses async file reading and direct fuzzy matching without trie structures

local M = {}
local utils = require('blink-cmp-dictionary.utils')

--- @type table<string, string[]> # filepath -> list of words
local file_word_lists = {}

--- @type table<string, boolean> # filepath -> enabled status
local file_enabled = {}

--- Load dictionary files into memory with file-based caching
--- @param files string[] # List of dictionary file paths
--- @param separate_output? function # Function to separate file content into words
--- @param callback function() # Callback called when loading completes
function M.load_dictionaries(files, separate_output, callback)
    if not files or #files == 0 then
        -- Don't clear cache - just mark all files as disabled
        for filepath, _ in pairs(file_word_lists) do
            file_enabled[filepath] = false
        end
        if callback then
            callback()
        end
        return
    end
    
    -- Create a set of current files for quick lookup
    local current_files = {}
    for _, file in ipairs(files) do
        current_files[file] = true
    end
    
    -- Mark files as enabled or disabled based on current list
    for filepath, _ in pairs(file_word_lists) do
        file_enabled[filepath] = current_files[filepath] or false
    end
    
    -- Mark new files as enabled
    for _, filepath in ipairs(files) do
        file_enabled[filepath] = true
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
            callback()
        end
        return
    end
    
    -- Read all files at once to avoid multiple callback invocations
    -- Note: All files loaded together share the same word list (concatenated content)
    -- This is a trade-off: simpler code and single callback vs per-file word granularity
    utils.read_dictionary_files_async(files_to_load, function(return_code, standard_error, content)
        if content then
            -- Parse content into words using separate_output
            local words = separate_output(content)
            -- Store the same word list for all loaded files
            -- This is acceptable since files are loaded together as a batch
            for _, filepath in ipairs(files_to_load) do
                file_word_lists[filepath] = words
            end
        else
            -- Mark failed files with empty word lists
            for _, filepath in ipairs(files_to_load) do
                file_word_lists[filepath] = {}
            end
        end
        
        if callback then
            callback()
        end
    end, false)  -- Disable cache in utils to let fallback manage its own cache
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
    
    -- Collect all words from enabled cached files only
    local all_words = {}
    local seen = {}
    
    for filepath, word_list in pairs(file_word_lists) do
        -- Only include words from enabled files
        if file_enabled[filepath] then
            for _, word in ipairs(word_list) do
                if not seen[word] then
                    table.insert(all_words, word)
                    seen[word] = true
                end
            end
        end
    end
    
    -- Use get_top_matches to perform fuzzy matching and return top results
    return utils.get_top_matches(all_words, prefix, max_results)
end

return M
