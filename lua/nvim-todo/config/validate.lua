---@class nvim-todo.config.validate
local M = {}

---Validate that required configuration fields are present.
---@param config table The current runtime config
---@return boolean valid True if all required fields are set
function M.validate(config)
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
    vim.notify(msg, vim.log.levels.WARN)
    vim.notify("   Create your Pantry at https://getpantry.cloud", vim.log.levels.INFO)
    return false
  end

  return true
end

return M
