---@class nvim-todo.utils.string
local M = {}

---Format a keymap value for display.
---Handles both single key strings and arrays of alternative keys.
---@param k string|string[] Single key or array of keys
---@return string formatted Display string (e.g. "q / <Esc>")
function M.fmt_key(k)
  if type(k) == 'table' then return table.concat(k, ' / ') end
  return k
end

return M
