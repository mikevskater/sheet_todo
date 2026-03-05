local M = {}

local pantry = require('sheet_todo.pantry')
local config = require('sheet_todo.config')
local multi_panel = require('sheet_todo.multi_panel')
local group_manager = require('sheet_todo.group_manager')

-- State tracking
M.state = {
  loading = false,
  saving = false,
  last_error = nil,
}

-- Show the notepad (always multi-panel)
function M.show()
  -- Already open, focus it
  if multi_panel.is_open() then
    return
  end

  -- Create multi-panel UI
  multi_panel.show(M.save)

  -- Disable change tracking during load
  multi_panel.set_ignore_changes(true)

  -- Load content from Pantry (raw data for group_manager)
  M.state.loading = true

  pantry.get_raw_data(function(success, data, err)
    M.state.loading = false

    if not success then
      M.state.last_error = err
      vim.notify("Failed to load: " .. (err or "unknown error"), vim.log.levels.ERROR)
      -- Load empty default group
      group_manager.load(nil)
      multi_panel.set_content(group_manager.get_active_content())
      multi_panel.render_groups()
      multi_panel.update_editor_title()
      return
    end

    -- Load into group_manager (handles format detection/migration)
    group_manager.load(data)

    -- Set right panel content from active group
    multi_panel.set_content(group_manager.get_active_content())

    -- Restore cursor position
    vim.schedule(function()
      local cursor = group_manager.get_active_cursor()
      if cursor then
        multi_panel.set_cursor(cursor)
      end
    end)

    -- Render left panel with groups
    multi_panel.render_groups()

    -- Update right panel title
    multi_panel.update_editor_title()

    vim.notify("Notepad loaded (" .. group_manager.get_group_count() .. " groups)", vim.log.levels.INFO)
  end)
end

-- Save all groups to Pantry
function M.save()
  if M.state.saving then
    vim.notify("Already saving...", vim.log.levels.WARN)
    return
  end

  -- Collect right panel content into group_manager
  group_manager.set_active_content(multi_panel.get_content())
  group_manager.set_active_cursor(multi_panel.get_cursor())

  -- Serialize all groups and save
  local data = group_manager.serialize()

  M.state.saving = true
  vim.notify("Saving to Pantry...", vim.log.levels.INFO)

  pantry.save_raw_data(data, function(success, err)
    M.state.saving = false

    if success then
      vim.notify("Saved successfully", vim.log.levels.INFO)
      M.state.last_error = nil
      multi_panel.mark_as_saved()
    else
      M.state.last_error = err
      vim.notify("Save failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

-- Close the notepad
function M.close()
  multi_panel.close()
  group_manager.reset()
end

-- Show status
function M.status()
  local has_nvim_float = pcall(require, 'nvim-float')
  local lines = {
    "Sheet Todo Notepad Status",
    "========================",
    "",
    "Configuration:",
    "  Pantry ID: " .. (config.get('pantry_id') or "NOT SET"),
    "  Basket: " .. (config.get('basket_name') or "NOT SET"),
    "  Float Provider: " .. (has_nvim_float and "nvim-float" or "raw"),
    "",
    "State:",
    "  Window: " .. (multi_panel.is_open() and "open" or "closed"),
    "  Loading: " .. (M.state.loading and "yes" or "no"),
    "  Saving: " .. (M.state.saving and "yes" or "no"),
    "  Last Error: " .. (M.state.last_error or "none"),
  }

  if group_manager.is_loaded() then
    table.insert(lines, "")
    table.insert(lines, "Groups:")
    table.insert(lines, "  Active: " .. (group_manager.get_active_group() or "none"))
    table.insert(lines, "  Count: " .. group_manager.get_group_count())
  end

  -- Create status buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  -- Open in split
  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, #lines + 2)
end

-- Setup function
function M.setup(opts)
  opts = opts or {}

  -- Initialize config with all user options
  config.setup(opts)

  -- Register commands
  vim.api.nvim_create_user_command('TodoShow', M.show, {})
  vim.api.nvim_create_user_command('TodoSave', M.save, {})
  vim.api.nvim_create_user_command('TodoClose', M.close, {})
  vim.api.nvim_create_user_command('TodoStatus', M.status, {})

  -- Register keymap
  vim.keymap.set('n', '<leader>otd', M.show, { desc = 'Open Todo notepad' })

  vim.notify("Sheet Todo Notepad ready. Use :TodoShow or <leader>otd to open.", vim.log.levels.INFO)
end

return M
