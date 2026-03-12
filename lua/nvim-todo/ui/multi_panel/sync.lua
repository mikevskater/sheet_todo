-- Group switching and public sync API for the multi-panel UI.
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local right_buffer = require('nvim-todo.ui.panels.right.buffer')
local tree_state = require('nvim-todo.ui.panels.left.tree_state')
local statuscolumn = require('nvim-todo.ui.multi_panel.statuscolumn')
local active = require('nvim-todo.data.manager.active')
local cursor = require('nvim-todo.data.group.cursor')
local path_utils = require('nvim-todo.data.group.path')
local hide_completed = require('nvim-todo.features.hide_completed')

---Switch to a different group.
---@param path string Group path to switch to
function M.switch_group(path)
  if not state.panel_state then return end
  if path == active.get_active_group() then return end

  -- Save current right-panel content and cursor
  local full_content = right_buffer.get_full_content()
  hide_completed.reset()
  active.set_active_content(full_content)
  cursor.set_active_cursor(right_buffer.get_cursor())

  -- Switch active group
  active.set_active_group(path)

  -- Load new group's content
  right_buffer.set_content(active.get_active_content())

  -- Restore cursor
  vim.schedule(function()
    right_buffer.set_cursor(cursor.get_active_cursor())
  end)

  -- Apply per-group line numbers, match global relativenumber
  if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
    local ln_on = active.get_active_line_numbers()
    vim.api.nvim_set_option_value('number', ln_on, { win = state.right_win })
    vim.api.nvim_set_option_value('relativenumber', ln_on and vim.o.relativenumber or false, { win = state.right_win })
  end

  statuscolumn.apply()

  -- Update right panel title (show leaf name)
  local parts = path_utils.split_path(path)
  local display_name = parts[#parts] or path
  state.panel_state:update_panel_title(state.PANEL_EDITOR, " " .. display_name .. " ")

  -- Re-render left panel
  state.panel_state:render_panel(state.PANEL_GROUPS)
end

-- ============================================================================
-- Public sync wrappers (delegated from multi_panel/init.lua)
-- ============================================================================

---Set content in the right panel (called after loading from Pantry).
---@param content string
function M.set_content(content)
  right_buffer.set_content(content)
end

---Get content from the right panel.
---@return string
function M.get_content()
  return right_buffer.get_full_content()
end

---Get cursor position from the right panel.
---@return { line: number, col: number }
function M.get_cursor()
  return right_buffer.get_cursor()
end

---Set cursor position in the right panel.
---@param pos { line: number, col: number }
function M.set_cursor(pos)
  right_buffer.set_cursor(pos)
end

---Mark content as saved.
function M.mark_as_saved()
  state.saved_content = right_buffer.get_content()
  state.has_unsaved_changes = false
  if state.panel_state then
    local name = active.get_active_group() or "Editor"
    local parts = path_utils.split_path(name)
    local display_name = parts[#parts] or name
    state.panel_state:update_panel_title(state.PANEL_EDITOR, " " .. display_name .. " ")
    state.panel_state:render_panel(state.PANEL_GROUPS)
  end
end

---Render the left panel (refresh group list).
function M.render_groups()
  if state.panel_state then
    state.panel_state:render_panel(state.PANEL_GROUPS)
  end
end

---Update the right panel title with active group name (includes unsaved marker if dirty).
function M.update_editor_title()
  if state.panel_state then
    local name = active.get_active_group() or "Editor"
    local parts = path_utils.split_path(name)
    local display_name = parts[#parts] or name
    local title = state.has_unsaved_changes
      and (state.unsaved_marker .. " " .. display_name .. " ")
      or (" " .. display_name .. " ")
    state.panel_state:update_panel_title(state.PANEL_EDITOR, title)
  end
end

---Set ignore changes flag (used during spinner/loading).
---@param value boolean
function M.set_ignore_changes(value)
  state.ignore_changes = value
end

---Sync current expanded paths from UI tree_state to data layer for persistence.
function M.sync_expanded_paths()
  active.set_expanded_paths(state.tree_state.expanded)
end

---Get the visible tree node under cursor (delegated to tree_state).
---@return TreeNode?
function M.get_node_under_cursor()
  return tree_state.get_node_under_cursor()
end

---Get the group path under cursor (delegated to tree_state).
---@return string?
function M.get_group_under_cursor()
  return tree_state.get_group_under_cursor()
end

return M
