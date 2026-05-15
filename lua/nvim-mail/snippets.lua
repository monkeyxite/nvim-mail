-- Smart snippets: context-aware snippet loading by recipient
local M = {}

M.config = {
  -- domain patterns → context name
  domains = {
    ['work%.com'] = 'work',
    ['ericsson%.com'] = 'work',
    ['personal%.com'] = 'personal',
    ['gmail%.com'] = 'personal',
  },
  -- Snippet definitions per context
  snippets = {
    work = {
      { trigger = 'mty', body = 'Thanks for the update.' },
      { trigger = 'mpfa', body = 'Please find attached.' },
      { trigger = 'mbr', body = 'Best regards,\n${1:John}' },
      { trigger = 'mfyi', body = 'FYI — ${1:context}.' },
      { trigger = 'mack', body = 'Acknowledged, will follow up by ${1:date}.' },
    },
    personal = {
      { trigger = 'mty', body = 'Thanks!' },
      { trigger = 'mch', body = 'Cheers,\n${1:John}' },
      { trigger = 'mlmk', body = 'Let me know what you think.' },
    },
    general = {
      { trigger = 'mty', body = 'Thank you.' },
      { trigger = 'mbr', body = 'Best regards,\n${1:John}' },
      { trigger = 'msig', body = 'Best,\n${1:John}' },
    },
  },
}

--- Detect context from mail headers
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

--- Get snippets for a context
---@param context string
---@return table[]
function M.get_snippets(context)
  return M.config.snippets[context] or M.config.snippets.general
end

--- Load context-aware snippets for buffer (placeholder for future dynamic loading)
--- Currently snippets are loaded via vscode JSON in snips/snippets/mail.json
---@param lines string[]
function M.load_for_buffer(lines)
  -- Context detection available for future per-recipient snippet switching
  -- For now, all mail snippets are loaded statically via luasnip lazy_load
  local _ = M.detect_context(lines)
end

return M
