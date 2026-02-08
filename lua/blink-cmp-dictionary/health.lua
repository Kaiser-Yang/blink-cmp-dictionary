local M = {}
local health = vim.health
local utils = require('blink-cmp-dictionary.utils')

--- @param command string
--- @param message? string
--- @return boolean
local function check_command_executable(command, message)
    message = message or ('"' .. command .. '" not found.')
    if not utils.command_found(command) then
        health.warn(message)
        return false
    end
    health.ok('"' .. command .. '" found.')
    return true
end

function M.check()
    health.start('blink-cmp-dictionary')
    check_command_executable('cat')
    if not check_command_executable('fzf', '"fzf" is not installed, try to use "rg" instead') then
        if not check_command_executable('rg', '"rg" is not installed, try to use "grep" instead') then
            check_command_executable('grep')
        end
    end
    check_command_executable('wn')
end

return M
