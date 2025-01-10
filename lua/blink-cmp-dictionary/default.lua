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

--- @type blink-cmp-dictionary.Options
local default
default = {
    async = true,
    get_prefix = function(context)
        return match_prefix(context.line:sub(1, context.cursor[2]))
    end,
    dictionary_directories = { vim.fn.expand('~/.config/nvim/dict/') },
    get_command = 'fzf',
    get_command_args = function(prefix)
        return {
            '--filter=' .. prefix,
            '--sync',
            '--no-sort'
        }
    end,
    separate_output = function(output)
        local items = {}
        for line in output:gmatch("[^\r\n]+") do
            table.insert(items, {
                label = line,
                insert_text = line,
                documentation = {
                    get_command = 'wn',
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
    end
}
return default
