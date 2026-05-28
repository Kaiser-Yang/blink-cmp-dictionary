--- Fallback search implementation that doesn't depend on external tools
--- This module provides a pure Lua implementation for fuzzy search
--- Uses async file reading and direct fuzzy matching without trie structures

local M = {}
local utils = require("blink-cmp-dictionary.utils")

--- Search for words matching the given prefix with fuzzy matching
--- @param files string[]
--- @param separate_output function # Function to separate file content into words
--- @param prefix string # The search prefix
--- @param max_results? number # Maximum number of results to return (default: 100)
--- @param callback function(number, string|nil, string[]) # Callback called with (return_code, standard_error, words)
function M.search(files, separate_output, prefix, max_results, callback)
	if not files or #files == 0 or not prefix or #prefix == 0 then
		if callback then
			callback(0, nil, {}) -- Success - no errors
		end
		return
	end
	max_results = max_results or 100
	utils.read_dictionary_files_async(files, function(return_code, standard_error, content)
		-- PERF:
		local words = separate_output(content)
		-- PERF:
		words = utils.get_top_matches(words, prefix, max_results)
		if callback then
			callback(return_code, standard_error, words)
		end
	end, false)
end

return M
