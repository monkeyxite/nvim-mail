-- Pure functions for contact name resolution, exposed for testing
local M = {}

local _tr = {
  ['à']='a',['á']='a',['â']='a',['ã']='a',['ä']='a',['å']='a',
  ['æ']='ae',['ç']='c',['è']='e',['é']='e',['ê']='e',['ë']='e',
  ['ì']='i',['í']='i',['î']='i',['ï']='i',['ñ']='n',
  ['ò']='o',['ó']='o',['ô']='o',['õ']='o',['ö']='o',['ø']='o',
  ['ù']='u',['ú']='u',['û']='u',['ü']='u',['ý']='y',
}

--- Transliterate non-ASCII characters for Ericsson email pattern matching.
function M.tr(s)
  return (s:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c)
    return _tr[c] or c
  end))
end

--- Strip Ericsson-style suffixes: "Kevin Li K" → "Kevin Li", "Magnus Lundgren X" → "Magnus Lundgren"
function M.normalize_name(n)
  return vim.trim(n:gsub('%s+[A-Z][A-Z]?$', ''):gsub('%s+I+$', ''))
end

--- Build Ericsson email candidates from a name (first.last, first.mid.last variants).
--- Returns list of candidate email prefixes (without @ericsson.com).
function M.ericsson_candidates(name)
  local norm = M.normalize_name(name)
  local parts = vim.split(norm, ' ', { trimempty = true })
  if #parts < 2 then return {} end
  local first = M.tr(parts[1]:lower())
  local last  = M.tr(parts[#parts]:lower())
  local candidates = {}
  if #parts == 3 then
    local mid = M.tr(parts[2]:lower())
    candidates[#candidates+1] = first..'.'..mid..'.'..last
    candidates[#candidates+1] = first..'.'..last..'.'..mid
  end
  candidates[#candidates+1] = first..'.'..last
  return candidates
end

--- Validate that a notmuch display name contains both first and longest-surname words.
function M.validate_notmuch_match(display_name, name)
  local norm = M.normalize_name(name)
  local parts = vim.split(norm, ' ', { trimempty = true })
  if #parts < 2 then return false end
  local first = M.tr(parts[1]:lower())
  -- Use longest non-first part as check_last
  local check_last = ''
  for _, p in ipairs(parts) do
    local tp = M.tr(p:lower())
    if tp ~= first and #tp > #check_last then check_last = tp end
  end
  local dtr = M.tr(display_name:lower())
  local dwords = vim.split(dtr, '%s+')
  local has_first = vim.tbl_contains(dwords, first)
  local has_last  = #check_last > 1 and vim.tbl_contains(dwords, check_last)
  return has_first and has_last
end

--- Parse first email from khard --parsable output.
function M.parse_khard(stdout)
  local line = vim.split(stdout or '', "\n")[1] or ''
  local email = vim.split(line, "\t")[1] or ''
  email = vim.trim(email)
  return email:find('@') and email or nil
end

return M
