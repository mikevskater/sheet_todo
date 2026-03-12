---@class nvim-todo.storage.pantry.client
local M = {}

local http = require('nvim-todo.storage.http')
local url = require('nvim-todo.storage.pantry.url')

---Fetch raw parsed JSON from Pantry without format processing.
---@param callback fun(success: boolean, data: table?, err: string?)
function M.get_raw_data(callback)
  if not url.is_configured() then
    callback(false, nil, "Pantry ID not configured")
    return
  end

  local basket_url = url.get_basket_url()

  http.get(basket_url, {}, function(response, err)
    if err then
      callback(false, nil, "Failed to fetch content: " .. err)
      return
    end

    -- Pantry returns 400 when basket doesn't exist (not 404)
    if response.status == 400 or response.status == 404 then
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

---Save arbitrary JSON data to Pantry.
---@param data table Data to encode as JSON and save
---@param callback fun(success: boolean, err: string?)
function M.save_raw_data(data, callback)
  if not url.is_configured() then
    callback(false, "Pantry ID not configured")
    return
  end

  local basket_url = url.get_basket_url()
  local body = vim.json.encode(data)

  http.post(basket_url, body, {
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
