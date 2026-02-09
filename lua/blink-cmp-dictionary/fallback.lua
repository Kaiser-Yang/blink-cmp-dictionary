--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for fuzzy search similar to fzf
--- Uses a trie data structure for efficient fuzzy matching
--- It runs synchronously and may have performance issues with large dictionaries

local M = {}

--- @class blink-cmp-dictionary.TrieNode
--- @field children table<string, blink-cmp-dictionary.TrieNode> # Child nodes
--- @field words table<string, boolean> # Words that end at or pass through this node
--- @field is_end boolean # Whether this is the end of a word

--- @class blink-cmp-dictionary.FileCache
--- @field enabled boolean # Whether this cache entry is currently enabled
--- @field word_list string[] # List of words for this file (for enable/disable)

--- @type table<string, blink-cmp-dictionary.FileCache>
local file_caches = {}

--- @type blink-cmp-dictionary.TrieNode
local trie_root = { children = {}, words = {}, is_end = false }

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

--- Insert a word into the trie
--- @param word string
local function trie_insert(word)
    local node = trie_root
    local word_lower = word:lower()
    
    -- Insert into trie character by character
    for i = 1, #word_lower do
        local char = word_lower:sub(i, i)
        if not node.children[char] then
            node.children[char] = { children = {}, words = {}, is_end = false }
        end
        node = node.children[char]
        -- Store the original word at each node it passes through
        node.words[word] = true
    end
    
    node.is_end = true
end

--- Remove a word from the trie
--- @param word string
local function trie_remove(word)
    local word_lower = word:lower()
    local nodes = {}
    local node = trie_root
    
    -- Traverse and collect nodes
    for i = 1, #word_lower do
        local char = word_lower:sub(i, i)
        if not node.children[char] then
            return -- Word not in trie
        end
        table.insert(nodes, { node = node, char = char })
        node = node.children[char]
        -- Remove word from this node's word set
        node.words[word] = nil
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
        -- Collect all words that pass through this node
        local function collect_words(node)
            for word, _ in pairs(node.words) do
                results[word] = true
            end
        end
        collect_words(trie_root.children[first_char])
    end
    
    return results
end

--- Load dictionary files into memory with file-based caching
--- @param files string[] # List of dictionary file paths
--- @return boolean # Success status
function M.load_dictionaries(files)
    if not files or #files == 0 then
        -- Mark all caches as disabled but don't clear them
        for _, cache in pairs(file_caches) do
            if cache.enabled then
                cache.enabled = false
                -- Remove words from trie
                for _, word in ipairs(cache.word_list) do
                    trie_remove(word)
                end
            end
        end
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
            if cache.enabled then
                cache.enabled = false
                -- Remove words from trie
                for _, word in ipairs(cache.word_list) do
                    trie_remove(word)
                end
            end
        end
    end
    
    -- Load or re-enable files as needed
    for _, filepath in ipairs(files) do
        local cached = file_caches[filepath]
        
        -- Load file if not cached
        if not cached then
            local words = load_file(filepath)
            file_caches[filepath] = {
                word_list = words,
                enabled = true,
            }
            -- Add words to trie
            for _, word in ipairs(words) do
                trie_insert(word)
            end
        else
            -- Re-enable if it was disabled
            if not cached.enabled then
                cached.enabled = true
                -- Re-add words to trie
                for _, word in ipairs(cached.word_list) do
                    trie_insert(word)
                end
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
    file_caches = {}
    trie_root = { children = {}, words = {}, is_end = false }
end

--- Get cache statistics
--- @return { word_count: number, file_count: number }
function M.get_stats()
    local total_words = 0
    local file_count = 0
    
    for _, file_cache in pairs(file_caches) do
        if file_cache.enabled then
            total_words = total_words + #file_cache.word_list
            file_count = file_count + 1
        end
    end
    
    return {
        word_count = total_words,
        file_count = file_count,
    }
end

return M
