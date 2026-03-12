---@class nvim-todo.ui.highlights.color
local M = {}

---@type table<string, string>
local hl_cache = {}

---Get or create a highlight group for a hex color
---@param hex string e.g. "#E06C75"
---@return string hl_group
function M.get_color_hl(hex)
  if hl_cache[hex] then return hl_cache[hex] end
  local safe = hex:gsub('#', '')
  local name = 'NvimTodo_' .. safe
  vim.api.nvim_set_hl(0, name, { fg = hex })
  hl_cache[hex] = name
  return name
end

---Clear the highlight cache (called on cleanup)
function M.clear_cache()
  hl_cache = {}
end

return M
