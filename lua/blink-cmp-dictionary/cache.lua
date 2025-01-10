local M = {}
local cache = {}

function M.reload()
    cache = {}
end

--- @param keys string|string[]
function M.get(keys)
    keys = type(keys) == 'table' and keys or { keys }
    local res = nil
    for _, key in ipairs(keys) do
        if cache[key] then
            res = cache[key]
        else
            res = nil
            break
        end
    end
    return res
end

--- @param keys string|string[]
--- @param value? any
function M.set(keys, value)
    keys = type(keys) == 'table' and keys or { keys }
    local pre = nil
    local last_key = nil
    local now = cache
    for _, key in ipairs(keys) do
        if not now[key] then
            now[key] = {}
        end
        pre = now
        last_key = key
        now = now[key]
    end
    pre[last_key] = value
end

return M
