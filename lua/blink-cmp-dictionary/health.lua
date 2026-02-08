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
    local has_cat = check_command_executable('cat', '"cat" is not installed, will use fallback mode')
    local has_search_tool = false
    
    if has_cat then
        if not check_command_executable('fzf', '"fzf" is not installed, try to use "rg" instead') then
            if not check_command_executable('rg', '"rg" is not installed, try to use "grep" instead') then
                has_search_tool = check_command_executable('grep', '"grep" is not installed, will use fallback mode')
            else
                has_search_tool = true
            end
        else
            has_search_tool = true
        end
    end
    
    if not has_cat or not has_search_tool then
        health.info('Fallback mode will be used: pure Lua substring search (synchronous, may have performance issues)')
        health.info('In fallback mode, plenary.nvim is not required')
    else
        health.info('External commands are available')
        local has_plenary = pcall(require, 'plenary.job')
        if has_plenary then
            health.ok('plenary.nvim is installed')
        else
            health.info('plenary.nvim is not installed, will use fallback mode instead')
        end
    end
    
    check_command_executable('wn', '"wn" is not installed, documentation will not be available')
end

return M
