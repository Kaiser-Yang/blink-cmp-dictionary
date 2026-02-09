--- @module 'blink.cmp'

local default = require('blink-cmp-dictionary.default')
local utils = require('blink-cmp-dictionary.utils')
local log = require('blink-cmp-dictionary.log')
log.setup({ title = 'blink-cmp-dictionary' })
local fallback = require('blink-cmp-dictionary.fallback')

-- No longer need plenary.job - using native vim.system instead

-- Cache for individual dictionary file contents
-- Note: Cache is now managed in utils.lua


--- @type blink.cmp.Source
--- @diagnostic disable-next-line: missing-fields
local DictionarySource = {}
--- @type blink-cmp-dictionary.Options
local dictionary_source_config
--- @type blink.cmp.SourceProviderConfig
local source_provider_config
--- @param opts blink-cmp-dictionary.Options
function DictionarySource.new(opts, config)
    local self = setmetatable({}, { __index = DictionarySource })
    dictionary_source_config = vim.tbl_deep_extend("force", default, opts or {})
    source_provider_config = config

    local completion_item_kind = require('blink.cmp.types').CompletionItemKind
    local blink_kind_icons = require('blink.cmp.config').appearance.kind_icons
    for kind_name, icon in pairs(dictionary_source_config.kind_icons) do
        if completion_item_kind[kind_name] then
            goto continue
        end
        completion_item_kind[#completion_item_kind + 1] = kind_name
        completion_item_kind[kind_name] = #completion_item_kind
        blink_kind_icons[kind_name] = icon
        vim.api.nvim_set_hl(0, 'BlinkCmpKind' .. kind_name, { default = true, fg = '#a6e3a1' })
        ::continue::
    end
    return self
end

--- Assemble completion items from raw command output
--- Assemble completion items from already-separated words (fallback mode)
--- @param feature blink-cmp-dictionary.Options
--- @param words string[] # Already separated words from fallback search
--- @return blink-cmp-dictionary.DictionaryCompletionItem[]
local function assemble_completion_items_from_words(feature, words)
    -- Words are already scored and limited by fallback.search
    -- Just assemble completion items
    local items = {}
    for i, v in ipairs(words) do
        items[i] = {
            label = feature.get_label(v),
            kind_name = feature.get_kind_name(v),
            insert_text = feature.get_insert_text(v),
            documentation = feature.get_documentation(v),
        }
    end
    -- feature.configure_score_offset(items)
    return items
end

--- @param feature blink-cmp-dictionary.Options
--- @param result string # Raw output from external command
--- @param prefix string
--- @param max_items number
--- @param cmd string|nil # Command name (e.g., 'fzf') for optimization
--- @return blink-cmp-dictionary.DictionaryCompletionItem[]
local function assemble_completion_items_from_output(feature, result, prefix, max_items, cmd)
    -- First, call separate_output to parse the output
    local separated_items = feature.separate_output(result)
    
    -- Optimization: if we have fewer items than max_items, or fzf output is already sorted,
    -- we don't need to do fuzzy scoring/selection
    local top_items
    if #separated_items <= max_items then
        -- Not enough items to select, use all
        top_items = separated_items
    elseif cmd == 'fzf' then
        -- fzf output is already sorted, just take first max_items
        top_items = {}
        for i = 1, max_items do
            table.insert(top_items, separated_items[i])
        end
    else
        -- Apply fuzzy scoring and limit to max_items
        top_items = utils.get_top_matches(separated_items, prefix, max_items)
    end
    
    -- Finally, assemble completion items using the shared function
    return assemble_completion_items_from_words(feature, top_items)
end

--- Helper function to get all dictionary files
--- @return string[]
local function get_all_dictionary_files()
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

--- Helper function to process completion items with capitalization
--- @param match blink-cmp-dictionary.DictionaryCompletionItem
--- @param context blink.cmp.Context
--- @param items table
local function process_completion_item(match, context, items)
    items[match] = {
        label = match.label,
        insertText = match.insert_text,
        kind = require('blink.cmp.types').CompletionItemKind[match.kind_name] or 0,
        documentation = match.documentation,
    }
    if utils.get_option(
        dictionary_source_config.capitalize_first,
        context,
        match
    ) then
        items[match].label = utils.capitalize(match.label, false)
        items[match].insertText = utils.capitalize(match.insert_text, false)
    end
    if utils.get_option(
        dictionary_source_config.capitalize_whole_word,
        context,
        match
    ) then
        items[match].label = utils.capitalize(match.label, true)
        items[match].insertText = utils.capitalize(match.insert_text, true)
    end
    if utils.get_option(
        dictionary_source_config.decapitalize_first,
        context,
        match
    ) then
        items[match].label = utils.decapitalize(match.label, false)
        items[match].insertText = utils.decapitalize(match.insert_text, false)
    end
    if utils.get_option(
        dictionary_source_config.decapitalize_whole_word,
        context,
        match
    ) then
        items[match].label = utils.decapitalize(match.label, true)
        items[match].insertText = utils.decapitalize(match.insert_text, true)
    end
end

function DictionarySource:get_completions(context, callback)
    local items = {}
    local cancel_fun = function() end
    -- In order to make the capitalization work as expected, we must make the source
    -- in completion all the time so that when users delete some letters from the prefix,
    -- the source will be called again to get the completions.
    local transformed_callback = function()
        callback({
            is_incomplete_forward = true,
            is_incomplete_backward = true,
            items = vim.tbl_values(items)
        })
    end
    -- NOTE:
    -- `min_keyword_length` in blink.cmp is taken into account when completions
    -- are displayed, not when they are fetched. The check here prevents excessive
    -- completion items from being passed to the callback, as dictionary results
    -- can be extensive.
    local prefix = utils.get_option(dictionary_source_config.get_prefix, context)
    local min_keyword_length = utils.get_option(source_provider_config.min_keyword_length, context) or 0
    if #prefix == 0 or #prefix < min_keyword_length then
        callback()
        return cancel_fun
    end
    local cmd = utils.get_option(dictionary_source_config.get_command)
    
    -- Parse max_items once for both fallback and external command modes
    -- Check type: if it's a function or nil, use default of 100
    -- We cannot call function types as we don't have the proper context
    local max_items = 100
    if type(source_provider_config.max_items) == 'number' then
        max_items = source_provider_config.max_items
    end
    
    -- Handle fallback mode: either forced or when cmd is not available
    local force_fallback = dictionary_source_config.force_fallback or false
    if force_fallback or not utils.truthy(cmd) then
        local files = get_all_dictionary_files()
        
        -- Load/refresh dictionaries asynchronously
        -- Pass separate_output function to parse dictionary files
        fallback.load_dictionaries(files, dictionary_source_config.separate_output, function(success)
            if not success then
                transformed_callback()
                return
            end
            
            -- Perform search using fallback
            local results = fallback.search(prefix, max_items)
            if utils.truthy(results) then
                -- fallback.search already returns scored and limited words
                -- No need to call separate_output again
                local match_list = assemble_completion_items_from_words(
                    dictionary_source_config,
                    results)
                vim.iter(match_list):each(function(match)
                    process_completion_item(match, context, items)
                end)
            end
            transformed_callback()
        end)
        return cancel_fun
    end
    local cmd_args = utils.get_option(dictionary_source_config.get_command_args, prefix, cmd)
    
    local cancel_fun_ref = { fn = nil }
    local files = get_all_dictionary_files()
    
    -- Function to run the search command
    local function run_search_command(input_data)
        local obj = { cancelled = false }
        
        -- Build command with args
        local full_cmd = { cmd }
        for _, arg in ipairs(cmd_args) do
            table.insert(full_cmd, arg)
        end
        
        vim.system(full_cmd, {
            text = true,
            stdin = input_data,
        }, function(result)
            if obj.cancelled then
                return
            end
            
            vim.schedule(function()
                if obj.cancelled then
                    return
                end
                
                if result.code ~= 0 and result.stderr and result.stderr ~= '' then
                    if dictionary_source_config.on_error(result.code, result.stderr) then
                        return
                    end
                end
                
                local output = result.stdout or ''
                if utils.truthy(output) then
                    local match_list = assemble_completion_items_from_output(
                        dictionary_source_config,
                        output,
                        prefix,
                        max_items,
                        cmd)  -- Pass cmd for fzf optimization
                    vim.iter(match_list):each(function(match)
                        process_completion_item(match, context, items)
                    end)
                end
                
                transformed_callback()
            end)
        end)
        
        cancel_fun_ref.fn = function()
            obj.cancelled = true
        end
        
        return obj
    end
    
    -- If we have files, read them asynchronously
    if utils.truthy(files) then
        local read_obj = { cancelled = false }
        
        -- Set cancel_fun immediately to handle race conditions
        cancel_fun = function()
            read_obj.cancelled = true
            if cancel_fun_ref.fn then
                cancel_fun_ref.fn()
            end
        end
        
        utils.read_dictionary_files_async(files, function(content)
            if read_obj.cancelled then
                return
            end
            
            if not content or content == '' then
                vim.schedule(function()
                    transformed_callback()
                end)
                return
            end
            
            -- Now run the search command with file content as stdin
            run_search_command(content)
        end)
    else
        -- No files, do not perform any operation
        transformed_callback()
    end
    
    return cancel_fun
end

function DictionarySource:resolve(item, callback)
    local transformed_callback = function()
        callback(item)
    end
    if type(item.documentation) == 'string' or not item.documentation then
        transformed_callback()
        return
    end
    ---@diagnostic disable-next-line: undefined-field
    if not utils.truthy(utils.get_option(item.documentation.get_command)) then
        item.documentation = nil
        transformed_callback()
        return
    end
    
    local cmd = utils.get_option(item.documentation.get_command)
    local args = utils.get_option(item.documentation.get_command_args)
    
    -- Build full command
    local full_cmd = { cmd }
    for _, arg in ipairs(args) do
        table.insert(full_cmd, arg)
    end
    
    vim.system(full_cmd, { text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 and result.stderr and result.stderr ~= '' then
                ---@diagnostic disable-next-line: undefined-field
                if item.documentation.on_error(result.code, result.stderr) then
                    return
                end
            end
            
            if result.stdout and result.stdout ~= '' then
                ---@diagnostic disable-next-line: undefined-field
                item.documentation = item.documentation.resolve_documentation(result.stdout)
            else
                item.documentation = nil
            end
            transformed_callback()
        end)
    end)
end

return DictionarySource
