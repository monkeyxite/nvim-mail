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
      { trigger = 'ty', body = 'Thanks for the update.' },
      { trigger = 'pfa', body = 'Please find attached.' },
      { trigger = 'br', body = 'Best regards,\n${1:John}' },
      { trigger = 'fyi', body = 'FYI — ${1:context}.' },
      { trigger = 'ack', body = 'Acknowledged, will follow up by ${1:date}.' },
    },
    personal = {
      { trigger = 'ty', body = 'Thanks!' },
      { trigger = 'ch', body = 'Cheers,\n${1:John}' },
      { trigger = 'lmk', body = 'Let me know what you think.' },
    },
    general = {
      { trigger = 'ty', body = 'Thank you.' },
      { trigger = 'br', body = 'Best regards,\n${1:John}' },
      { trigger = 'sig', body = 'Best,\n${1:John}' },
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

--- Register snippets with luasnip for current buffer context
---@param lines string[]
function M.load_for_buffer(lines)
  local ok, ls = pcall(require, 'luasnip')
  if not ok then return end
  local s = ls.snippet
  local t = ls.text_node
  local i = ls.insert_node

  local ctx = M.detect_context(lines)
  local snips = M.get_snippets(ctx)

  local ls_snips = {}
  for _, snip in ipairs(snips) do
    local nodes = {}
    local idx = 1
    -- Parse ${N:placeholder} patterns into insert nodes
    local remaining = snip.body
    while true do
      local pre, num, placeholder, post = remaining:match('^(.-)%${(%d+):([^}]*)}(.*)$')
      if not pre then
        -- No more placeholders, add remaining as text
        if remaining ~= '' then
          nodes[#nodes + 1] = t(vim.split(remaining, '\n'))
        end
        break
      end
      if pre ~= '' then
        nodes[#nodes + 1] = t(vim.split(pre, '\n'))
      end
      nodes[#nodes + 1] = i(tonumber(num), placeholder)
      remaining = post
    end
    if #nodes > 0 then
      ls_snips[#ls_snips + 1] = s(snip.trigger, nodes)
    end
  end

  ls.add_snippets('mail', ls_snips, { key = 'nvim-mail-' .. ctx })
end

return M
