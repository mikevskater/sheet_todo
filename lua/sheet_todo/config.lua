-- ============================================================================
-- CONFIGURATION MODULE
-- ============================================================================
-- Manages plugin configuration with sensible defaults

local M = {}

-- Default configuration
local defaults = {
  -- Pantry settings (REQUIRED)
  pantry_id = "",  -- Get from https://getpantry.cloud
  basket_name = "todos",   -- Name of the basket to store your todos
  
  -- UI settings
  split_height_percent = 25,
  spinner_frames = {"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"},
  
  -- Float window provider
  use_nvim_float = true,  -- Use nvim-float if available (false = always raw API)

  -- Keymaps (customizable key bindings)
  keymaps = {
    close = { '<Esc>', 'q' },
    save = '<C-s>',
    revert = '<A-r>',
    toggle_completed = '<leader>h',
    next_todo = 'n',
    toggle_line_numbers = '<leader>l',
    toggle_checkbox = '<C-t>',
  },

  -- Completion
  disable_completion = true,  -- Disable autocomplete (blink.cmp / nvim-cmp) in notepad buffer

  -- Folding
  collapsible_headers = true,  -- Collapsible markdown headers via foldmethod=expr

  -- Sticky headers
  sticky_headers = true,  -- Show ancestor headers at top of window when scrolled past

  -- Multi-panel (Phase 7)
  multi_panel = true,          -- Enable left panel with group tabs (requires nvim-float)
  left_panel_width = 0.25,      -- Left panel width ratio

  -- Group color presets (Phase 8)
  group_color_presets = {
    { name = "Red", color = "#E06C75" },
    { name = "Green", color = "#98C379" },
    { name = "Blue", color = "#61AFEF" },
    { name = "Yellow", color = "#E5C07B" },
    { name = "Purple", color = "#C678DD" },
    { name = "Cyan", color = "#56B6C2" },
    { name = "Orange", color = "#D19A66" },
  },

  -- Storage limit
  pantry_basket_limit_bytes = 1509949,  -- 1.44 MB per Pantry basket

  -- Behavior
  auto_refresh = false,  -- Auto-refresh todos periodically
  refresh_interval_ms = 30000,  -- 30 seconds
  timeout_ms = 10000,  -- 10 second timeout for HTTP requests
}

-- Current configuration
local config = {}

-- Setup configuration
function M.setup(opts)
  config = vim.tbl_deep_extend('force', defaults, opts or {})
  
  -- Validate required fields
  M.validate()
end

-- Validate configuration
function M.validate()
  local required = {
    'pantry_id',
  }
  
  local missing = {}
  for _, field in ipairs(required) do
    if not config[field] or config[field] == "" then
      table.insert(missing, field)
    end
  end
  
  if #missing > 0 then
    local msg = "Missing required configuration: " .. table.concat(missing, ", ")
    vim.notify("⚠️  " .. msg, vim.log.levels.WARN)
    vim.notify("   Create your Pantry at https://getpantry.cloud", vim.log.levels.INFO)
    return false
  end
  
  return true
end

-- Get configuration value
function M.get(key)
  -- Return from config if set, otherwise from defaults
  if config[key] ~= nil then
    return config[key]
  end
  return defaults[key]
end

-- Get all configuration
function M.get_all()
  return vim.deepcopy(config)
end

-- Update configuration
function M.set(key, value)
  config[key] = value
end

return M
