-- Right panel keymap handlers (7 handlers for editor actions).
local M = {}

local state = require('nvim-todo.ui.multi_panel.state')
local right_buffer = require('nvim-todo.ui.panels.right.buffer')
local statuscolumn = require('nvim-todo.ui.multi_panel.statuscolumn')
local active = require('nvim-todo.data.manager.active')
local hide_completed = require('nvim-todo.features.hide_completed')

function M.handle_save()
  if state.on_save then
    state.on_save()
  end
end

function M.handle_revert()
  local store = require('nvim-todo.state.store')
  local pantry = require('nvim-todo.storage.pantry.client')
  local manager = require('nvim-todo.data.manager')
  local cursor_mod = require('nvim-todo.data.group.cursor')
  local sync = require('nvim-todo.ui.multi_panel.sync')

  if store.loading then
    vim.notify("Already loading...", vim.log.levels.WARN)
    return
  end

  store.loading = true
  vim.notify("Refreshing from cloud...", vim.log.levels.INFO)

  pantry.get_raw_data(function(success, data, err)
    store.loading = false
    if not success then
      vim.notify("Refresh failed: " .. (err or "unknown"), vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      hide_completed.reset()
      manager.load(data)

      -- Restore UI tree state
      state.tree_state.expanded = manager.get_expanded_paths()

      -- Load active group content into editor
      right_buffer.set_content(manager.get_active_content())
      state.saved_content = manager.get_active_content()
      state.has_unsaved_changes = false

      vim.schedule(function()
        right_buffer.set_cursor(cursor_mod.get_active_cursor())
      end)

      sync.render_groups()
      sync.update_editor_title()

      vim.notify("Refreshed from cloud (" .. manager.get_group_count() .. " groups)", vim.log.levels.INFO)
    end)
  end)
end

function M.handle_toggle_completed()
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    hide_completed.toggle(state.right_buf)
    statuscolumn.apply()
  end
end

function M.handle_next_todo()
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.right_buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(state.right_win)
  local current_line = cursor[1]
  local total = #lines

  for offset = 1, total do
    local idx = ((current_line - 1 + offset) % total) + 1
    if lines[idx]:match('^%s*%- %[ %]') then
      vim.api.nvim_win_set_cursor(state.right_win, { idx, 0 })
      return
    end
  end

  vim.notify("No unchecked todos", vim.log.levels.INFO)
end

function M.handle_close()
  -- Lazy require to avoid circular dep: keymaps -> close -> keymaps
  require('nvim-todo.ui.multi_panel.close').close()
end

function M.handle_toggle_line_numbers()
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end
  local current = active.get_active_line_numbers()
  local new_state = not current
  active.set_active_line_numbers(new_state)
  vim.api.nvim_set_option_value('number', new_state, { win = state.right_win })
  if new_state then
    vim.api.nvim_set_option_value('relativenumber', vim.o.relativenumber, { win = state.right_win })
  else
    vim.api.nvim_set_option_value('relativenumber', false, { win = state.right_win })
  end
  statuscolumn.apply()
end

function M.handle_toggle_checkbox()
  if not state.right_buf or not vim.api.nvim_buf_is_valid(state.right_buf) then
    return
  end
  if not state.right_win or not vim.api.nvim_win_is_valid(state.right_win) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(state.right_win)
  local lnum = cursor[1]
  local line = vim.api.nvim_buf_get_lines(state.right_buf, lnum - 1, lnum, false)[1]
  if not line then return end

  local new_line
  if line:match('%- %[ %]') then
    new_line = line:gsub('%- %[ %]', '- [x]', 1)
  elseif line:match('%- %[x%]') then
    new_line = line:gsub('%- %[x%]', '- [ ]', 1)
  else
    return
  end

  vim.api.nvim_buf_set_lines(state.right_buf, lnum - 1, lnum, false, { new_line })
end

return M
