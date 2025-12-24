-- Floating notepad buffer management
local M = {}

-- State
local state = {
  buf = nil,
  win = nil,
  is_open = false,
}

-- Create floating window
function M.create_float()
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
    title = ' 📝 Cloud Notepad (Pantry) ',
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
  
  -- Save on Ctrl+S
  vim.keymap.set({'n', 'i'}, '<C-s>', function()
    M.save()
  end, keymap_opts)
  
  return state.buf, state.win
end

-- Set content in buffer
function M.set_content(lines)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  
  -- Make buffer modifiable
  vim.api.nvim_buf_set_option(state.buf, 'modifiable', true)
  
  -- Set lines
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  
  -- Mark as not modified
  vim.api.nvim_buf_set_option(state.buf, 'modified', false)
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
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.is_open = false
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

return M
