local log = require('blink-cmp-dictionary.log')
log.setup({ title = 'blink-cmp-dictionary' })
local utils = require('blink-cmp-dictionary.utils')

-- Default iskeyword value matching vim's default
local DEFAULT_ISKEYWORD = '@,48-57,_,192-255'

-- Cache for word_patterns: maps iskeyword string to compiled pattern
local pattern_cache = {}

--- Parse vim's iskeyword option and build an lpeg pattern
--- @param iskeyword string # The iskeyword string (e.g., "@,48-57,_,192-255")
--- @return table # An lpeg pattern matching word characters
local function build_word_character_pattern(iskeyword)
    local char_pattern = vim.lpeg.P(false) -- Start with a pattern that matches nothing
    
    -- Split by comma
    for part in iskeyword:gmatch('[^,]+') do
        part = vim.trim(part)
        
        if part == '@' then
            -- @ means all alphabetic characters (a-z, A-Z)
            char_pattern = char_pattern + vim.lpeg.R("az", "AZ")
        elseif #part == 1 then
            -- Single character like "_" or "-"
            -- Check this before range patterns to avoid matching "-" as a range
            -- Note: Most special lpeg characters don't need escaping in P()
            char_pattern = char_pattern + vim.lpeg.P(part)
        else
            -- Try to match as numeric range like "48-57" or "192-255"
            local start_str, end_str = part:match('^(%d+)%-(%d+)$')
            if start_str and end_str then
                local start_num = tonumber(start_str)
                local end_num = tonumber(end_str)
                -- Validate range: must be numbers, within byte range (0-255), and properly ordered
                if start_num and end_num and start_num >= 0 and end_num <= 255 and start_num <= end_num then
                    -- Convert numbers to characters and create range string (e.g., "09" for digits)
                    local start_char = string.char(start_num)
                    local end_char = string.char(end_num)
                    -- vim.lpeg.R expects each range as a 2-character string
                    char_pattern = char_pattern + vim.lpeg.R(start_char .. end_char)
                end
            else
                -- Try to match as character range like "a-z" or "A-Z"
                local start_char, end_char = part:match('^(.)%-(.)$')
                if start_char and end_char then
                    -- vim.lpeg.R expects each range as a 2-character string
                    char_pattern = char_pattern + vim.lpeg.R(start_char .. end_char)
                end
            end
        end
        -- Note: Negative ranges (e.g., "^,") and other advanced iskeyword features
        -- are not commonly used and can be added if needed
    end
    
    return char_pattern
end

--- Build the word_pattern based on current iskeyword setting
--- Uses caching with iskeyword as key to avoid rebuilding patterns
--- @param bufnr number|nil # Buffer number (nil uses current buffer)
--- @return table # An lpeg pattern for matching words
local function build_word_pattern(bufnr)
    local iskeyword
    if bufnr then
        iskeyword = vim.bo[bufnr].iskeyword or DEFAULT_ISKEYWORD
    else
        iskeyword = vim.bo.iskeyword or DEFAULT_ISKEYWORD
    end
    
    -- Check if we have a cached pattern for this iskeyword
    if pattern_cache[iskeyword] then
        return pattern_cache[iskeyword]
    end
    
    -- Build new pattern and cache it
    local word_character = build_word_character_pattern(iskeyword)
    local non_word_character = vim.lpeg.P(1) - word_character
    
    -- A word can start with any number of non-word characters, followed by
    -- at least one word character, and then any number of non-word characters.
    -- The word part is captured.
    local pattern = vim.lpeg.Ct(
        (
            non_word_character ^ 0
            * vim.lpeg.C(word_character ^ 1)
            * non_word_character ^ 0
        ) ^ 0
    )
    
    -- Cache the pattern with iskeyword as key
    pattern_cache[iskeyword] = pattern
    
    return pattern
end

--- @param prefix string # The prefix to be matched
--- @param bufnr number|nil # Buffer number (nil uses current buffer)
--- @return string
local function match_prefix(prefix, bufnr)
    -- Build word_pattern dynamically based on current iskeyword setting
    local word_pattern = build_word_pattern(bufnr)
    local match_res = vim.lpeg.match(word_pattern, prefix)
    if not match_res or #match_res == 0 then
        return ''
    end
    
    local result = match_res[#match_res]
    
    -- Filter out common punctuation symbols at the beginning
    -- This includes: . , ; : ! ? ' " ` ( ) [ ] { } < > / \ | @ # $ % ^ & * + = ~ -
    local cleaned_result = result:gsub("^[%.,%%;:!?'\"%(%)%[%]{}%s<>/\\|@#$%%^&*+=~-]+", "")
    
    return cleaned_result
end

local function default_get_command()
    -- Check for available search tools
    if utils.command_found('fzf') then
        return 'fzf'
    elseif utils.command_found('rg') then
        return 'rg'
    elseif utils.command_found('grep') then
        return 'grep'
    end
    
    -- Fallback to empty string (will use pure Lua implementation)
    return ''
end

local function default_get_command_args(prefix, command)
    if command == 'fzf' then
        return {
            '--filter=' .. prefix,
            '--sync',
            '-i',
        }
    elseif command == 'rg' then
        return {
            '--color=never',
            '--no-line-number',
            '--no-messages',
            '--no-filename',
            '--ignore-case',
            '-F', --Fixed strings
            '--',
            prefix,
        }
    elseif command == 'grep' then
        return {
            '--color=never',
            '--ignore-case',
            '-F', --Fixed strings
            '--',
            prefix,
        }
    else
        return {}
    end
end

local function default_on_error(return_value, standard_error)
    if utils.truthy(standard_error) then
        vim.schedule(function()
            log.warn('Dictionary file operation failed',
                '\n',
                'with error code:', return_value,
                '\n',
                'stderr:', standard_error)
        end)
    end
    return false  -- Always return false to continue
end

local function default_separate_output(output)
    local items = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(items, line)
    end
    return items
end

local function default_get_label(item)
    return item
end

local function default_get_insert_text(item)
    return item
end

local function default_get_kind_name(_)
    return 'Dict'
end

local function default_get_documentation(item)
    return {
        get_command = function()
            return utils.command_found('wn') and 'wn' or ''
        end,
        get_command_args = function()
            return { item, '-over' }
        end,
        resolve_documentation = function(output)
            return output
        end,
        on_error = default_on_error,
    }
end

local function default_get_prefix(context)
    return match_prefix(context.line:sub(1, context.cursor[2]), context.bufnr)
end

local function default_capitalize_first(context, match)
    local prefix = default_get_prefix(context)
    return string.match(prefix, '^%u') ~= nil and match.label:match('^%l*$') ~= nil
end

local function default_capitalize_whole_word(context, match)
    local prefix = default_get_prefix(context)
    return string.match(prefix, '^%u%u') ~= nil and match.label:match('^%l*$') ~= nil
end

--- @type blink-cmp-dictionary.Options
return {
    -- Return the word before the cursor
    get_prefix = default_get_prefix,
    -- Where is your dictionary files
    dictionary_files = nil,
    -- Where is your dictionary directories, all the .txt files in the directory will be loaded
    dictionary_directories = nil,
    -- Force using fallback mode instead of external commands (default: vim.fn.executable('fzf') == 0)
    force_fallback = vim.fn.executable('fzf') == 0,
    -- Whether or not to capitalize the first letter of the word
    capitalize_first = default_capitalize_first,
    -- Whether or not to capitalize the whole word
    capitalize_whole_word = default_capitalize_whole_word,
    -- Whether or not to decapitalize the first letter of the word
    decapitalize_first = false,
    -- Whether or not to decapitalize the whole word
    decapitalize_whole_word = false,
    -- The command to get the word list
    get_command = default_get_command,
    get_command_args = default_get_command_args,
    kind_icons = {
        Dict = '󰘝',
    },
    -- How to parse the output
    separate_output = default_separate_output,
    get_label = default_get_label,
    get_insert_text = default_get_insert_text,
    get_kind_name = default_get_kind_name,
    get_documentation = default_get_documentation,
    on_error = default_on_error,
}
