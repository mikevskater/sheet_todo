-- Pantry API implementation for cloud storage
local http = require('sheet_todo.http')
local config = require('sheet_todo.config')

local M = {}

-- Base64 encode content to avoid JSON escape sequence issues
function M.encode_content(content)
  if not content or content == "" then
    return ""
  end
  return vim.base64.encode(content)
end

-- Base64 decode content back to original string
function M.decode_content(encoded)
  if not encoded or encoded == "" then
    return ""
  end
  -- Strip whitespace that may be injected by JSON formatting or Pantry storage
  encoded = encoded:gsub('%s', '')
  local ok, decoded = pcall(vim.base64.decode, encoded)
  if not ok then
    -- If decoding fails, return raw string (handles pre-encoding data)
    return encoded
  end
  return decoded
end

-- Pantry API endpoint
local PANTRY_BASE_URL = "https://getpantry.cloud/apiv1/pantry"

-- Check if Pantry is configured
function M.is_configured()
  local pantry_id = config.get('pantry_id')
  return pantry_id ~= nil and pantry_id ~= ""
end

-- Get the basket URL
local function get_basket_url()
  local pantry_id = config.get('pantry_id')
  local basket_name = config.get('basket_name') or "todos"
  return string.format("%s/%s/basket/%s", PANTRY_BASE_URL, pantry_id, basket_name)
end

-- ============================================================================
-- RAW DATA API (used by multi-panel mode / group_manager)
-- ============================================================================

---Fetch raw parsed JSON from Pantry without format processing.
---@param callback fun(success: boolean, data: table?, err: string?)
function M.get_raw_data(callback)
  if not M.is_configured() then
    callback(false, nil, "Pantry ID not configured")
    return
  end

  local url = get_basket_url()

  http.get(url, {}, function(response, err)
    if err then
      callback(false, nil, "Failed to fetch content: " .. err)
      return
    end

    -- Pantry returns 400 when basket doesn't exist (not 404)
    if response.status == 400 or response.status == 404 then
      -- Basket doesn't exist yet, return nil data (first time)
      callback(true, nil)
      return
    end

    if response.status ~= 200 then
      callback(false, nil, "HTTP " .. response.status .. ": " .. (response.body or "Unknown error"))
      return
    end

    local ok, data = pcall(vim.json.decode, response.body)
    if not ok then
      callback(false, nil, "Failed to parse response: " .. tostring(data))
      return
    end

    callback(true, data)
  end)
end

---Save arbitrary JSON data to Pantry (used by multi-panel mode / group_manager).
---@param data table Data to encode as JSON and save
---@param callback fun(success: boolean, err: string?)
function M.save_raw_data(data, callback)
  if not M.is_configured() then
    callback(false, "Pantry ID not configured")
    return
  end

  local url = get_basket_url()
  local body = vim.json.encode(data)

  http.post(url, body, {
    ["Content-Type"] = "application/json"
  }, function(response, err)
    if err then
      callback(false, "Failed to save content: " .. err)
      return
    end

    if response.status ~= 200 then
      callback(false, "HTTP " .. response.status .. ": " .. (response.body or "Unknown error"))
      return
    end

    callback(true)
  end)
end

return M
