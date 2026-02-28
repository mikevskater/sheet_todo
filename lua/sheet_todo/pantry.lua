-- Pantry API implementation for cloud storage
local http = require('sheet_todo.http')
local config = require('sheet_todo.config')

local M = {}

-- Base64 encode content to avoid JSON escape sequence issues
local function encode_content(content)
  if not content or content == "" then
    return ""
  end
  return vim.base64.encode(content)
end

-- Base64 decode content back to original string
local function decode_content(encoded)
  if not encoded or encoded == "" then
    return ""
  end
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

-- Fetch notepad content from Pantry
function M.get_content(callback)
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
      -- Basket doesn't exist yet, return empty content
      callback(true, { content = "", cursor_pos = { line = 1, col = 0 } })
      return
    end
    
    if response.status ~= 200 then
      callback({ error = "HTTP " .. response.status .. ": " .. (response.body or "Unknown error") }, nil)
      return
    end
    
    -- Parse JSON response
    local ok, data = pcall(vim.json.decode, response.body)
    if not ok then
      callback(false, nil, "Failed to parse response: " .. tostring(data))
      return
    end
    
    -- Ensure content exists and decode from base64
    if not data.content then
      data.content = ""
    else
      data.content = decode_content(data.content)
    end
    if not data.cursor_pos then
      data.cursor_pos = { line = 1, col = 0 }
    end
    
    callback(true, data)
  end)
end

-- Save notepad content to Pantry
function M.save_content(content, cursor_pos, callback)
  if not M.is_configured() then
    callback(false, "Pantry ID not configured")
    return
  end

  local url = get_basket_url()
  
  local payload = {
    content = encode_content(content),
    cursor_pos = cursor_pos or { line = 1, col = 0 },
    last_modified = os.time()
  }
  
  local body = vim.json.encode(payload)
  
  -- Use POST to create/update the basket (Pantry uses POST for both)
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
