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
        -- TODO: add log here
        return true
    end
end

return M
