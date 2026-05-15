-- Attachment awareness: detect "attach" mentions without actual attachments
local M = {}

-- Patterns that indicate user intends to attach something
M.mention_patterns = {
  '[Aa]ttach',
  '[Ee]nclosed',
  'PFA',
  'see the file',
  'find the file',
}

-- Patterns that indicate an actual attachment exists
M.attachment_patterns = {
  '<#part',       -- neomutt MIME attachment marker
  '!%[',         -- markdown image
  'Content%-Disposition: attachment',
}

--- Parse buffer lines into headers and body
---@param lines string[]
---@return string[] headers, string[] body, integer body_start (1-indexed)
function M.parse_mail(lines)
  local headers, body = {}, {}
  local body_start = 1
  for i, l in ipairs(lines) do
    if l == '' then
      body_start = i + 1
      body = vim and vim.list_slice and vim.list_slice(lines, body_start) or { unpack(lines, body_start) }
      break
    end
    headers[#headers + 1] = l
  end
  return headers, body, body_start
end

--- Check if body text mentions an attachment
---@param body string[] lines of the body
---@return boolean
function M.has_attach_mention(body)
  local text = table.concat(body, ' ')
  for _, pat in ipairs(M.mention_patterns) do
    if text:find(pat) then return true end
  end
  return false
end

--- Check if body has an actual attachment marker
---@param body string[] lines of the body
---@return boolean
function M.has_attachment(body)
  local text = table.concat(body, '\n')
  for _, pat in ipairs(M.attachment_patterns) do
    if text:find(pat) then return true end
  end
  return false
end

--- Main check: returns true if attachment is mentioned but missing
---@param lines string[]
---@return boolean missing, string? mention_match
function M.check(lines)
  local _, body = M.parse_mail(lines)
  if not M.has_attach_mention(body) then return false, nil end
  if M.has_attachment(body) then return false, nil end
  -- Find which pattern matched for the warning message
  local text = table.concat(body, ' ')
  for _, pat in ipairs(M.mention_patterns) do
    local match = text:match(pat)
    if match then return true, match end
  end
  return true, nil
end

return M
