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
local default = {
    --- @param context blink.cmp.Context
    --- @return string
    get_prefix = function(context)
        return match_prefix(context.line:sub(1, context.cursor[2]))
    end,
    prefix_min_len = 3,
    -- output will be separated by vim.split(result.stdout, output_separator)
    output_separator = '\n',
    documentation = {
        enable = false,
    }
}
return default
