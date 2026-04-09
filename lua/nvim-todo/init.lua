---@class nvim-todo
local M = {}

local config = require('nvim-todo.config')
local store = require('nvim-todo.state.store')
local pantry = require('nvim-todo.storage.pantry')
local manager = require('nvim-todo.data.manager')
local cursor = require('nvim-todo.data.group.cursor')
local multi_panel = require('nvim-todo.ui.multi_panel')
local ui_state = require('nvim-todo.ui.multi_panel.state')
local plugin = require('nvim-todo.plugin')

---Open the notepad (always multi-panel).
function M.show()
  if multi_panel.is_open() then
    return
  end

  multi_panel.show(M.save)

  multi_panel.set_ignore_changes(true)

  -- Restore unsaved in-memory content from previous session
  if manager.is_loaded() then
    multi_panel.set_content(manager.get_active_content())
    vim.schedule(function()
      multi_panel.set_cursor(cursor.get_active_cursor())
    end)

    -- Override saved_content baseline with Pantry snapshot so unsaved detection works
    local pantry_snapshot = manager.get_active_saved_content()
    if pantry_snapshot then
      ui_state.saved_content = pantry_snapshot
      ui_state.has_unsaved_changes = (manager.get_active_content() ~= pantry_snapshot)
    end

    multi_panel.render_groups()
    multi_panel.update_editor_title()
    vim.notify("Restored unsaved changes", vim.log.levels.INFO)
    return
  end

  -- Fresh load from Pantry
  store.loading = true

  pantry.get_raw_data(function(success, data, err)
    store.loading = false

    if not success then
      store.last_error = err
      vim.notify("Failed to load: " .. (err or "unknown error"), vim.log.levels.ERROR)
      manager.load(nil)
      multi_panel.set_content(manager.get_active_content())
      multi_panel.render_groups()
      multi_panel.update_editor_title()
      return
    end

    manager.load(data)

    -- Refresh UI tree state from loaded data (expanded paths)
    ui_state.tree_state.expanded = manager.get_expanded_paths()

    multi_panel.set_content(manager.get_active_content())

    vim.schedule(function()
      local cur = cursor.get_active_cursor()
      if cur then
        multi_panel.set_cursor(cur)
      end
    end)

    multi_panel.render_groups()
    multi_panel.update_editor_title()

    vim.notify("Notepad loaded (" .. manager.get_group_count() .. " groups)", vim.log.levels.INFO)
  end)
end

---Save all groups to Pantry.
function M.save()
  if store.saving then
    vim.notify("Already saving...", vim.log.levels.WARN)
    return
  end

  manager.set_active_content(multi_panel.get_content())
  cursor.set_active_cursor(multi_panel.get_cursor())
  multi_panel.sync_expanded_paths()

  local data = manager.serialize()
  local json_str = vim.json.encode(data)
  local payload_bytes = #json_str
  local limit_bytes = config.get('pantry_basket_limit_bytes')

  store.saving = true
  vim.notify("Saving to Pantry...", vim.log.levels.INFO)

  pantry.replace_raw_data(data, function(success, err)
    store.saving = false

    if success then
      local pct = (payload_bytes / limit_bytes) * 100
      local size_kb = payload_bytes / 1024
      local limit_kb = limit_bytes / 1024
      local msg = string.format("Saved - %.1f KB / %.1f KB (%.1f%%)", size_kb, limit_kb, pct)

      local hl
      if pct < 50 then
        hl = "DiagnosticOk"
      elseif pct < 75 then
        hl = "DiagnosticWarn"
      elseif pct < 90 then
        hl = "WarningMsg"
      else
        hl = "DiagnosticError"
      end

      vim.api.nvim_echo({ { msg, hl } }, true, {})

      store.last_error = nil
      manager.mark_as_saved()
      multi_panel.mark_as_saved()
    else
      store.last_error = err
      vim.notify("Save failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

---Close the notepad (group state persists for unsaved content recovery).
function M.close()
  multi_panel.close()
end

---Discard unsaved changes and reset state.
function M.discard()
  manager.reset()
  vim.notify("Unsaved changes discarded. Next open will fetch from Pantry.", vim.log.levels.INFO)
end

---Reset in-memory state and re-fetch from Pantry.
---Unlike :TodoShow (which reuses the loaded state forever within a session),
---this forces a fresh load. Use when the tree looks wrong or a transient load
---error got cached in memory.
---Any unsaved changes will be lost.
function M.reload()
  local was_open = multi_panel.is_open()
  if was_open then
    multi_panel.close()
  end
  manager.reset()
  if was_open then
    M.show()
  else
    vim.notify("Notepad state cleared. Next :TodoShow will fetch from Pantry.", vim.log.levels.INFO)
  end
end

---Show status info in a split buffer.
function M.status()
  local has_nvim_float = pcall(require, 'nvim-float')
  local lines = {
    "nvim-todo Notepad Status",
    "========================",
    "",
    "Configuration:",
    "  Pantry ID: " .. (config.get('pantry_id') or "NOT SET"),
    "  Basket: " .. (config.get('basket_name') or "NOT SET"),
    "  Float Provider: " .. (has_nvim_float and "nvim-float" or "raw"),
    "",
    "State:",
    "  Window: " .. (multi_panel.is_open() and "open" or "closed"),
    "  Loading: " .. (store.loading and "yes" or "no"),
    "  Saving: " .. (store.saving and "yes" or "no"),
    "  Last Error: " .. (store.last_error or "none"),
  }

  if manager.is_loaded() then
    table.insert(lines, "")
    table.insert(lines, "Groups:")
    table.insert(lines, "  Active: " .. (manager.get_active_group() or "none"))
    table.insert(lines, "  Count: " .. manager.get_group_count())
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, #lines + 2)
end

---Initialize nvim-todo with user options.
---@param opts table? User configuration overrides
function M.setup(opts)
  opts = opts or {}
  config.setup(opts)
  plugin.register(M)
  vim.notify("nvim-todo Notepad ready. Use :TodoShow or <leader>otd to open.", vim.log.levels.INFO)
end

return M
