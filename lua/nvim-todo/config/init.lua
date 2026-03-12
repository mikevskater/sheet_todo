---@class nvim-todo.config
local M = {}

local defaults = require('nvim-todo.config.defaults')
local validate = require('nvim-todo.config.validate')

---@type table Current runtime configuration
local config = {}

---Initialize configuration by merging user opts into defaults.
---@param opts table? User-provided configuration overrides
function M.setup(opts)
  config = vim.tbl_deep_extend('force', defaults, opts or {})
  M.validate()
end

---Validate current configuration.
---@return boolean valid True if all required fields are set
function M.validate()
  return validate.validate(config)
end

---Get a configuration value by key.
---@param key string Configuration key
---@return any value The config value, falling back to default
function M.get(key)
  if config[key] ~= nil then
    return config[key]
  end
  return defaults[key]
end

---Get a deep copy of the entire configuration.
---@return table config Copy of runtime config
function M.get_all()
  return vim.deepcopy(config)
end

---Update a configuration value at runtime.
---@param key string Configuration key
---@param value any New value
function M.set(key, value)
  config[key] = value
end

return M
