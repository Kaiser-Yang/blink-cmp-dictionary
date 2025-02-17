--- @module 'blink.cmp'

local default = require('blink-cmp-dictionary.default')
local utils = require('blink-cmp-dictionary.utils')
local log = require('blink-cmp-dictionary.log')
local Job = require('plenary.job')

--- @type blink.cmp.Source
local DictionarySource = {}
--- @type blink-cmp-dictionary.Options
local dictionary_source_config
--- @type blink.cmp.SourceProviderConfig
local source_provider_config
local function create_job_from_documentation_command(documentation_command)
    ---@diagnostic disable-next-line: missing-fields
    return Job:new({
        command = utils.get_option(documentation_command.get_command),
        args = utils.get_option(documentation_command.get_command_args),
    })
end

--- @param opts blink-cmp-dictionary.Options
function DictionarySource.new(opts, config)
    log.setup({ title = 'blink-cmp-dictionary' })
    local self = setmetatable({}, { __index = DictionarySource })
    dictionary_source_config = vim.tbl_deep_extend("force", default, opts or {})
    source_provider_config = config
    local completion_item_kind = require('blink.cmp.types').CompletionItemKind
    local blink_kind_icons = require('blink.cmp.config').appearance.kind_icons
    for kind_name, icon in pairs(dictionary_source_config.kind_icons) do
        completion_item_kind[#completion_item_kind + 1] = kind_name
        completion_item_kind[kind_name] = #completion_item_kind
        blink_kind_icons[kind_name] = icon
        vim.api.nvim_set_hl(0, 'BlinkCmpKind' .. kind_name, { link = 'BlinkCmpKind', default = true })
    end
    return self
end

function DictionarySource:get_completions(context, callback)
    local items = {}
    local cancel_fun = function() end
    local transformed_callback = function()
        vim.schedule(function()
            callback({
                is_incomplete_forward = false,
                is_incomplete_backward = false,
                items = vim.tbl_values(items)
            })
        end)
    end
    -- NOTE:
    -- In blink.cmp, the min_keyword_length dose not mean when to get the completions
    -- it means when to show the completions, so we check here to avoid too many
    -- completions items passed to the callback
    local prefix = utils.get_option(dictionary_source_config.get_prefix, context)
    if #prefix == 0 or source_provider_config.min_keyword_length and
        #prefix < source_provider_config.min_keyword_length then
        callback()
        return cancel_fun
    end
    local async = utils.get_option(dictionary_source_config.async)
    local cmd = utils.get_option(dictionary_source_config.get_command)
    local cmd_args = utils.get_option(dictionary_source_config.get_command_args, prefix)
    local cat_writer = nil
    local get_all_dictionary_files = function()
        local res = {}
        local dirs = utils.get_option(dictionary_source_config.dictionary_directories)
        local files = utils.get_option(dictionary_source_config.dictionary_files)
        if utils.truthy(dirs) then
            for _, dir in ipairs(dirs) do
                for _, file in ipairs(vim.fn.globpath(dir, '**/*.txt', true, true)) do
                    table.insert(res, file)
                end
            end
        end
        if utils.truthy(files) then
            for _, file in ipairs(files) do
                table.insert(res, file)
            end
        end
        return res
    end
    local files = get_all_dictionary_files()
    if utils.truthy(files) then
        ---@diagnostic disable-next-line: missing-fields
        cat_writer = Job:new({
            command = 'cat',
            args = files,
        })
    end
    ---@diagnostic disable-next-line: missing-fields
    local job = Job:new({
        command = cmd,
        args = cmd_args,
        on_exit = function(j, code, signal)
            if signal == 9 then
                -- shutdown mannually
                -- do not handle the result
                return
            end
            if code ~= 0 or utils.truthy(j:stderr_result()) then
                if dictionary_source_config.on_error(code, table.concat(j:stderr_result(), '\n')) then
                    return
                end
            end
            local output = table.concat(j:result(), '\n')
            if utils.truthy(output) then
                local match_list = utils.get_option(dictionary_source_config.separate_output, output)
                vim.iter(match_list):each(function(match)
                    match.kind_name = dictionary_source_config.get_kind_name(match)
                    items[match] = {
                        label = match.label,
                        insertText = match.insert_text,
                        kind = require('blink.cmp.types').CompletionItemKind[match.kind_name] or 0,
                        documentation = match.documentation,
                    }
                end)
            end
        end,
        writer = cat_writer,
    })
    job:after(transformed_callback)
    if async then
        cancel_fun = function() job:shutdown(0, 9) end
    end
    if async then
        job:start()
    else
        job:sync()
    end
    return cancel_fun
end

function DictionarySource:resolve(item, callback)
    local transformed_callback = function()
        vim.schedule(function()
            callback(item)
        end)
    end
    if type(item.documentation) == 'string' or type(item.documentation) == 'nil' then
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

return DictionarySource
