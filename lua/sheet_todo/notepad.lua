-- Floating notepad buffer management
local M = {}

local float_provider = require('sheet_todo.float_provider')
local cfg = require('sheet_todo.config')
local hide_completed = require('sheet_todo.features.hide_completed')

-- State
local state = {
  buf = nil,
  win = nil,
  float_win = nil,          -- FloatWindow instance (nil in raw mode)
  is_open = false,
  -- Saved state tracking
  saved_content = nil,        -- Last saved content from cloud
  unsaved_content = nil,      -- Unsaved local changes
  has_unsaved_changes = false,
  ignore_changes = false,     -- Flag to ignore buffer changes during initial load
  resize_autocmd_id = nil,    -- Autocmd ID for window resize (raw mode only)
}

local float_title = ' Notes '
local unsaved_marker = '●'

-- Build the title string based on unsaved state
local function get_title()
  if state.has_unsaved_changes then
    return unsaved_marker .. float_title
  end
  return float_title
end

-- Jump cursor to the next unchecked todo, wrapping around
local function jump_to_next_todo()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local current_line = cursor[1] -- 1-indexed
  local total = #lines

  -- Search forward from cursor+1, then wrap from 1 to cursor
  for offset = 1, total do
    local idx = ((current_line - 1 + offset) % total) + 1
    if lines[idx]:match('^%s*%- %[ %]') then
      vim.api.nvim_win_set_cursor(state.win, { idx, 0 })
      return
    end
  end

  vim.notify("No unchecked todos", vim.log.levels.INFO)
end

-- Action handlers table (action name -> function)
local actions = {
  close = function() M.close() end,
  save = function() M.save() end,
  revert = function() M.revert_unsaved_changes() end,
  toggle_completed = function()
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      hide_completed.toggle(state.buf)
    end
  end,
  next_todo = function() jump_to_next_todo() end,
}

---Format a key or key table for display in controls
---@param k string|string[]
---@return string
local function fmt_key(k)
  if type(k) == 'table' then return table.concat(k, ' / ') end
  return k
end

-- Build keymaps table for nvim-float mode from config
local function build_nvim_float_keymaps()
  local km = cfg.get('keymaps')
  local result = {}
  for action_name, keys in pairs(km) do
    local handler = actions[action_name]
    if handler then
      if type(keys) == 'table' then
        for _, key in ipairs(keys) do
          result[key] = handler
        end
      else
        result[keys] = handler
      end
    end
  end
  return result
end

-- Set buffer-local keymaps for raw mode from config
local function setup_buffer_keymaps(buf)
  local km = cfg.get('keymaps')
  local opts = { buffer = buf, nowait = true, silent = true }
  for action_name, keys in pairs(km) do
    local handler = actions[action_name]
    if handler then
      if type(keys) == 'table' then
        for _, key in ipairs(keys) do
          vim.keymap.set('n', key, handler, opts)
        end
      else
        vim.keymap.set('n', keys, handler, opts)
      end
    end
  end
end

-- Set up insert-mode save keymap (both modes need this)
local function setup_insert_keymaps(buf)
  local save_key = cfg.get('keymaps').save or '<C-s>'
  if type(save_key) == 'table' then save_key = save_key[1] end
  vim.keymap.set('i', save_key, actions.save, { buffer = buf, nowait = true, silent = true })
end

-- Build controls array for nvim-float's "? = Controls" footer
local function build_controls()
  local km = cfg.get('keymaps')
  return {
    { header = "Editing", keys = {
      { key = fmt_key(km.save), desc = "Save to cloud" },
      { key = fmt_key(km.revert), desc = "Revert to saved" },
    }},
    { header = "View", keys = {
      { key = fmt_key(km.toggle_completed), desc = "Hide/show completed" },
      { key = fmt_key(km.next_todo), desc = "Jump to next todo" },
    }},
    { header = "Window", keys = {
      { key = fmt_key(km.close), desc = "Close" },
      { key = "?", desc = "Show controls" },
    }},
  }
end

-- Disable autocomplete on the notepad buffer
local function disable_completion(buf)
  if not cfg.get('disable_completion') then
    return
  end
  vim.b[buf].sheet_todo_buffer = true
  vim.b[buf].completion = false -- blink.cmp
  pcall(function()
    require('cmp').setup.buffer({ enabled = false }) -- nvim-cmp
  end)
end

-- Attach change tracking to the buffer
local function attach_change_tracking(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if state.ignore_changes then
        return
      end
      vim.schedule(function()
        M.update_unsaved_state()
      end)
    end,
  })
end

-- Create floating window
function M.create_float()
  -- Reset unsaved changes state on fresh open (will be set to true if restoring unsaved content)
  if not state.is_open then
    state.has_unsaved_changes = false
  end

  local keymaps = build_nvim_float_keymaps()
  local controls = build_controls()

  -- Create float via provider
  local buf, win, float_win = float_provider.create_float({
    title = get_title(),
    keymaps = keymaps,
    controls = controls,
    on_close = function()
      -- Store unsaved content before nvim-float wipes the buffer
      if state.has_unsaved_changes and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        if hide_completed.is_active() then
          state.unsaved_content = hide_completed.get_full_content(state.buf)
        else
          state.unsaved_content = M.get_content()
        end
      end
      hide_completed.reset()
      state.win = nil
      state.buf = nil
      state.float_win = nil
      state.is_open = false
    end,
  })

  state.buf = buf
  state.win = win
  state.float_win = float_win
  state.is_open = true

  -- In raw mode, set keymaps directly on the buffer
  if not float_win then
    setup_buffer_keymaps(buf)
  end

  -- Insert-mode save keymap needs to be set directly regardless of provider
  setup_insert_keymaps(buf)

  -- Track buffer changes to detect unsaved edits
  attach_change_tracking(buf)

  -- Suppress autocomplete popups on notepad buffer
  disable_completion(buf)

  -- Set up resize autocmd (raw mode only; nvim-float handles this internally)
  if not float_win then
    if state.resize_autocmd_id then
      vim.api.nvim_del_autocmd(state.resize_autocmd_id)
    end
    state.resize_autocmd_id = vim.api.nvim_create_autocmd('VimResized', {
      callback = function()
        M.resize_window()
      end,
    })
  end

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

-- Get full content including hidden completed tasks (for saving)
function M.get_full_content()
  if hide_completed.is_active() then
    return hide_completed.get_full_content(state.buf)
  end
  return M.get_content()
end

-- Set cursor position
function M.set_cursor(line, col)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  -- Clamp to valid position
  local total_lines = vim.api.nvim_buf_line_count(state.buf)
  line = math.max(1, math.min(line, total_lines))

  vim.api.nvim_win_set_cursor(state.win, { line, col })
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
    if state.has_unsaved_changes then
      if hide_completed.is_active() then
        state.unsaved_content = hide_completed.get_full_content(state.buf)
      else
        state.unsaved_content = M.get_content()
      end
    end
  end

  hide_completed.reset()
  float_provider.close(state.win, state.float_win)
  state.win = nil
  state.float_win = nil
  state.is_open = false

  -- Clean up resize autocmd (raw mode only)
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
      "  Loading from cloud...",
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

  float_provider.update_title(state.win, state.float_win, get_title())
end

-- Revert to last saved content
function M.revert_unsaved_changes()
  if not state.saved_content then
    vim.notify("No saved content to revert to", vim.log.levels.WARN)
    return
  end

  -- Reset hide state before reverting (show all lines)
  hide_completed.reset()

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
  float_provider.resize(state.win, state.float_win)
end

return M
