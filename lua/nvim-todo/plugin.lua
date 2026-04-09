---Command and keymap registration for nvim-todo.
---@class nvim-todo.plugin
local M = {}

---Register user commands and keymaps.
---@param api { show: fun(), save: fun(), close: fun(), discard: fun(), reload: fun(), status: fun() }
function M.register(api)
  vim.api.nvim_create_user_command('TodoShow', api.show, {})
  vim.api.nvim_create_user_command('TodoSave', api.save, {})
  vim.api.nvim_create_user_command('TodoClose', api.close, {})
  vim.api.nvim_create_user_command('TodoDiscard', api.discard, {})
  vim.api.nvim_create_user_command('TodoReload', api.reload, {})
  vim.api.nvim_create_user_command('TodoStatus', api.status, {})

  vim.keymap.set('n', '<leader>otd', api.show, { desc = 'Open Todo notepad' })
end

return M
