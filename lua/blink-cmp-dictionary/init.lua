--- @module 'blink.cmp'

local default = require('blink-cmp-dictionary.default')
local utils = require('blink-cmp-dictionary.utils')
local log = require('blink-cmp-dictionary.log')
local Job = require('plenary.job')

--- @type blink.cmp.Source
local DictionarySource = {}
--- @type blink-cmp-dictionary.Options
local dictionary_source_config

local function create_job_from_documentation_command(documentation_command)
    return Job:new({
        command = utils.get_option(documentation_command.get_command),
        args = utils.get_option(documentation_command.get_command_args),
    })
end

--- @param opts blink-cmp-dictionary.Options
function DictionarySource.new(opts)
    log.setup({ title = 'blink-cmp-dictionary' })
    local self = setmetatable({}, { __index = DictionarySource })
    dictionary_source_config = vim.tbl_deep_extend("force", default, opts or {})
    return self
end

function DictionarySource:get_completions(context, callback)
    local items = {}
    local cancel_fun = function() end
    local transformed_callback = function()
        callback({
            is_incomplete_forward = false,
            is_incomplete_backward = false,
            items = vim.tbl_values(items)
        })
    end
    local prefix = utils.get_option(dictionary_source_config.get_prefix, context)
    local cmd = utils.get_option(dictionary_source_config.get_command)
    local cmd_args = utils.get_option(dictionary_source_config.get_command_args, prefix)
    local cat_writer = nil
    local dictionary_directories = utils.get_option(dictionary_source_config.dictionary_directories)
    local get_all_text_files = function()
        local files = {}
        for _, dir in ipairs(dictionary_directories) do
            for _, file in ipairs(vim.fn.globpath(dir, '**/*.txt', true, true)) do
                table.insert(files, file)
            end
        end
        return files
    end
    if utils.truthy(dictionary_directories) then
        cat_writer = Job:new({
            command = 'cat',
            args = get_all_text_files(),
        })
    end
    local job = Job:new({
        command = cmd,
        args = cmd_args,
        on_exit = function(j, code, _)
            if code ~= 0 and not j:stderr_result() then
                log.warn('failed to run cmd:', cmd, 'args:', cmd_args, 'stderr:', j:stderr_result())
            end
            local output = table.concat(j:result(), '\n')
            if utils.truthy(output) then
                local match_list = utils.get_option(dictionary_source_config.seperate_output, output)
                vim.iter(match_list):each(function(match)
                    items[match] = {
                        label = match.label,
                        insertText = match.insert_text,
                        kind = vim.lsp.protocol.CompletionItemKind.Text,
                        documentation = match.documentation,
                    }
                end)
            end
        end,
        writer = cat_writer,
    })
    job:after(transformed_callback)
    if utils.get_option(dictionary_source_config.async) then
        cancel_fun = function() job:shutdown(0, nil) end
        job:start()
    else
        job:sync()
    end
    return cancel_fun
end

function DictionarySource:resolve(item, callback)
    local transformed_callback = function()
        callback(item)
    end
    if type(item.documentation) == 'string' then
        transformed_callback()
        return
    end
    local job = create_job_from_documentation_command(item.documentation)
    job:after(function()
        if utils.truthy(job:result()) then
            ---@diagnostic disable-next-line: undefined-field
            item.documentation = item.documentation.resolve_documentation(table.concat(job:result(), '\n'))
        else
            item.documentation = nil
        end
        transformed_callback()
    end)
    if utils.get_option(dictionary_source_config.async) then
        job:start()
    else
        job:sync()
    end
end

-- TODO: add highlight
-- vim.api.nvim_set_hl(0, 'BlinkCmpDictionary', { link = 'Search', default = true })
-- local highlight_ns_id = 0
-- pcall(function()
--     highlight_ns_id = require('blink.cmp.config').appearance.highlight_ns
-- end)
return DictionarySource
