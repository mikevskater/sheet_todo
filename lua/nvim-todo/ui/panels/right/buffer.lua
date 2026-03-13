-- Right panel buffer I/O: get/set content and cursor, scrollbar sync.
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local hide_completed = require('nvim-todo.features.hide_completed')

---Sync the editor FloatWindow's .lines field and trigger scrollbar update.
---@param lines string[]?
function M.sync_scrollbar(lines)
  if not state.panel_state then return end
  local editor_float = state.panel_state:get_panel_float(state.PANEL_EDITOR)
  if not editor_float then return end

  if lines then
    editor_float.lines = lines
  elseif state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    editor_float.lines = vim.api.nvim_buf_get_lines(state.right_buf, 0, -1, false)
  end

  local ok, Scrollbar = pcall(require, 'nvim-float.float.scrollbar')
  if ok then
    Scrollbar.update(editor_float)
  end
end

---Get content from the right panel buffer.
---@return string
function M.get_content()
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(state.right_buf, 0, -1, false)
  return table.concat(lines, "\n")
end

---Get full content including hidden completed tasks.
---@return string
function M.get_full_content()
  if hide_completed.is_active() then
    return hide_completed.get_full_content(state.right_buf)
  end
  return M.get_content()
end

---Set content in the right panel buffer.
---@param content string
function M.set_content(content)
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end

  state.ignore_changes = true

  vim.api.nvim_buf_set_option(state.right_buf, 'modifiable', true)
  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(state.right_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.right_buf, 'modified', false)

  -- Sync FloatWindow lines for scrollbar
  M.sync_scrollbar(lines)

  state.saved_content = content
  state.has_unsaved_changes = false

  vim.schedule(function()
    state.ignore_changes = false
  end)
end

---Get cursor position from the right panel.
---@return { line: number, col: number }
function M.get_cursor()
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return { line = 1, col = 0 }
  end
  local pos = vim.api.nvim_win_get_cursor(state.right_win)
  return { line = pos[1], col = pos[2] }
end

---Set cursor position in the right panel.
---@param pos { line: number, col: number }
function M.set_cursor(pos)
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end
  local total = vim.api.nvim_buf_line_count(state.right_buf)
  local line = math.max(1, math.min(pos.line or 1, total))
  vim.api.nvim_win_set_cursor(state.right_win, { line, pos.col or 0 })
  -- Scroll so cursor line sits at the bottom of the window
  vim.api.nvim_win_call(state.right_win, function() vim.cmd('normal! zb') end)
end

return M
