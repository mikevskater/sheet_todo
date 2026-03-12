-- Close and cleanup for the multi-panel UI.
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local right_buffer = require('nvim-todo.ui.panels.right.buffer')
local active = require('nvim-todo.data.manager.active')
local cursor = require('nvim-todo.data.group.cursor')
local highlights = require('nvim-todo.ui.highlights')
local sticky_headers = require('nvim-todo.features.sticky_headers')
local hide_completed = require('nvim-todo.features.hide_completed')

---Persist content/cursor/expanded to data layer, clean up features, reset state.
function M.cleanup()
  -- Save current right-panel content to data layer
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    local full_content = right_buffer.get_full_content()
    active.set_active_content(full_content)
    cursor.set_active_cursor(right_buffer.get_cursor())
  end

  -- Save expanded state for persistence
  active.set_expanded_paths(state.tree_state.expanded)

  sticky_headers.cleanup()
  hide_completed.reset()
  highlights.clear_cache()

  state.reset()
end

---Close the multi-panel UI.
function M.close()
  if state.panel_state then
    state.panel_state:close()
  end
end

---Check if multi-panel is currently open.
---@return boolean
function M.is_open()
  return state.panel_state ~= nil
    and state.right_win ~= nil
    and vim.api.nvim_win_is_valid(state.right_win)
end

return M
