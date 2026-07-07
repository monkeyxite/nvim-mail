-- Contact completion: blink-cmp provider for khard
---@module 'blink.cmp'

---@class nvim-mail.contacts.Source : blink.cmp.Source
local M = {}

M.config = {
  -- Per-account contact sources
  accounts = {
    -- Each account may include an optional `resolver` block that controls
    -- how ,mC resolves display names to emails (stages 2 + 3).
    -- Accounts without a resolver block use khard only (stage 1).
    --
    -- Example:
    --   work = {
    --     cmd = 'khard',
    --     args = { 'email', '-p', '--remove-first-line', '-A', 'work' },
    --     notmuch_path = 'work',
    --     from = 'Your Name <you@company.com>',
    --     resolver = {
    --       email_pattern = 'first.last',  -- 'first.last'|'flast'|'first_last'|'firstlast'|'last.first'
    --       domain = 'company.com',
    --       normalize_suffixes = true,     -- strip 'K'/'XX'/'I' suffixes before matching
    --       transliterate = true,          -- ä→a, ö→o etc.
    --       ldap = {                       -- omit to disable LDAP stage
    --         cmd = 'ldap_owa_query',
    --         args = {},
    --         account_arg = 'work',
    --         timeout = 10000,
    --       },
    --     },
    --   },
    work = {
      cmd = 'khard',
      args = { 'email', '-p', '--remove-first-line', '-A', 'work' },
    },
    personal = {
      cmd = 'khard',
      args = { 'email', '-p', '--remove-first-line', '-A', 'personal' },
    },
  },
  -- Fallback (no account match)
  cmd = 'khard',
  args = { 'email', '-p', '--remove-first-line' },
  -- From: → account mapping
  from_map = {},  -- e.g. { ['work%.com'] = 'work', ['gmail%.com'] = 'personal' }
  -- Calendar name → account mapping (for calendar MoM/reply resolution)
  calendar_map = {},  -- e.g. { ['Calendar'] = 'work', ['monkeyxite@gmail.com'] = 'personal' }
  -- Account → From address (used to inject From: in calendar reply)
  account_from = {},  -- e.g. { work = 'Jonny Hou <jonny.hou@ericsson.com>', personal = 'Jonny Hou <monkeyxite@gmail.com>' }
  -- DEPRECATED: use resolver.domain on the relevant accounts entry instead.
  -- If set (and not 'example.com'), a legacy resolver is synthesised for
  -- backwards compatibility and a one-time deprecation warning is emitted.
  work_domain = 'example.com',
  -- notmuch address search (searches all indexed mail)
  notmuch = true,
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

--- Parse khard stdout into a list of contact items
---@param output string
---@return {email: string, name: string, type?: string}[]
function M.parse_khard_output(output)
  local results = {}
  for _, line in ipairs(vim.split(output or '', '\n')) do
    local item = M.parse_khard_line(line)
    if item then results[#results + 1] = item end
  end
  return results
end

--- Parse notmuch JSON address output into a list of contact items
---@param output string
---@return {email: string, name: string, type?: string}[]
function M.parse_notmuch_output(output)
  if not output or output == '' then return {} end
  local ok, data = pcall(vim.json.decode, output)
  if not ok or type(data) ~= 'table' then return {} end
  local results = {}
  for _, entry in ipairs(data) do
    if type(entry) == 'table' and entry.address then
      results[#results + 1] = {
        email = entry.address,
        name = entry.name or '',
        type = 'notmuch',
      }
    end
  end
  return results
end

--- Detect account from current buffer's From: header or buffer-local variable
---@return string? account name
function M.detect_account()
  -- Check buffer-local override first (set by calendar picker)
  local buf_acct = vim.b.nvim_mail_account
  if buf_acct then return buf_acct end
  local lines = vim.api.nvim_buf_get_lines(0, 0, 20, false)
  for _, l in ipairs(lines) do
    if l == '' then break end
    local from = l:match('^From:%s*(.+)')
    if from then
      for pattern, acct in pairs(M.config.from_map) do
        if from:find(pattern) then return acct end
      end
    end
  end
  return nil
end

--- Resolve account from calendar name
---@param calendar_name string?
---@return string? account name
function M.account_from_calendar(calendar_name)
  if not calendar_name or calendar_name == '' then return nil end
  for pattern, acct in pairs(M.config.calendar_map) do
    if calendar_name:find(pattern) then return acct end
  end
  return nil
end

--- Async query: runs khard and (optionally) notmuch, merges results, calls cb.
--- Both external processes run concurrently; cb is called once both complete.
---@param query string
---@param cb fun(results: {email: string, name: string, type?: string}[])
function M.query_async(query, cb)
  if query == '' then
    cb({})
    return
  end

  -- Pick account-specific config or fallback
  local acct = M.detect_account()
  local cmd_cfg = (acct and M.config.accounts[acct]) or { cmd = M.config.cmd, args = M.config.args }
  local khard_cmd = { cmd_cfg.cmd or M.config.cmd }
  vim.list_extend(khard_cmd, cmd_cfg.args or M.config.args or {})
  table.insert(khard_cmd, query)

  -- Build notmuch command (if enabled)
  local notmuch_cmd = nil
  if M.config.notmuch then
    local path_filter = ''
    if acct and M.config.accounts[acct] and M.config.accounts[acct].notmuch_path then
      path_filter = ' AND path:' .. M.config.accounts[acct].notmuch_path .. '/**'
    end
    local nm_query = '(from:' .. query .. '* OR to:' .. query .. '*)' .. path_filter
    notmuch_cmd = { 'notmuch', 'address', '--format=json', '--deduplicate=address', nm_query }
  end

  local khard_results = nil
  local notmuch_results = nil
  local pending = notmuch_cmd and 2 or 1

  local function merge_and_deliver()
    pending = pending - 1
    if pending > 0 then return end

    local results = khard_results or {}
    if notmuch_results then
      -- Deduplicate by email
      local seen = {}
      for _, r in ipairs(results) do seen[r.email] = true end
      for _, r in ipairs(notmuch_results) do
        if not seen[r.email] then
          results[#results + 1] = r
          seen[r.email] = true
        end
      end
    end
    cb(results)
  end

  -- Launch khard async. Wrap in pcall so a missing binary doesn't strand the
  -- callback (which would leave `pending` > 0 forever and never call cb).
  local khard_ok = pcall(vim.system, khard_cmd, { text = true }, function(result)
    if result.code ~= 0 then
      khard_results = {}
    else
      khard_results = M.parse_khard_output(result.stdout)
    end
    merge_and_deliver()
  end)
  if not khard_ok then
    khard_results = {}
    merge_and_deliver()
  end

  -- Launch notmuch async (if enabled)
  if notmuch_cmd then
    local nm_ok = pcall(vim.system, notmuch_cmd, { text = true }, function(result)
      if result.code ~= 0 then
        notmuch_results = {}
      else
        notmuch_results = M.parse_notmuch_output(result.stdout)
      end
      merge_and_deliver()
    end)
    if not nm_ok then
      notmuch_results = {}
      merge_and_deliver()
    end
  end
end

--- blink-cmp provider interface

function M.new(opts)
  local self = setmetatable({}, { __index = M })
  if opts then
    M.config = vim.tbl_deep_extend('force', M.config, opts)
  end
  return self
end

function M:enabled()
  return vim.bo.filetype == 'mail'
end

function M:get_completions(ctx, callback)
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
  M.query_async(query, function(results)
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
