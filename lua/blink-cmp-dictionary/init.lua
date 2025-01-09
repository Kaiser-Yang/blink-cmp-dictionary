--- @module 'blink.cmp'

local default = require('blink-cmp-dictionary.default')
local utils = require('blink-cmp-dictionary.utils')
local log = require('blink-cmp-dictionary.log')

local DictionarySource = {}
DictionarySource.__index = DictionarySource

--- @param opts blink-cmp-dictionary.Options
function DictionarySource.new(opts)
    log.setup({ title = 'blink-cmp-dictionary' })
    local self = setmetatable({}, DictionarySource)
    self.config = vim.tbl_deep_extend("force", default, opts or {})
    return self
end

--- We always do this synchronously, let blink handle the async part
--- @param context blink.cmp.Context
function DictionarySource:get_completions(context, callback)
    local prefix = utils.get_option(self.config.get_prefix, context)
    local prefix_min_len = utils.get_option(self.config.prefix_min_len, context, prefix)
    if #prefix < prefix_min_len then
        log.debug('prefix is too short:', prefix,
            '\n',
            'required min length:', prefix_min_len)
        callback()
        return
    end
    local search_cmd = vim.tbl_map(function(arg)
        return arg:gsub('${prefix}', prefix)
    end, utils.get_option(self.config.get_command, context, prefix))
    if not utils.truthy(search_cmd) then
        log.warn('get empty command from config.get_command')
        callback()
        return
    end
    log.trace('search command:', search_cmd)
    local match_list = {}
    vim.system(search_cmd, nil, function(result)
        if result.code ~= 0 and utils.truthy(result.stderr) then
            log.error('search command failed:', search_cmd,
                '\n',
                'with error code:', result.code,
                '\n',
                'stderr:' .. result.stderr)
            return
        end
        if utils.truthy(result.stdout) then
            local separator = utils.get_option(self.config.output_separator, context, prefix)
            match_list = vim.split(result.stdout, separator)
        else
            log.trace('search command return empty result')
        end
    end):wait()
    local items = {}
    vim.iter(match_list):each(function(match)
        items[match] = {
            label = match,
            kind = vim.lsp.protocol.CompletionItemKind.Text,
            insertText = match,
        }
    end)
    callback({
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = vim.tbl_values(items)
    })
end

function DictionarySource:resolve(item, callback)
    if utils.truthy(utils.get_option(self.config.documentation.enable, item)) then
        local doc_cmd = vim.tbl_map(function(arg)
            return arg:gsub('${word}', item.label)
        end, utils.get_option(self.config.documentation.get_command, item))
        if not utils.truthy(doc_cmd) then
            log.warn('get empty command from config.documentation.get_command')
            callback(item)
            return
        end
        log.trace('documentation command:', doc_cmd)
        vim.system(doc_cmd, nil, function(result)
            if result.code ~= 0 and utils.truthy(result.stderr) then
                log.error('documentation command failed:', doc_cmd,
                    '\n',
                    'with error code:', result.code,
                    '\n',
                    utils.truthy(result.stderr) and 'stderr: ' .. result.stderr or '')
            end
            if utils.truthy(result.stdout) then
                item.documentation = result.stdout
            else
                log.debug('documentation command return empty result')
            end
        end):wait()
    else
        log.debug('documentation is disabled')
    end
    callback(item)
end

-- TODO: add highlight
-- vim.api.nvim_set_hl(0, 'BlinkCmpDictionary', { link = 'Search', default = true })
-- local highlight_ns_id = 0
-- pcall(function()
--     highlight_ns_id = require('blink.cmp.config').appearance.highlight_ns
-- end)
return DictionarySource
