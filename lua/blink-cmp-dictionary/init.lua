--- @module 'blink.cmp'

--- @class (exact) blink-cmp-dictionary.DocumentationOptions
--- @field enable boolean
--- @field get_command? string[]|fun(context: blink.cmp.Context, prefix: string): string[]

--- @class (exact) blink-cmp-dictionary.Options
--- @field prefix_min_len? number # Minimum length of prefix to trigger completion
--- @field get_prefix? fun(context: blink.cmp.Context): string # How to get the prefix
--- @field rg_additional_args? string[]| fun(context: blink.cmp.Context, prefix: string): string[] # Additional arguments for rg
--- @field dictionary_path? string[] # The path to the dictionary file
--- @field documentation? blink-cmp-dictionary.DocumentationOptions

--- @class blink-cmp-dictionary.DictionarySource : blink.cmp.Source
--- @field get_completions? fun(self: blink.cmp.Source, context: blink.cmp.Context, callback: fun(response: blink.cmp.CompletionResponse | nil)):  nil

local default = require('blink-cmp-dictionary.default')

local DictionarySource = {}
DictionarySource.__index = DictionarySource

--- @param opts blink-cmp-dictionary.Options
function DictionarySource.new(opts)
    local self = setmetatable({}, DictionarySource)
    self.config = vim.tbl_deep_extend("force", default, opts or {})
    return self
end

--- @param context blink.cmp.Context
function DictionarySource:get_completions(context, resolve)
    local prefix = self.config.get_prefix(context)
    if #prefix < self.config.prefix_min_len then
        resolve()
        return
    end
    local match_list = {}
    local cmd = { 'rg' }
    cmd = vim.list_extend(cmd,
        type(self.config.rg_additional_args) == 'function' and
        self.config.rg_additional_args(context, prefix) or
        self.config.rg_additional_args)
    cmd = vim.list_extend(cmd, { '--', prefix })
    for _, path in ipairs(self.config.dictionary_path) do
        cmd[#cmd + 1] = vim.fn.expand(path)
    end
    vim.system(cmd, nil, function(result)
        if result.code ~= 0 then
            return
        end
        match_list = vim.split(result.stdout, '\n')
    end):wait()
    local items = {}
    vim.iter(match_list):each(function(match)
        items[match] = {
            label = match,
            kind = vim.lsp.protocol.CompletionItemKind.Text,
            insertText = match,
        }
    end)
    if self.config.documentation.enable then
        for _, word in ipairs(match_list) do
            items[word].documentation = {
                --- @param opts blink.cmp.SourceRenderDocumentationOpts
                render = function(opts)
                    cmd = vim.tbl_map(function(arg)
                        return arg:gsub('${word}', opts.item.label)
                    end, self.config.documentation.get_command(context, prefix))
                    local doc
                    vim.system(cmd, nil, function(result)
                        -- 'wn' will always return non-zero, ignore it
                        if result.code ~= 0 and cmd[1] ~= 'wn' then
                            return
                        end
                        if result.stdout and result.stdout ~= '' then
                            doc = result.stdout
                        end
                    end):wait()
                    if doc then
                        opts.default_implementation({ documentation = doc })
                    end
                end
            }
        end
    end
    resolve({
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = vim.tbl_values(items)
    })
end

-- vim.api.nvim_set_hl(0, 'BlinkCmpDictionary', { link = 'Search', default = true })
-- local highlight_ns_id = 0
-- pcall(function()
--     highlight_ns_id = require('blink.cmp.config').appearance.highlight_ns
-- end)
return DictionarySource
