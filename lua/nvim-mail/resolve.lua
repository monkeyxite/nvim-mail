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

--- Strip name suffixes: "Kevin Li K" → "Kevin Li", "Magnus Lundgren X" → "Magnus Lundgren".
--- Strips single/double uppercase word suffixes and Roman-numeral suffixes.
function M.normalize_name(n)
  return vim.trim(n:gsub('%s+[A-Z][A-Z]?$', ''):gsub('%s+I+$', ''))
end

--- Build email-prefix candidates from a display name.
--- @param name string  Display name, e.g. "Anders Björk" or "Kevin K Li"
--- @param pattern string  One of: 'first.last' | 'flast' | 'first_last' | 'firstlast' | 'last.first'
--- @param opts table?  { transliterate: bool, normalize_suffixes: bool }
---   transliterate=true  applies ä→a, ö→o etc. before pattern building
---   normalize_suffixes=true  strips single/double uppercase word suffixes first
---
--- Multi-word names: parts[1] is first name, parts[#parts] is last name, any
--- middle parts are treated as middle names.  For the 'first.last' pattern, a
--- three-part name generates three variants (first.mid.last, first.last.mid,
--- first.last) to cover common corporate conventions.  Other patterns use only
--- first and last to avoid combinatorial noise.
function M.build_candidates(name, pattern, opts)
  opts = opts or {}
  local processed = opts.normalize_suffixes and M.normalize_name(name) or vim.trim(name)
  local parts = vim.split(processed, ' ', { trimempty = true })
  if #parts < 2 then return {} end
  local xfm = opts.transliterate and M.tr or function(s) return s end
  local first = xfm(vim.fn.tolower(parts[1]))
  local last  = xfm(vim.fn.tolower(parts[#parts]))
  local candidates = {}
  if pattern == 'first.last' then
    if #parts == 3 then
      local mid = xfm(vim.fn.tolower(parts[2]))
      candidates[#candidates+1] = first..'.'..mid..'.'..last
      candidates[#candidates+1] = first..'.'..last..'.'..mid
    end
    candidates[#candidates+1] = first..'.'..last
  elseif pattern == 'flast' then
    candidates[#candidates+1] = first:sub(1, 1)..last
  elseif pattern == 'first_last' then
    candidates[#candidates+1] = first..'_'..last
  elseif pattern == 'firstlast' then
    candidates[#candidates+1] = first..last
  elseif pattern == 'last.first' then
    candidates[#candidates+1] = last..'.'..first
  end
  return candidates
end

--- Build Ericsson-style candidates (first.last with transliteration and suffix stripping).
--- Kept for backwards compatibility; delegates to build_candidates.
function M.ericsson_candidates(name)
  return M.build_candidates(name, 'first.last', { transliterate = true, normalize_suffixes = true })
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
