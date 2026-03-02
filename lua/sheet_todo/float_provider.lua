-- Float window provider abstraction
-- Uses nvim-float if available, otherwise falls back to raw nvim API
local M = {}

local config = require('sheet_todo.config')

-- Detect nvim-float availability
local has_nvim_float, nvim_float = pcall(require, 'nvim-float')

---Check if nvim-float is available and enabled
---@return boolean
function M.has_nvim_float()
  return has_nvim_float and config.get('use_nvim_float')
end

---Create a floating window
---@param opts { title: string, keymaps: table?, controls: table?, on_close: function? }
---@return number bufnr, number winid, table? float_win FloatWindow instance (nil in raw mode)
function M.create_float(opts)
  opts = opts or {}
  if M.has_nvim_float() then
    return M._create_nvim_float(opts)
  else
    return M._create_raw_float(opts)
  end
end

---Update the window title
---@param winid number
---@param float_win table? FloatWindow instance (nil in raw mode)
---@param title string
function M.update_title(winid, float_win, title)
  if float_win then
    float_win:update_title(title)
  else
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_config(winid, {
        title = title,
        title_pos = 'center',
      })
    end
  end
end

---Close the float window
---@param winid number
---@param float_win table? FloatWindow instance (nil in raw mode)
function M.close(winid, float_win)
  if float_win then
    float_win:close()
  else
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end
end

---Resize the window (raw mode only; nvim-float handles this internally)
---@param winid number
---@param float_win table? FloatWindow instance (nil in raw mode)
function M.resize(winid, float_win)
  if float_win then
    -- nvim-float handles VimResized internally
    return
  end

  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local width = vim.o.columns
  local height = vim.o.lines
  local win_width = math.floor(width * 0.8)
  local win_height = math.floor(height * 0.8)
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)

  vim.api.nvim_win_set_config(winid, {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
  })
end

-- ============================================================================
-- nvim-float path
-- ============================================================================

---@private
function M._create_nvim_float(opts)
  nvim_float.ensure_setup()

  local width = vim.o.columns
  local height = vim.o.lines
  local win_width = math.floor(width * 0.8)
  local win_height = math.floor(height * 0.8)

  local float_win = nvim_float.create({ "" }, {
    title = opts.title or "Notes",
    title_pos = "center",
    border = "rounded",
    width = win_width,
    height = win_height,
    -- Must be editable for notepad usage
    modifiable = true,
    readonly = false,
    -- Markdown for syntax highlighting
    filetype = "markdown",
    buftype = "nofile",
    -- We provide our own close handlers (to preserve unsaved content)
    default_keymaps = false,
    -- Wrapping for markdown content
    wrap = true,
    cursorline = false,
    -- Scrollbar
    scrollbar = true,
    -- Keymaps and controls from caller
    keymaps = opts.keymaps or {},
    controls = opts.controls,
    on_close = opts.on_close,
  })

  if not float_win or not float_win.winid then
    -- Fallback to raw if nvim-float creation failed
    return M._create_raw_float(opts)
  end

  -- nvim-float doesn't set linebreak; enable it for markdown word wrapping
  if vim.api.nvim_win_is_valid(float_win.winid) then
    vim.api.nvim_set_option_value('linebreak', true, { win = float_win.winid })
  end

  return float_win.bufnr, float_win.winid, float_win
end

-- ============================================================================
-- Raw nvim API path (fallback)
-- ============================================================================

---@private
function M._create_raw_float(opts)
  local width = vim.o.columns
  local height = vim.o.lines
  local win_width = math.floor(width * 0.8)
  local win_height = math.floor(height * 0.8)
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')

  -- Window options
  local win_opts = {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = opts.title or ' Notes ',
    title_pos = 'center',
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Window display options
  vim.api.nvim_set_option_value('wrap', true, { win = win })
  vim.api.nvim_set_option_value('linebreak', true, { win = win })

  return buf, win, nil
end

return M
