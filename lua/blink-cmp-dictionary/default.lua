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
    return utils.command_found('fzf') and 'fzf' or
        utils.command_found('rg') and 'rg' or ''
end

local function default_get_command_args(prefix, command)
    if command == 'fzf' then
        return {
            '--filter=' .. prefix,
            '--sync',
            '--no-sort',
            '-i',
        }
    else
        return {
            '--color=never',
            '--no-line-number',
            '--no-messages',
            '--no-filename',
            '--ignore-case',
            '--',
            prefix,
        }
    end
end

local function default_on_error(return_value, standard_error)

    vim.schedule(function()
        log.error('get_completions failed',
            '\n',
            'with error code:', return_value,
            '\n',
            'stderr:', standard_error)
    end)
    return true
end

--- @type blink-cmp-dictionary.Options
return {
    async = true,
    -- Return the word before the cursor
    get_prefix = function(context)
        return match_prefix(context.line:sub(1, context.cursor[2]))
    end,
    -- Where is your dictionary files
    dictionary_files = nil,
    -- Where is your dictionary directories, all the .txt files in the directory will be loaded
    dictionary_directories = nil,
    -- The command to get the word list
    get_command = default_get_command,
    get_command_args = default_get_command_args,
    kind_icons = {
        Dict = '󰘝',
    },
    -- How to parse the output
    separate_output = function(output)
        local items = {}
        for line in output:gmatch("[^\r\n]+") do
            table.insert(items, {
                label = line,
                insert_text = line,
                -- If you want to disable the documentation feature, just set it to nil
                documentation = {
                    get_command = function()
                        return utils.command_found('wn') and 'wn' or ''
                    end,
                    get_command_args = {
                        line,
                        '-over'
                    },
                    ---@diagnostic disable-next-line: redefined-local
                    resolve_documentation = function(output)
                        return output
                    end
                }
            })
        end
        return items
    end,
    get_kind_name = function(_) return 'Dict' end,
    on_error = default_on_error,
}
