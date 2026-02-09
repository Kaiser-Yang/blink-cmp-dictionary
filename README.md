# 📚 blink-cmp-dictionary

<div align="center">

### 🎉 Version 3.0 - Zero Dependencies Required! 🎉

**English** | [中文文档](./README-zh.md)

[![Latest Release](https://img.shields.io/github/v/release/Kaiser-Yang/blink-cmp-dictionary)](https://github.com/Kaiser-Yang/blink-cmp-dictionary/releases)

</div>

---

> 🚀 **New in v3.0:** Enjoy **blazingly fast** dictionary completion with **ZERO external dependencies**! Just provide a dictionary file and you're ready to go! ⚡

Dictionary source for [blink.cmp](https://github.com/Saghen/blink.cmp)
completion plugin. This makes it possible to query a dictionary
without leaving the editor.

## ✨ Features

Fuzzy finding is supported by default:

![blink-cmp-dictionary fuzzy finding a word](./images/demo-fuzzy.png)

📖 Definitions of words are also supported (use `wn` by default):

![blink-cmp-dictionary documents a word](./images/demo-doc.png)

> [!NOTE]
> `wn` is the abbreviation of `WordNet`, which is a lexical database of the English language.
> If you don't know how to install `wn`, you may google the keyword
> `how to install WordNet on ...`.

## 🎯 Requirements

> 💎 **v3.0 Highlight:** The plugin now works **out of the box** with ZERO external dependencies! Just provide a dictionary file and enjoy lightning-fast fuzzy completion! ⚡

**Optional external tools** (for enhanced performance):
- `fzf`, `rg`, or `grep` - for even faster searching (optional)
- `wn` (WordNet) - for word definitions (optional)

You can use `checkhealth blink-cmp-dictionary` to check if the optional tools are available.

### 🚀 Fallback Mode (Pure Lua - No Dependencies!)

**Default Behavior:**
By default, if `fzf` is **not found**, the plugin will **directly fall back** to a pure Lua implementation instead of trying `rg` or `grep`. This provides the best user experience with excellent performance.

**🎁 Why Fallback Mode is Amazing:**
* ✅ **Zero external dependencies** - Works everywhere!
* ✅ **Blazing fast** - Almost no perceptible delay even with 90,000+ word dictionaries
* ✅ **Full fuzzy matching** - Similar to `fzf`, with intelligent scoring
* ✅ **Cross-platform** - Works on any system with Neovim

**Disabling Fallback:**
If you prefer to use `rg` or `grep` when `fzf` is not available, set `force_fallback = false` in your configuration:

```lua
opts = {
    force_fallback = false,  -- Try rg/grep instead of fallback when fzf is not found
}
```

> [!NOTE]
> 🎯 **Performance:** Testing with a 90,000 line dictionary file shows virtually no perceptible latency. The fallback mode is now a viable option even for large dictionaries!
> 
> 💬 If you encounter any performance issues with fallback mode, please [open an issue](https://github.com/Kaiser-Yang/blink-cmp-dictionary/issues). We will work on implementing an asynchronous execution mode to resolve them.

## 📦 Installation

Add the plugin to your package manager, and make sure it is loaded before `blink.cmp`.

> [!TIP]
> 💡 **Recommended:** Use the default `force_fallback` configuration. The plugin will automatically use the pure Lua fallback only when `fzf` is not available, giving you the best performance in all scenarios!

### 🔌 lazy.nvim

**Recommended Setup (Zero Dependencies!):**

```lua
{
    'saghen/blink.cmp',
    dependencies = {
        'Kaiser-Yang/blink-cmp-dictionary',
        -- ... Other dependencies
    },
    opts = {
        sources = {
            -- Add 'dictionary' to the list
            default = { 'dictionary', 'lsp', 'path', 'luasnip', 'buffer' },
            providers = {
                dictionary = {
                    module = 'blink-cmp-dictionary',
                    name = 'Dict',
                    min_keyword_length = 0,
                    opts = {
                        -- Optional: explicitly force fallback mode
                        -- (By default, fallback is used when fzf is not found)
                        force_fallback = true,
                    }
                }
            },
        }
    }
}
```

**With External Commands (Enhanced Performance):**

```lua
{
    'saghen/blink.cmp',
    dependencies = {
        'Kaiser-Yang/blink-cmp-dictionary',
        -- ... Other dependencies
    },
    opts = {
        sources = {
            -- Add 'dictionary' to the list
            default = { 'dictionary', 'lsp', 'path', 'luasnip', 'buffer' },
            providers = {
                dictionary = {
                    module = 'blink-cmp-dictionary',
                    name = 'Dict',
                    -- 💡 Performance impact of min_keyword_length:
                    -- - In fallback mode: No impact on performance regardless of value
                    -- - With fzf: Higher values may improve performance
                    -- - With other commands (rg/grep): Higher values significantly improve performance
                    min_keyword_length = 0,
                    -- options for blink-cmp-dictionary
                    opts = {
                        -- put your dictionary files here
                        -- dictionary_files = {}
                    }
                }
            },
        }
    }
}
```

## 🚀 Quick Start

> [!NOTE]
> 📖 If you don't have a dictionary file, see [english-words](https://github.com/dwyl/english-words).

By default, your dictionary files must be like this content (every line is a word):

```txt
word1
word2
```

If your dictionary files are like these, you just need to specify the dictionary files'
path in the configuration:

```lua
-- Specify the dictionary files' path
-- example: { vim.fn.expand('~/.config/nvim/dictionary/words.dict') }
dictionary_files = nil,
-- All .txt files in these directories will be treated as dictionary files
-- example: { vim.fn.expand('~/.config/nvim/dictionary') }
dictionary_directories = nil,
```

> [!NOTE]
>
> ⚠️ All the dictionary files in `dictionary_files` and `dictionary_directories` will be
> concatenated together. Make sure the files are different, otherwise there will be
> duplicate words in the completion list. If your dictionary files are not separated by lines,
> see [How to customize completion items](#how-to-customize-completion-items)

## ⚙️ Default Configuration

See [default.lua](./lua/blink-cmp-dictionary/default.lua).

## 💡 Q&A

### 🔤 What is the actual behavior of capitalization?

As for `v2.0.0`, there are four new options:

* `capitalize_first`:
  - `true`: Capitalize the first letter of the completion item.
  - `false`: Do not capitalize the first letter of the completion item.
* `capitalize_whole_word`:
  - `true`: Capitalize the whole word.
  - `false`: Do not capitalize the whole word.
* `decapitalize_first`:
  - `true`: Decapitalize the first letter of the completion item.
  - `false`: Do not de-capitalize the first letter of the completion item.
* `decapitalize_whole_word`:
  - `true`: Decapitalize the whole word.
  - `false`: Do not de-capitalize the whole word.

The behavior of capitalization is determined by all the options. For example, if the values of them
are `true`, `true`, `true`, `true`. The process will be: (use `word` as an example)

* Capitalize the first letter of the completion item: `Word`
* Capitalize the whole word: `WORD`
* Decapitalize the first letter of the completion item: `wORD`
* Decapitalize the whole word: `word`

So the result will be `word`.

By default, `capitalize_first` will be `true`, if the word of dictionary files is lowercase, and the
first letter of match prefix is uppercase; `capitalize_whole_word` will be `true`, if the word of
dictionary files is lowercase, and the first two letters of match prefix are uppercase;
`decapitalize_first` and `decapitalize_whole_word` are always `false`. This means if there is
`word` in your dictionary files, and you input `W`, the completion item will be `Word`. If you
input `WO`, the completion item will be `WORD`. If you input `wo`, `wO`, `woR`, or `wOr`, the
completion item will be `word`.

### 📁 How to use different dictionaries for different filetypes?

You just need use a function to determine the dictionary files for different file types,
for example:

```lua
dictionary_files = function()
    if vim.bo.filetype == 'markdown' then
        return { vim.fn.expand('~/.config/nvim/dictionary/markdown.dict') }
    end
    return { vim.fn.expand('~/.config/nvim/dictionary/words.dict') }
end,
```

### 🔍 Why use `fzf` as default? `blink.cmp` already supports fuzzy finding

In `blink-cmp-dictionary` we use `get_prefix` to determine which part to search. If we do not use
`fzf`, for example we use `rg` or `grep`, and we set `min_keyword_length=3`. After inputting 'dic',
`blink.cmp` will get all the words that start with 'dic', then `blink.cmp` will fuzzy find on
words starting with 'dic'. The process makes it impossible to complete 'dictionary'
when inputting 'dit'. But if we use `fzf`, `fzf` will return 'dictionary' when inputting `dit`
('dit' is a sub-sequence of 'dictionary'). So the fuzzy finding feature are fully supported.

Note that `grep` is provided as a last resort fallback when neither `fzf` nor `rg` are available,
but it will not provide the same level of fuzzy matching as `fzf`.

### 🎨 How to customize completion items

By default, `blink-cmp-dictionary` treat every line in the dictionary files as a completion item.
You can update this by use `separate_output` in the configuration:

```lua
separate_output = function(output)
    local items = {}
    -- You may need to change the pattern to match your dictionary files
    for line in output:gmatch("[^\r\n]+") do
        local items = {}
        for line in output:gmatch("[^\r\n]+") do
            table.insert(items, line)
        end
        return items
    end
    return items
end
```

After calling `separate_output`, `blink-cmp-dictionary` will call `get_label`, `get_insert_text`,
`get_documentation`, and `get_kind` for each item in the list to assemble the completion items.
Those below are the default:

```lua
get_label = function(item)
    return item
end,
get_insert_text = function(item)
    return item
end,
get_kind_name = function(_)
    return 'Dict'
end,
get_documentation = function(item)
    -- use return nil to disable the documentation
    -- return nil
    return {
        get_command = function()
            return utils.command_found('wn') and 'wn' or ''
        end,
        get_command_args = function()
            return { item, '-over' }
        end,
        resolve_documentation = function(output)
            return output
        end,
        on_error = default_on_error,
    }
end,
```

### 🛠️ How to customize the command

By default, `blink-cmp-dictionary` will read dictionary files using native Neovim async file I/O and pipe them to a search tool. 

**Default Behavior:**
- If `fzf` is found → Use `fzf` for fuzzy searching
- If `fzf` is **not** found → **Directly fall back to pure Lua implementation**
- This provides excellent performance without requiring external tools

**Disable Fallback (use rg/grep when fzf not found):**
If you prefer to try `rg` or `grep` when `fzf` is not available:

```lua
opts = {
    force_fallback = false,  -- Try rg/grep instead of direct fallback
    -- Other options for blink-cmp-dictionary
}
```

**Force Fallback Mode:**
You can force fallback mode even when `fzf` is available:

```lua
opts = {
    force_fallback = true,   -- Always use pure Lua implementation
    -- Other options for blink-cmp-dictionary
}
```

**Fallback Mode Performance:**
- Performs **fuzzy matching** (similar to `fzf`) synchronously with intelligent scoring
- Has **excellent performance** even with large dictionaries (tested with 90,000 line files showing virtually no perceptible latency)
- If you encounter performance issues, please [open an issue](https://github.com/Kaiser-Yang/blink-cmp-dictionary/issues) - we can implement async execution

**Custom Command:**
You may configure a new command which supports reading from files directly, for example, `rg`:

```lua
-- set them with nil to pass files directly to the command
dictionary_files = nil,
dictionary_directories = nil,
get_command = 'rg',
get_command_args = function(prefix, _)
    local dictionary_file1 = 'path/to/your/dictionary/file1'
    local dictionary_file2 = 'path/to/your/dictionary/file2'
    return {
        '--color=never',
        '--no-line-number',
        '--no-messages',
        '--no-filename',
        '--smart-case',
        '--',
        prefix,
        -- pass the dictionary files to the command
        dictionary_file1,
        dictionary_file2,
    }
end
```

If you just want to customize the arguments for `fzf` , for example,
those below will ignore the case:

```lua
get_command_args = function(prefix, _)
    return {
        '--filter=' .. prefix,
        '--sync',
        '--no-sort',
        '-i' -- -i to ignore case, +i to respect case, with no this line is smart case
    }
end,
```

### 🎨 How to customize the highlight

Customize the `BlinkCmpKindDict` to customize the highlight for kind icon, here is an example:

```lua
vim.api.nvim_set_hl(0, 'BlinkCmpKindDict', { default = false, fg = '#a6e3a1' })
```

### 🎯 How to enable this plugin for comment blocks or specific file types only?

Update the `default` of `blink.cmp`:

```lua
-- Use this function to check if the cursor is inside a comment block
local function inside_comment_block()
    if vim.api.nvim_get_mode().mode ~= 'i' then
        return false
    end
    local node_under_cursor = vim.treesitter.get_node()
    local parser = vim.treesitter.get_parser(nil, nil, { error = false })
    local query = vim.treesitter.query.get(vim.bo.filetype, 'highlights')
    if not parser or not node_under_cursor or not query then
        return false
    end
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    row = row - 1
    for id, node, _ in query:iter_captures(node_under_cursor, 0, row, row + 1) do
        if query.captures[id]:find('comment') then
            local start_row, start_col, end_row, end_col = node:range()
            if start_row <= row and row <= end_row then
                if start_row == row and end_row == row then
                    if start_col <= col and col <= end_col then
                        return true
                    end
                elseif start_row == row then
                    if start_col <= col then
                        return true
                    end
                elseif end_row == row then
                    if col <= end_col then
                        return true
                    end
                else
                    return true
                end
            end
        end
    end
    return false
end

-- this is the opts for blink.cmp
---@module 'blink.cmp'
---@type blink.cmp.Config
opts = {
    sources = {
        default = function()
            -- put those which will be shown always
            local result = {'lsp', 'path', 'luasnip', 'buffer' }
            if
                -- turn on dictionary in markdown or text file
                vim.tbl_contains({ 'markdown', 'text' }, vim.bo.filetype) or
                -- or turn on dictionary if cursor is in the comment block
                inside_comment_block()
            then
                table.insert(result, 'dictionary')
            end
            return result
        end,
    }
}
```

## ⚡ Performance

**Default Mode:**
- If `fzf` is found: Uses `fzf` (asynchronous, no blocking)
- If `fzf` is **not** found: Uses **fallback mode** (synchronous, but excellent performance) ✨

**With External Commands:**
When using external commands (`fzf`, `rg`, or `grep`), `blink-cmp-dictionary` runs asynchronously and will not block other operations.

**With Fallback Mode (Default when fzf not found):**
When using fallback mode (no external commands), the plugin performs **synchronous** filtering with **excellent performance**. Testing with a 90,000 line dictionary file shows virtually no perceptible latency. Performance issues are now almost non-existent, making fallback mode a viable option even for large dictionaries! 🚀

> [!TIP]
> 💬 If you encounter any performance issues with fallback mode, please [open an issue](https://github.com/Kaiser-Yang/blink-cmp-dictionary/issues). We will implement an asynchronous execution mode to resolve them.

**Performance Tuning:**

- **`min_keyword_length`**: 
  - In **fallback mode**: No impact on performance regardless of value ✅
  - With **fzf**: Higher values may improve performance
  - With **other commands** (rg/grep): Higher values significantly improve performance

- **`max_items`**: Smaller values result in better performance across all modes. This is because blink.cmp's fuzzy matching (which happens after dictionary results are returned) processes the items - more items require more processing time downstream.

**Example Configuration:**

```lua
opts = {
    sources = {
        providers = {
            dictionary = {
                module = 'blink-cmp-dictionary',
                name = 'Dict',
                min_keyword_length = 0,  -- Adjust based on your search command
                -- Smaller values improve performance universally
                max_items = 8, -- blink-cmp-dictionary will inherit this, the default is 100
            }
        },
    }
}
```

## 📌 Version Introduction

The release versions are something like `major.minor.patch`. When one of these numbers is increased:

* `patch`: 🐛 bugs are fixed or docs are added. This will not break the compatibility.
* `minor`: ✨ compatible features are added. This may cause some configurations `deprecated`, but
not break the compatibility.
* `major`: 🚀 incompatible features are added. All the `deprecated` configurations will be removed.
This will break the compatibility.

## 🙏 Acknowledgment

Nice and fast completion plugin: [blink.cmp](https://github.com/Saghen/blink.cmp).

Inspired by [cmp-dictionary](https://github.com/uga-rosa/cmp-dictionary).

Learned how to write a source from [blink-ripgrep.nvim](https://github.com/mikavilpas/blink-ripgrep.nvim).

---

<div align="center">

**⭐ Star this repo if you find it useful! ⭐**

Made with ❤️ by the community

</div>
