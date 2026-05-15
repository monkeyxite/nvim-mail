-- Contact completion: blink-cmp provider for khard
local M = {}

M.config = {
  cmd = 'khard',
  args = { 'email', '-p', '--remove-first-line' },
}

--- Check if a line is an address header (To/Cc/Bcc)
---@param line string
---@return boolean
function M.is_header_line(line)
  return line:match('^[Tt]o:') ~= nil
    or line:match('^[Cc]c:') ~= nil
    or line:match('^[Bb]cc:') ~= nil
end

--- Extract the query string (partial input after last comma or colon)
---@param line string
---@return string
function M.extract_query(line)
  local after_comma = line:match(',([^,]*)$')
  if after_comma then return vim.trim(after_comma) end
  local after_colon = line:match('^%a+:%s*(.*)$')
  return after_colon and vim.trim(after_colon) or ''
end

--- Parse a khard output line (tab-separated: email\tname\ttype)
---@param line string
---@return {email: string, name: string, type?: string}?
function M.parse_khard_line(line)
  if not line or line == '' then return nil end
  local parts = vim.split(line, '\t')
  if #parts < 2 then return nil end
  return {
    email = parts[1],
    name = parts[2],
    type = parts[3],
  }
end

--- Query khard for contacts matching a string
---@param query string
---@return {email: string, name: string, type?: string}[]
function M.query(query)
  if query == '' then return {} end
  local cmd = { M.config.cmd }
  vim.list_extend(cmd, M.config.args)
  table.insert(cmd, query)
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then return {} end
  local results = {}
  for _, line in ipairs(vim.split(output, '\n')) do
    local item = M.parse_khard_line(line)
    if item then results[#results + 1] = item end
  end
  return results
end

--- Blink-cmp provider module interface
M.provider = {}

function M.provider.new()
  return setmetatable({}, { __index = M.provider })
end

function M.provider:enabled()
  return vim.bo.filetype == 'mail'
end

function M.provider:get_completions(ctx, callback)
  local line = ctx.line
  if not M.is_header_line(line) then
    callback({ items = {}, is_incomplete_forward = false })
    return
  end
  local query = M.extract_query(line)
  if #query < 2 then
    callback({ items = {}, is_incomplete_forward = true })
    return
  end
  vim.schedule(function()
    local results = M.query(query)
    local items = {}
    for _, r in ipairs(results) do
      items[#items + 1] = {
        label = string.format('%s <%s>', r.name, r.email),
        insertText = string.format('%s <%s>', r.name, r.email),
        detail = r.type or '',
        kind = 12,
      }
    end
    callback({ items = items, is_incomplete_forward = false })
  end)
end

return M
