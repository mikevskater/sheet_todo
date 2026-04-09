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

---Save arbitrary JSON data to Pantry via deep-merge update (POST).
---Pantry's POST endpoint performs a deep merge against the existing basket,
---which means fields omitted from `data` are preserved server-side and arrays
---are merged element-wise by index. That is the wrong semantics when the
---in-memory state has shrunk (e.g. children deleted) — stale entries persist.
---Prefer `M.replace_raw_data` for full-replace semantics.
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

---Replace the entire basket contents with `data` (full overwrite).
---
---Pantry does not expose a PUT/replace verb — POST is a deep merge that
---preserves fields omitted from the body and merges arrays by index. To get
---true replacement semantics we DELETE the basket first, then POST.
---
---Failure modes:
---  * DELETE fails with 400/404: basket does not exist yet (first save after
---    a manual delete, or a fresh Pantry). Treated as success; POST creates.
---  * DELETE succeeds, POST fails: basket is now empty server-side. The
---    caller's in-memory state is untouched and still dirty, so the next
---    save attempt will recreate the basket from that state. Surface the
---    error loudly so the user knows not to close Neovim.
---
---@param data table Data to encode as JSON and save
---@param callback fun(success: boolean, err: string?)
function M.replace_raw_data(data, callback)
  if not url.is_configured() then
    callback(false, "Pantry ID not configured")
    return
  end

  local basket_url = url.get_basket_url()
  local body = vim.json.encode(data)

  local function do_post()
    http.post(basket_url, body, {
      ["Content-Type"] = "application/json"
    }, function(response, err)
      if err then
        callback(false, "Save failed after delete (basket is now empty, retry save): " .. err)
        return
      end
      if response.status ~= 200 then
        callback(false, "Save failed after delete (basket is now empty, retry save): HTTP "
          .. response.status .. ": " .. (response.body or "Unknown error"))
        return
      end
      callback(true)
    end)
  end

  http.delete(basket_url, {}, function(response, err)
    if err then
      -- Network-level failure on DELETE. Don't proceed — basket is untouched.
      callback(false, "Failed to clear basket before save: " .. err)
      return
    end
    -- Pantry returns 400 when the basket does not exist. Treat 400/404/200
    -- as "basket is now empty, safe to POST".
    if response.status == 200 or response.status == 400 or response.status == 404 then
      do_post()
      return
    end
    callback(false, "Failed to clear basket before save: HTTP "
      .. response.status .. ": " .. (response.body or "Unknown error"))
  end)
end

return M
