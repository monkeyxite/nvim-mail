-- Pure address-manipulation helpers for building reply-all drafts.
local M = {}

--- Extract bare email address from a "Name <email>" or "email" string.
-- Returns the address in lower-case for comparison.
local function extract_email(addr)
  local angle = addr:match('<(.-)>')
  return (angle or addr):gsub('%s+', ''):lower()
end

--- Split a comma-separated address list into a table of trimmed entries.
local function split_addresses(addr_str)
  local result = {}
  for part in (addr_str .. ','):gmatch('([^,]+),') do
    local trimmed = part:match('^%s*(.-)%s*$')
    if trimmed ~= '' then
      result[#result + 1] = trimmed
    end
  end
  return result
end

--- Build a Cc address string for a reply-all draft.
-- Merges orig_to and orig_cc, removes any address matching my_from (self),
-- deduplicates, and returns a comma-separated string (or '' if empty).
function M.build_reply_all_cc(orig_to, orig_cc, my_from)
  local self_email = extract_email(my_from or '')
  local seen = {}
  local result = {}

  local function add(addr)
    local key = extract_email(addr)
    if key == '' then return end
    if key == self_email then return end
    if seen[key] then return end
    seen[key] = true
    result[#result + 1] = addr
  end

  for _, a in ipairs(split_addresses(orig_to or '')) do add(a) end
  for _, a in ipairs(split_addresses(orig_cc or '')) do add(a) end

  return table.concat(result, ', ')
end

return M
