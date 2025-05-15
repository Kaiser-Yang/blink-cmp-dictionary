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

return M
