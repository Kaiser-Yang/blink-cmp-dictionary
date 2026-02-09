--- @module 'blink.cmp'

local default = require('blink-cmp-dictionary.default')
local utils = require('blink-cmp-dictionary.utils')
local log = require('blink-cmp-dictionary.log')
log.setup({ title = 'blink-cmp-dictionary' })
local fallback = require('blink-cmp-dictionary.fallback')

-- No longer need plenary.job - using native vim.system instead

-- Cache for individual dictionary file contents
-- Key: file path, Value: { content = string } or { loading = true, pending_callbacks = {callbacks} }
local file_cache = {}
local uv = vim.uv or vim.loop

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

--- @param feature blink-cmp-dictionary.Options
--- @param result string[]
--- @param prefix string
--- @param max_items number
--- @return blink-cmp-dictionary.DictionaryCompletionItem[]
local function assemble_completion_items_from_output(feature, result, prefix, max_items)
    -- First, call separate_output to parse the output
    local separated_items = feature.separate_output(table.concat(result, '\n'))
    -- Then, apply fuzzy scoring and limit to max_items
    local top_items = utils.get_top_matches(separated_items, prefix, max_items)
    -- Finally, assemble completion items
    local items = {}
    for i, v in ipairs(top_items) do
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

--- Read a single file asynchronously using libuv with caching
--- @param filepath string
--- @param callback function(string|nil, string|nil) Called with (content, error)
local function read_file_async(filepath, callback)
    -- Check if already cached
    if file_cache[filepath] and file_cache[filepath].content then
        callback(file_cache[filepath].content, nil)
        return
    end
    
    -- Check if already loading
    if file_cache[filepath] and file_cache[filepath].loading then
        -- Add callback to pending list
        table.insert(file_cache[filepath].pending_callbacks, callback)
        return
    end
    
    -- Mark as loading and add the initial callback to pending list
    file_cache[filepath] = { loading = true, pending_callbacks = { callback } }
    
    -- Helper to handle errors for this specific filepath
    local function handle_error(error_msg)
        local pending = file_cache[filepath] and file_cache[filepath].pending_callbacks or {}
        file_cache[filepath] = nil
        vim.schedule(function()
            for _, cb in ipairs(pending) do
                cb(nil, error_msg)
            end
        end)
    end
    
    uv.fs_open(filepath, 'r', 438, function(err_open, fd)
        if err_open or not fd then
            handle_error(err_open or 'Failed to open file')
            return
        end
        
        uv.fs_fstat(fd, function(err_stat, stat)
            if err_stat or not stat then
                uv.fs_close(fd, function() end)
                handle_error(err_stat or 'Failed to stat file')
                return
            end
            
            uv.fs_read(fd, stat.size, 0, function(err_read, data)
                uv.fs_close(fd, function() end)
                
                if err_read then
                    handle_error(err_read)
                else
                    local pending = file_cache[filepath] and file_cache[filepath].pending_callbacks or {}
                    file_cache[filepath] = { content = data }
                    vim.schedule(function()
                        for _, cb in ipairs(pending) do
                            cb(data, nil)
                        end
                    end)
                end
            end)
        end)
    end)
end

--- Read dictionary files asynchronously and concatenate the content
--- @param files string[]
--- @param callback function(string|nil) Called with content or nil on error
local function read_dictionary_files_async(files, callback)
    if not files or #files == 0 then
        callback(nil)
        return
    end
    
    -- Read all files asynchronously (each file uses per-file caching)
    local content_parts = {}
    local remaining = #files
    
    for i, filepath in ipairs(files) do
        read_file_async(filepath, function(content, err)
            -- Treat errors as empty content and continue
            content_parts[i] = (not err and content) or ''
            
            remaining = remaining - 1
            
            if remaining == 0 then
                -- All files processed (some may have failed)
                local full_content = table.concat(content_parts, '\n')
                -- Only return nil if content is empty or whitespace only
                if full_content == '' or full_content:match('^%s*$') then
                    callback(nil)
                else
                    callback(full_content)
                end
            end
        end)
    end
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
    
    -- Handle fallback mode when cmd is empty string
    if not utils.truthy(cmd) then
        local files = get_all_dictionary_files()
        
        -- Load/refresh dictionaries (uses file-based caching internally)
        fallback.load_dictionaries(files)
        
        -- Perform synchronous search using fallback
        -- Check type: if it's a function or nil, use default of 100
        -- We cannot call function types as we don't have the proper context
        local max_items = 100
        if type(source_provider_config.max_items) == 'number' then
            max_items = source_provider_config.max_items
        end
        local results = fallback.search(prefix, max_items)
        if utils.truthy(results) then
            local match_list = assemble_completion_items_from_output(
                dictionary_source_config,
                results,
                prefix,
                max_items)
            vim.iter(match_list):each(function(match)
                process_completion_item(match, context, items)
            end)
        end
        transformed_callback()
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
                    local lines = {}
                    for line in output:gmatch("[^\r\n]+") do
                        table.insert(lines, line)
                    end
                    
                    -- Check type: if it's a function or nil, use default of 100
                    -- We cannot call function types as we don't have the proper context
                    local max_items = 100
                    if type(source_provider_config.max_items) == 'number' then
                        max_items = source_provider_config.max_items
                    end
                    local match_list = assemble_completion_items_from_output(
                        dictionary_source_config,
                        lines,
                        prefix,
                        max_items)
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
        
        read_dictionary_files_async(files, function(content)
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
