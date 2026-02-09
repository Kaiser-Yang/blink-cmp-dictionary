--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for fuzzy search similar to fzf
--- Uses a trie data structure with suffix indexing for efficient fuzzy matching
--- It runs synchronously and may have performance issues with large dictionaries

local M = {}

--- @class blink-cmp-dictionary.TrieNode
--- @field children table<string, blink-cmp-dictionary.TrieNode> # Child nodes
--- @field words table<string, table<string, boolean>> # words[word][filepath] = true for active words
--- @field is_end boolean # Whether this is the end of a word

--- @type blink-cmp-dictionary.TrieNode
local trie_root = { children = {}, words = {}, is_end = false }

--- @type table<string, string[]> # filepath -> list of words
local file_word_lists = {}

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

--- Insert a word into the trie for all its substrings
--- @param word string
--- @param filepath string
local function trie_insert(word, filepath)
    local word_lower = word:lower()
    
    -- Insert for all substrings starting at each position
    for start_pos = 1, #word_lower do
        local node = trie_root
        
        -- Build path from this starting position
        for i = start_pos, #word_lower do
            local char = word_lower:sub(i, i)
            if not node.children[char] then
                node.children[char] = { children = {}, words = {}, is_end = false }
            end
            node = node.children[char]
            
            -- Store the original word and which file it's from
            if not node.words[word] then
                node.words[word] = {}
            end
            node.words[word][filepath] = true
        end
    end
end

--- Remove a word from the trie (remove filepath association)
--- @param word string
--- @param filepath string
local function trie_remove(word, filepath)
    local word_lower = word:lower()
    
    -- Remove from all substrings starting at each position
    for start_pos = 1, #word_lower do
        local node = trie_root
        
        -- Traverse path from this starting position
        for i = start_pos, #word_lower do
            local char = word_lower:sub(i, i)
            if not node.children[char] then
                break -- Path doesn't exist
            end
            node = node.children[char]
            
            -- Remove filepath association
            if node.words[word] then
                node.words[word][filepath] = nil
                -- If no more files reference this word, remove it completely
                if next(node.words[word]) == nil then
                    node.words[word] = nil
                end
            end
        end
    end
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

--- Search in trie starting from a node with a pattern
--- @param pattern string
--- @return table<string, boolean> # Set of matching words
local function trie_search_fuzzy(pattern)
    if pattern == "" then
        return {}
    end
    
    local pattern_lower = pattern:lower()
    local first_char = pattern_lower:sub(1, 1)
    local results = {}
    
    -- Start search from nodes that match the first character
    if trie_root.children[first_char] then
        -- Collect all words that pass through this node and have active file references
        for word, files in pairs(trie_root.children[first_char].words) do
            -- Only include words that have at least one active file
            if next(files) then
                results[word] = true
            end
        end
    end
    
    return results
end

--- Load dictionary files into memory with file-based caching
--- @param files string[] # List of dictionary file paths
--- @return boolean # Success status
function M.load_dictionaries(files)
    if not files or #files == 0 then
        -- Remove all words from all files from trie
        for filepath, word_list in pairs(file_word_lists) do
            for _, word in ipairs(word_list) do
                trie_remove(word, filepath)
            end
        end
        return true
    end
    
    -- Create a set of current files for quick lookup
    local current_files = {}
    for _, file in ipairs(files) do
        current_files[file] = true
    end
    
    -- Remove words from files that are no longer in the list
    for filepath, word_list in pairs(file_word_lists) do
        if not current_files[filepath] then
            for _, word in ipairs(word_list) do
                trie_remove(word, filepath)
            end
        end
    end
    
    -- Load or re-enable files as needed
    for _, filepath in ipairs(files) do
        local cached_words = file_word_lists[filepath]
        
        -- Load file if not cached
        if not cached_words then
            local words = load_file(filepath)
            file_word_lists[filepath] = words
            -- Add words to trie
            for _, word in ipairs(words) do
                trie_insert(word, filepath)
            end
        else
            -- Re-add words if they were removed
            for _, word in ipairs(cached_words) do
                trie_insert(word, filepath)
            end
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
    
    -- Get candidate words from trie
    local candidates = trie_search_fuzzy(prefix)
    
    -- Score and filter candidates
    local matches = {}
    for word, _ in pairs(candidates) do
        local score = fuzzy_match_score(word, prefix)
        if score then
            table.insert(matches, {word = word, score = score})
        end
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
    file_word_lists = {}
    trie_root = { children = {}, words = {}, is_end = false }
end

--- Get cache statistics
--- @return { word_count: number, file_count: number }
function M.get_stats()
    local total_words = 0
    local file_count = 0
    
    for _, word_list in pairs(file_word_lists) do
        total_words = total_words + #word_list
        file_count = file_count + 1
    end
    
    return {
        word_count = total_words,
        file_count = file_count,
    }
end

return M
