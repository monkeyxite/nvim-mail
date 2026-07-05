-- Smart snippets: context-aware snippet loading by recipient
local M = {}

M.config = {
  -- Your display name for signature snippets (set in lazy opts)
  name = 'Your Name',
  -- domain patterns → context name (set in lazy opts)
  domains = {},
  -- Snippet definitions per context (set in lazy opts, or use defaults)
  snippets = {
    work = {
      { trigger = 'mty',  body = 'Thanks for the update.' },
      { trigger = 'mpfa', body = 'Please find attached.' },
      { trigger = 'mbr',  body = 'Best regards,\n${1:name}' },
      { trigger = 'mfyi', body = 'FYI — ${1:context}.' },
      { trigger = 'mack', body = 'Acknowledged, will follow up by ${1:date}.' },
    },
    personal = {
      { trigger = 'mty',  body = 'Thanks!' },
      { trigger = 'mch',  body = 'Cheers,\n${1:name}' },
      { trigger = 'mlmk', body = 'Let me know what you think.' },
    },
    general = {
      { trigger = 'mty',  body = 'Thank you.' },
      { trigger = 'mbr',  body = 'Best regards,\n${1:name}' },
      { trigger = 'msig', body = 'Best,\n${1:name}' },
    },
  },
}

--- Detect context from mail headers using configured domain patterns.
---@param lines string[]
---@return string context name
function M.detect_context(lines)
  for _, l in ipairs(lines) do
    if l == '' then break end
    local addr = l:match('^[Tt]o:%s*(.+)') or l:match('^[Cc]c:%s*(.+)')
    if addr then
      for pattern, ctx in pairs(M.config.domains) do
        if addr:find(pattern) then return ctx end
      end
    end
  end
  return 'general'
end

--- Get snippets for a context, with name substituted.
---@param context string
---@return table[]
function M.get_snippets(context)
  local snips = M.config.snippets[context] or M.config.snippets.general
  local name = M.config.name
  local result = {}
  for _, s in ipairs(snips) do
    result[#result + 1] = {
      trigger = s.trigger,
      body = s.body:gsub('%${1:name}', '${1:' .. name .. '}'),
    }
  end
  return result
end

---@param lines string[]
function M.load_for_buffer(lines)
  local ctx = M.detect_context(lines)
  local ok, ls = pcall(require, 'luasnip')
  if not ok then return end
  local snips = M.get_snippets(ctx)
  local ls_snips = {}
  for _, s in ipairs(snips) do
    ls_snips[#ls_snips + 1] = ls.parser.parse_snippet(s.trigger, s.body)
  end
  ls.add_snippets('mail', ls_snips, { key = 'nvim-mail-' .. ctx })
end

return M
