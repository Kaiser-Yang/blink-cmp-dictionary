--- @class (exact) blink-cmp-dictionary.DocumentationOptions
--- @field enable boolean|fun(item: blink.cmp.CompletionItem): boolean
--- @field get_command? string[]|fun(item: blink.cmp.CompletionItem): string[]

--- @class (exact) blink-cmp-dictionary.Options
--- @field get_prefix? string|fun(context: blink.cmp.Context): string
--- @field prefix_min_len? number|fun(context: blink.cmp.Context, prefix: string): number
--- @field get_command? string[]|fun(context: blink.cmp.Context, prefix: string): string[]
--- @field output_separator? string|fun(context: blink.cmp.Context, prefix: string): string
--- @field documentation? blink-cmp-dictionary.DocumentationOptions
