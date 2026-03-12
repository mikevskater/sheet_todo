---@class nvim-todo.ui.highlights.groups
local M = {}

---Define default highlight groups for the plugin
function M.setup()
  vim.api.nvim_set_hl(0, 'NvimTodoActiveGroup', { default = true, bold = true })
  vim.api.nvim_set_hl(0, 'NvimTodoUnsaved', { default = true, fg = '#E5C07B' })
end

return M
