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

---@param x unknown
---@return boolean
local function Boolean(x)
    return not not x
end

---@param str string
---@return boolean
function M.is_capital(str)
    return Boolean(str:find("^%u"))
end

---@param str string
---@return string
function M.capitalize(str)
    local u = str:gsub("^%l", string.upper)
    return u
end

---@param str string
---@return string
function M.decapitalize(str)
    local l = str:gsub("^%u", string.lower)
    return l
end

return M
