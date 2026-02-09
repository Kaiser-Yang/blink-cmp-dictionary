local M = {}

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
function M.fuzzy_match_score(word, pattern)
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

--- Sort items by fuzzy match score and return top N results
--- @param items string[] # List of items to score
--- @param pattern string # Pattern to match against
--- @param max_items number # Maximum number of items to return
--- @return string[] # Top N items sorted by score
function M.get_top_matches(items, pattern, max_items)
    if not items or #items == 0 then
        return {}
    end
    
    -- Score all items
    local scored = {}
    for _, item in ipairs(items) do
        local score = M.fuzzy_match_score(item, pattern)
        if score then
            table.insert(scored, {item = item, score = score})
        end
    end
    
    -- Sort by score (higher is better)
    table.sort(scored, function(a, b)
        return a.score > b.score
    end)
    
    -- Extract top results
    local results = {}
    for i = 1, math.min(#scored, max_items) do
        table.insert(results, scored[i].item)
    end
    
    return results
end

return M
