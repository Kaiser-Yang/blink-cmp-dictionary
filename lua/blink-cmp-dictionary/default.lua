local log = require('blink-cmp-dictionary.log')
log.setup({ title = 'blink-cmp-dictionary' })
local utils = require('blink-cmp-dictionary.utils')
local word_pattern
do
    -- Only support utf-8
    local word_character = vim.lpeg.R("az", "AZ", "09", "\128\255") + vim.lpeg.P("_") + vim.lpeg.P("-")

    local non_word_character = vim.lpeg.P(1) - word_character

    -- A word can start with any number of non-word characters, followed by
    -- at least one word character, and then any number of non-word characters.
    -- The word part is captured.
    word_pattern = vim.lpeg.Ct(
        (
            non_word_character ^ 0
            * vim.lpeg.C(word_character ^ 1)
            * non_word_character ^ 0
        ) ^ 0
    )
end

--- @param prefix string # The prefix to be matched
--- @return string
local function match_prefix(prefix)
    local match_res = vim.lpeg.match(word_pattern, prefix)
    return match_res and match_res[#match_res] or ''
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
            log.error('get_completions failed',
                '\n',
                'with error code:', return_value,
                '\n',
                'stderr:', standard_error)
        end)
        return true
    end
    return false
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
    return match_prefix(context.line:sub(1, context.cursor[2]))
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
