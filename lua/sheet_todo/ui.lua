-- ============================================================================
-- UI MODULE
-- ============================================================================
-- Manages the split window viewer and spinner animations
--
-- LEARNING POINTS:
-- - Window and buffer management
-- - Async UI updates with spinners
-- - Non-blocking animations
-- ============================================================================

local config = require('sheet_todo.config')

local M = {}

-- UI state
local state = {
  viewer_buf = nil,
  viewer_win = nil,
  spinner_timer = nil,
  spinner_callback = nil,
  current_frame = 1,
}

-- Get async library
local uv = vim.uv or vim.loop

-- ============================================================================
-- VIEWER WINDOW
-- ============================================================================

-- Create or get the viewer buffer
local function create_viewer_buffer()
  if state.viewer_buf and vim.api.nvim_buf_is_valid(state.viewer_buf) then
    return state.viewer_buf
  end
  
  state.viewer_buf = vim.api.nvim_create_buf(false, true)
  
  vim.api.nvim_buf_set_option(state.viewer_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(state.viewer_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.viewer_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.viewer_buf, 'filetype', 'sheet_todo')
  vim.api.nvim_buf_set_name(state.viewer_buf, '[Google Sheets Todos]')
  
  return state.viewer_buf
end

-- Open the viewer window
function M.open_viewer()
  local buf = create_viewer_buffer()
  
  -- Check if window already exists
  if state.viewer_win and vim.api.nvim_win_is_valid(state.viewer_win) then
    -- Window exists, just focus it
    vim.api.nvim_set_current_win(state.viewer_win)
    return state.viewer_win
  end
  
  -- Calculate window height
  local height = math.floor(vim.api.nvim_get_option("lines") * (config.get('split_height_percent') / 100))
  
  -- Create split at bottom
  vim.cmd('botright split')
  state.viewer_win = vim.api.nvim_get_current_win()
  
  -- Set buffer
  vim.api.nvim_win_set_buf(state.viewer_win, buf)
  vim.api.nvim_win_set_height(state.viewer_win, height)
  
  -- Window options
  vim.api.nvim_win_set_option(state.viewer_win, 'number', false)
  vim.api.nvim_win_set_option(state.viewer_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(state.viewer_win, 'cursorline', true)
  vim.api.nvim_win_set_option(state.viewer_win, 'wrap', false)
  
  -- Return focus to previous window
  vim.cmd('wincmd p')
  
  return state.viewer_win
end

-- Get viewer buffer number
function M.get_viewer_buffer()
  return state.viewer_buf
end

-- Close the viewer window
function M.close_viewer()
  if state.viewer_win and vim.api.nvim_win_is_valid(state.viewer_win) then
    vim.api.nvim_win_close(state.viewer_win, true)
    state.viewer_win = nil
  end
end

-- Update viewer content
function M.show_in_viewer(lines)
  local buf = create_viewer_buffer()
  
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Make buffer modifiable
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  
  -- Set content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Make buffer read-only
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

-- ============================================================================
-- SPINNER ANIMATION
-- ============================================================================

-- Start spinner with custom callback
function M.start_spinner(message, callback)
  M.stop_spinner()
  
  state.spinner_callback = callback or function(frame)
    M.show_in_viewer({message .. " " .. frame})
  end
  
  local frames = config.get('spinner_frames')
  state.current_frame = 1
  
  state.spinner_timer = uv.new_timer()
  state.spinner_timer:start(0, 80, function()
    local frame = frames[state.current_frame]
    
    vim.schedule(function()
      if state.spinner_callback then
        state.spinner_callback(frame)
      end
    end)
    
    state.current_frame = state.current_frame % #frames + 1
  end)
end

-- Show spinner with default message
function M.show_spinner(message)
  M.open_viewer()
  M.start_spinner(message)
end

-- Stop spinner
function M.stop_spinner()
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
  state.spinner_callback = nil
end

-- ============================================================================
-- STATUS MESSAGES
-- ============================================================================

-- Show a status message in the viewer
function M.show_status(message)
  M.open_viewer()
  M.show_in_viewer({
    "",
    "  " .. message,
    "",
  })
end

-- Show an error in the viewer
function M.show_error(error_msg)
  M.open_viewer()
  M.show_in_viewer({
    "❌ Error",
    "",
    error_msg,
  })
end

return M
