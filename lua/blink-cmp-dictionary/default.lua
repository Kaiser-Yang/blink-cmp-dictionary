local word_pattern
do
    -- Only support utf-8
    local word_character = vim.lpeg.R("az", "AZ", "09", "\128\255") + vim.lpeg.P("_") + vim.lpeg.P("-")

    local non_word_character = vim.lpeg.P(1) - word_character

    -- A word can start with any number of non-starting characters, followed by
    -- more than one word character, and then any number of non-middle characters.
    -- The word is captured.
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
local default = {
    prefix_min_len = 3,
    --- @param context blink.cmp.Context
    --- @return string
    get_prefix = function(context)
        return match_prefix(context.line:sub(1, context.cursor[2]))
    end,
    rg_additional_args = {
        '--color=never',
        '--no-line-number',
        '--no-messages',
        '--no-filename',
        '--ignore-case', -- or you can use '--case-sensitive' or '--smart-case'
    },
    dictionary_path = {},
    documentation = {
        enable = false,
        --- @return string[]
        get_command = function(_, _)
            return {
                'wn',
                '${word}', -- This will be replaced with the matched word
                '-over'
            }
        end,
    },
}
return default
