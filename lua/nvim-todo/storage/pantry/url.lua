---@class nvim-todo.storage.pantry.url
local M = {}

local config = require('nvim-todo.config')

---@type string
local PANTRY_BASE_URL = "https://getpantry.cloud/apiv1/pantry"

---Check if Pantry is configured (pantry_id is set and non-empty).
---@return boolean
function M.is_configured()
  local pantry_id = config.get('pantry_id')
  return pantry_id ~= nil and pantry_id ~= ""
end

---Build the full basket URL from config.
---@return string url Full Pantry basket endpoint URL
function M.get_basket_url()
  local pantry_id = config.get('pantry_id')
  local basket_name = config.get('basket_name') or "todos"
  return string.format("%s/%s/basket/%s", PANTRY_BASE_URL, pantry_id, basket_name)
end

return M
