---@class nvim-todo.ui.highlights.groups
local M = {}

---Define default highlight groups for the plugin
function M.setup()
  vim.api.nvim_set_hl(0, 'NvimTodoUnsaved', { default = true, fg = '#E5C07B' })
  vim.api.nvim_set_hl(0, 'NvimTodoActiveArrow', { default = true, fg = '#5C6370' })
  vim.api.nvim_set_hl(0, 'NvimTodoCount', { default = true, fg = '#5C6370' })
end

return M
