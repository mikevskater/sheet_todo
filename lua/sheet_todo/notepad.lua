-- Floating notepad buffer management
local M = {}

-- State
local state = {
  buf = nil,
  win = nil,
  is_open = false,
  -- Saved state tracking
  saved_content = nil,        -- Last saved content from cloud
  unsaved_content = nil,      -- Unsaved local changes
  has_unsaved_changes = false,
  ignore_changes = false,     -- Flag to ignore buffer changes during initial load
  resize_autocmd_id = nil,    -- Autocmd ID for window resize
}

local float_title = ' Notes '
local unsaved_marker = '●'

-- Create floating window
function M.create_float()
  -- Reset unsaved changes state on fresh open (will be set to true if restoring unsaved content)
  if not state.is_open then
    state.has_unsaved_changes = false
  end
  
  -- Get editor dimensions
  local width = vim.o.columns
  local height = vim.o.lines
  
  -- Calculate floating window size (80% of screen)
  local win_width = math.floor(width * 0.8)
  local win_height = math.floor(height * 0.8)
  
  -- Calculate position (centered)
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)
  
  -- Create buffer if it doesn't exist
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true) -- not listed, scratch
    vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(state.buf, 'filetype', 'markdown')
  end

  -- Window options  
  local opts = {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = state.has_unsaved_changes and (unsaved_marker .. float_title) or float_title,
    title_pos = 'center',
  }
  
  -- Create window
  state.win = vim.api.nvim_open_win(state.buf, true, opts)
  state.is_open = true
  
  -- Window options
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  vim.api.nvim_win_set_option(state.win, 'linebreak', true)
  
  -- Set buffer keymaps
  local keymap_opts = { buffer = state.buf, nowait = true, silent = true }
  
  -- Close on <Esc> in normal mode
  vim.keymap.set('n', '<Esc>', function()
    M.close()
  end, keymap_opts)
  
  -- Close on 'q' in normal mode
  vim.keymap.set('n', 'q', function()
    M.close()
  end, keymap_opts)
  
  -- Revert unsaved changes on <A-r>
  vim.keymap.set('n', '<A-r>', function()
    M.revert_unsaved_changes()
  end, keymap_opts)
  
  -- Save on Ctrl+S
  vim.keymap.set({'n', 'i'}, '<C-s>', function()
    M.save()
  end, keymap_opts)
  
  -- Track buffer changes to detect unsaved edits
  vim.api.nvim_buf_attach(state.buf, false, {
    on_lines = function()
      if state.ignore_changes then
        return
      end
      vim.schedule(function()
        M.update_unsaved_state()
      end)
    end,
  })
  
  -- Set up resize autocmd
  if state.resize_autocmd_id then
    vim.api.nvim_del_autocmd(state.resize_autocmd_id)
  end
  state.resize_autocmd_id = vim.api.nvim_create_autocmd('VimResized', {
    callback = function()
      M.resize_window()
    end,
  })
  
  return state.buf, state.win
end

-- Set content in buffer
function M.set_content(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  -- Ignore buffer changes during initial content load
  state.ignore_changes = true
  
  -- Make buffer modifiable
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  
  -- Set lines
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  
  -- Mark as not modified
  vim.api.nvim_buf_set_option(state.buf, 'modified', false)
  
  -- Store as saved content
  state.saved_content = table.concat(lines, "\n")
  state.has_unsaved_changes = false
  
  -- Re-enable change tracking after a short delay
  vim.schedule(function()
    state.ignore_changes = false
  end)
end

-- Get content from buffer
function M.get_content()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return ""
  end
  
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  return table.concat(lines, "\n")
end

-- Set cursor position
function M.set_cursor(line, col)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  
  -- Clamp to valid position
  local total_lines = vim.api.nvim_buf_line_count(state.buf)
  line = math.max(1, math.min(line, total_lines))
  
  vim.api.nvim_win_set_cursor(state.win, {line, col})
end

-- Get cursor position
function M.get_cursor()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return { line = 1, col = 0 }
  end
  
  local pos = vim.api.nvim_win_get_cursor(state.win)
  return { line = pos[1], col = pos[2] }
end

-- Close the floating window
function M.close()
  -- Store current content if there are unsaved changes
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local current_content = M.get_content()
    if state.has_unsaved_changes then
      state.unsaved_content = current_content
    end
  end
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.is_open = false
  
  -- Clean up resize autocmd
  if state.resize_autocmd_id then
    vim.api.nvim_del_autocmd(state.resize_autocmd_id)
    state.resize_autocmd_id = nil
  end
end

-- Check if window is open
function M.is_open()
  return state.is_open and state.win and vim.api.nvim_win_is_valid(state.win)
end

-- Show loading message
function M.show_loading()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
      "",
      "  ⏳ Loading from cloud...",
      ""
    })
    vim.api.nvim_buf_set_option(state.buf, 'modifiable', false)
  end
end

-- Trigger save callback
M.on_save = nil

function M.save()
  if M.on_save then
    M.on_save()
  end
end

-- Update unsaved state and window title
function M.update_unsaved_state()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  local current_content = M.get_content()
  local prev_unsaved_state = state.has_unsaved_changes
  
  -- Check if content differs from saved content
  if state.saved_content then
    state.has_unsaved_changes = (current_content ~= state.saved_content)
  else
    state.has_unsaved_changes = (#current_content > 0)
  end
  
  -- Update window title if state changed
  if prev_unsaved_state ~= state.has_unsaved_changes and state.win and vim.api.nvim_win_is_valid(state.win) then
    M.update_window_title()
  end
end

-- Update window title with unsaved indicator
function M.update_window_title()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  
  vim.api.nvim_win_set_config(state.win, {
    title = state.has_unsaved_changes and (unsaved_marker .. float_title) or float_title,
    title_pos = 'center',
  })
end

-- Revert to last saved content
function M.revert_unsaved_changes()
  if not state.saved_content then
    vim.notify("No saved content to revert to", vim.log.levels.WARN)
    return
  end
  
  -- Restore saved content
  local lines = vim.split(state.saved_content, "\n", { plain = true })
  
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.buf, 'modified', false)
  end
  
  -- Clear unsaved changes
  state.unsaved_content = nil
  state.has_unsaved_changes = false
  M.update_window_title()
  
  vim.notify("Reverted to last saved content", vim.log.levels.INFO)
end

-- Mark content as saved (called after successful save)
function M.mark_as_saved()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local current_content = M.get_content()
    state.saved_content = current_content
    state.unsaved_content = nil
    state.has_unsaved_changes = false
    M.update_window_title()
  end
end

-- Check if has unsaved content to restore
function M.has_unsaved_content()
  return state.unsaved_content ~= nil
end

-- Get unsaved content
function M.get_unsaved_content()
  return state.unsaved_content
end

-- Set ignore changes flag (used by init.lua during spinner animation)
function M.set_ignore_changes(value)
  state.ignore_changes = value
end

-- Restore unsaved content with proper change tracking
function M.restore_unsaved_content(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  -- Temporarily disable change tracking
  state.ignore_changes = true
  
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, 'modified', true)
  
  -- Re-enable change tracking and mark as having unsaved changes
  vim.schedule(function()
    state.ignore_changes = false
    state.has_unsaved_changes = true
    M.update_window_title()
  end)
end

-- Resize window when terminal is resized
function M.resize_window()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  
  -- Get new editor dimensions
  local width = vim.o.columns
  local height = vim.o.lines
  
  -- Calculate new floating window size (80% of screen)
  local win_width = math.floor(width * 0.8)
  local win_height = math.floor(height * 0.8)
  
  -- Calculate new position (centered)
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)
  
  -- Update window configuration
  vim.api.nvim_win_set_config(state.win, {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
  })
end

return M