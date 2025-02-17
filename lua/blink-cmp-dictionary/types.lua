--- @class (exact) blink-cmp-dictionary.DocumentationCommand
--- @field get_command? string|fun(): string
--- @field get_command_args? string[]|fun(): string[]
--- @field resolve_documentation? fun(output: string): string

--- @class (exact) blink-cmp-dictionary.DictionaryCompletionItem
--- @field label string
--- @field insert_text string
--- @field documentation? string|blink-cmp-dictionary.DocumentationCommand

--- @class (exact) blink-cmp-dictionary.Options
--- @field async? boolean|fun(): boolean
--- @field get_prefix? string|fun(context: blink.cmp.Context): string
--- @field dictionary_files? string[]|fun(): string[]
--- @field dictionary_directories? string[]|fun(): string[]
--- @field get_command? string|fun(): string
--- @field get_command_args? fun(prefix: string, coomand: string): string[]
--- @field separate_output? fun(output: string): blink-cmp-dictionary.DictionaryCompletionItem[]
--- @field get_kind_name? fun(item: blink-cmp-dictionary.DictionaryCompletionItem): string
--- @field on_error? fun(return_value: number, standard_error: string): boolean
