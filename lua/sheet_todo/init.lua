local M = {}

local notepad = require('sheet_todo.notepad')
local pantry = require('sheet_todo.pantry')
local config = require('sheet_todo.config')
local ui = require('sheet_todo.ui')

-- State tracking
M.state = {
  bufnr = nil,
  winnr = nil,
  loading = false,
  saving = false,
  last_error = nil
}

-- Show the notepad
function M.show()
  if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
    -- Already open, focus it
    if M.state.winnr and vim.api.nvim_win_is_valid(M.state.winnr) then
      vim.api.nvim_set_current_win(M.state.winnr)
      return
    end
  end

  -- Create floating window
  M.state.bufnr, M.state.winnr = notepad.create_float()
  
  -- Set up save callback
  notepad.on_save = M.save
  
  -- Start animated spinner
  ui.start_spinner("Loading from Pantry", function(frame)
    if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
      vim.schedule(function()
        if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
          vim.api.nvim_buf_set_option(M.state.bufnr, 'modifiable', true)
          vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, {
            "",
            "  " .. frame .. " Loading from Pantry...",
            ""
          })
          vim.api.nvim_buf_set_option(M.state.bufnr, 'modifiable', false)
        end
      end)
    end
  end)
  
  -- Load content from Pantry
  M.state.loading = true
  
  pantry.get_content(function(success, data, err)
    M.state.loading = false
    ui.stop_spinner()
    
    if not success then
      M.state.last_error = err
      vim.notify("Failed to load: " .. (err or "unknown error"), vim.log.levels.ERROR)
      -- Still allow editing with empty content
      notepad.set_content({" "})
      return
    end
    
    if data and data.content then
      -- Split content into lines
      local lines = vim.split(data.content, "\n", { plain = true })
      notepad.set_content(lines)
      
      -- Restore cursor position
      if data.cursor_pos then
        notepad.set_cursor(data.cursor_pos.line, data.cursor_pos.col)
      end
      
      vim.notify("Notepad loaded", vim.log.levels.INFO)
    else
      -- Empty basket or first time
      notepad.set_content({" "})
      vim.notify("New notepad created", vim.log.levels.INFO)
    end
  end)
end

-- Save the notepad content
function M.save()
  if not M.state.bufnr or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    vim.notify("No notepad buffer to save", vim.log.levels.WARN)
    return
  end
  
  if M.state.saving then
    vim.notify("Already saving...", vim.log.levels.WARN)
    return
  end
  
  -- Get current content and cursor position
  local content = notepad.get_content()
  local cursor_pos = notepad.get_cursor()
  
  M.state.saving = true
  vim.notify("Saving to Pantry...", vim.log.levels.INFO)
  
  pantry.save_content(content, cursor_pos, function(success, err)
    M.state.saving = false
    
    if success then
      vim.notify("Saved successfully", vim.log.levels.INFO)
      M.state.last_error = nil
    else
      M.state.last_error = err
      vim.notify("Save failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

-- Close the notepad
function M.close()
  if M.state.winnr and vim.api.nvim_win_is_valid(M.state.winnr) then
    vim.api.nvim_win_close(M.state.winnr, true)
  end
  M.state.winnr = nil
  M.state.bufnr = nil
end

-- Show status
function M.status()
  local lines = {
    "Sheet Todo Notepad Status",
    "========================",
    "",
    "Configuration:",
    "  Pantry ID: " .. (config.get('pantry_id') or "NOT SET"),
    "  Basket: " .. (config.get('basket_name') or "NOT SET"),
    "",
    "State:",
    "  Buffer: " .. (M.state.bufnr and "active" or "inactive"),
    "  Window: " .. (M.state.winnr and vim.api.nvim_win_is_valid(M.state.winnr) and "open" or "closed"),
    "  Loading: " .. (M.state.loading and "yes" or "no"),
    "  Saving: " .. (M.state.saving and "yes" or "no"),
    "  Last Error: " .. (M.state.last_error or "none"),
  }
  
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
  
  -- Update config with user options
  if opts.pantry_id then
    config.set('pantry_id', opts.pantry_id)
  end
  if opts.basket_name then
    config.set('basket_name', opts.basket_name)
  end
  
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
