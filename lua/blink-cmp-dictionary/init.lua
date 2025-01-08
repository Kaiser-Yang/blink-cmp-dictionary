--- @module 'blink.cmp'

--- @class (exact) blink-cmp-dictionary.DocumentationOptions
--- @field enable boolean|fun(item: blink.cmp.CompletionItem): boolean
--- @field get_command? string[]|fun(item: blink.cmp.CompletionItem): string[]

--- @class (exact) blink-cmp-dictionary.Options
--- @field get_prefix? string|fun(context: blink.cmp.Context): string
--- @field prefix_min_len? number|fun(context: blink.cmp.Context, prefix: string): number
--- @field get_command? string[]|fun(context: blink.cmp.Context, prefix: string): string[]
--- @field output_separator? string|fun(context: blink.cmp.Context, prefix: string): string
--- @field documentation? blink-cmp-dictionary.DocumentationOptions

--- @class blink-cmp-dictionary.DictionarySource : blink.cmp.Source
--- @field get_completions? fun(self: blink.cmp.Source, context: blink.cmp.Context, callback: fun(response: blink.cmp.CompletionResponse | nil)):  nil

local default = require('blink-cmp-dictionary.default')
local utils = require('blink-cmp-dictionary.utils')

local DictionarySource = {}
DictionarySource.__index = DictionarySource

--- @param opts blink-cmp-dictionary.Options
function DictionarySource.new(opts)
    local self = setmetatable({}, DictionarySource)
    self.config = vim.tbl_deep_extend("force", default, opts or {})
    return self
end

--- We always do this synchronously, let blink handle the async part
--- @param context blink.cmp.Context
function DictionarySource:get_completions(context, callback)
    local prefix = utils.get_option(self.config.get_prefix, context)
    if #prefix < utils.get_option(self.config.prefix_min_len, context, prefix) then
        -- TODO: add log here
        callback()
        return
    end
    local search_cmd = vim.tbl_map(function(arg)
        return arg:gsub('${prefix}', prefix)
    end, utils.get_option(self.config.get_command, context, prefix))
    if not utils.truthy(search_cmd) then
        -- TODO: add log here
        callback()
        return
    end
    local match_list = {}
    vim.system(search_cmd, nil, function(result)
        if not utils.truthy(result.code) then
            -- TODO: add log here
        end
        if utils.truthy(result.stdout) then
            local separator = utils.get_option(self.config.output_separator, context, prefix)
            match_list = vim.split(result.stdout, separator)
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
            -- TODO: add log here
            callback(item)
            return
        end
        vim.system(doc_cmd, nil, function(result)
            if result.code ~= 0 then
                -- TODO: add log here
            end
            if utils.truthy(result.stdout) then
                item.documentation = result.stdout
            end
        end):wait()
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
