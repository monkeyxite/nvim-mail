-- Async contact resolver: wraps resolve.lua pure functions with vim.system I/O.
-- Extracted from init.lua ,mC handler (issues #1 + #8).
-- Per-account resolver pipeline added in issue #14.
local M = {}
local r = require('nvim-mail.resolve')

-- Auto-save a resolved contact to khard
local function save_to_khard(first, last, email)
  local vcard = table.concat({
    'BEGIN:VCARD', 'VERSION:3.0',
    'FN:' .. first .. ' ' .. last,
    'N:' .. last .. ';' .. first .. ';;;',
    'EMAIL;TYPE=WORK:' .. email,
    'END:VCARD',
  }, '\n')
  vim.system({ 'khard', 'add', '--input-format=vcard' }, { text = true, stdin = vcard })
end

--- Return the resolver config for an account, plus the account config table.
--- Migration path: if the account has no resolver block but contacts.work_domain
--- is set, synthesise a legacy resolver with a one-time deprecation notice.
---@param account_name string?
---@return table? resolver_cfg, table? acct_cfg
local function get_resolver_config(account_name)
  local contacts = require('nvim-mail.contacts')
  local accounts = contacts.config.accounts or {}
  local acct_cfg = account_name and accounts[account_name]

  -- Happy path: per-account resolver block present
  if acct_cfg and acct_cfg.resolver then
    return acct_cfg.resolver, acct_cfg
  end

  -- Legacy migration: top-level work_domain → synthesise implicit resolver
  local work_domain = contacts.config.work_domain
  if work_domain and work_domain ~= 'example.com' then
    if not contacts._work_domain_warned then
      contacts._work_domain_warned = true
      vim.schedule(function()
        vim.notify(
          '[nvim-mail] contacts.work_domain is deprecated.\n'
          .. 'Move to a resolver block on the relevant contacts.accounts entry.\n'
          .. 'See :help nvim-mail-resolver for the new config shape.',
          vim.log.levels.WARN
        )
      end)
    end
    return {
      email_pattern    = 'first.last',
      domain           = work_domain,
      normalize_suffixes = true,
      transliterate    = true,
      ldap = {
        cmd         = 'ldap_owa_query',
        args        = {},
        account_arg = 'work',
        timeout     = 10000,
      },
    }, acct_cfg
  end

  return nil, acct_cfg
end

--- Stage 3: LDAP fallback.
---@param name string
---@param ldap_cfg table  { cmd, args, account_arg?, timeout? }
---@param cb fun(email: string?)
local function ldap_lookup(name, ldap_cfg, cb)
  vim.schedule(function()
    vim.notify('⏳ LDAP lookup for: ' .. name, vim.log.levels.WARN)
  end)
  local norm = r.normalize_name(name)
  local p = vim.split(norm, ' ', { trimempty = true })
  local cmd = { ldap_cfg.cmd }
  vim.list_extend(cmd, ldap_cfg.args or {})
  cmd[#cmd + 1] = p[1] or norm
  cmd[#cmd + 1] = p[2] or ''
  if ldap_cfg.account_arg then
    cmd[#cmd + 1] = ldap_cfg.account_arg
  end
  local ldap_ok = pcall(vim.system, cmd, { text = true, timeout = ldap_cfg.timeout or 10000 }, function(result)
    if result.code ~= 0 then
      if result.code == 124 then
        vim.schedule(function()
          vim.notify('⚠ LDAP timeout for: ' .. name, vim.log.levels.WARN)
        end)
      end
      cb(nil); return
    end
    local line = vim.split(result.stdout or '', '\n')[1] or ''
    local email = vim.trim(vim.split(line, '\t')[1] or '')
    if email:find('@') then
      local p2 = vim.split(r.normalize_name(name), ' ', { trimempty = true })
      save_to_khard(p2[1] or name, p2[#p2] or '', email)
    end
    cb(email:find('@') and email or nil)
  end)
  if not ldap_ok then cb(nil) end
end

--- Stage 2: notmuch lookup using the account's resolver config.
---@param name string
---@param resolver_cfg table  { email_pattern, domain, transliterate?, normalize_suffixes? }
---@param acct_cfg table?     account config (used for notmuch_path scoping)
---@param cb fun(email: string?)
local function notmuch_lookup(name, resolver_cfg, acct_cfg, cb)
  local pattern = resolver_cfg.email_pattern or 'first.last'
  local domain  = resolver_cfg.domain
  if not domain then cb(nil); return end

  local build_opts = {
    transliterate      = resolver_cfg.transliterate,
    normalize_suffixes = resolver_cfg.normalize_suffixes,
  }
  local candidates = r.build_candidates(name, pattern, build_opts)
  if #candidates == 0 then cb(nil); return end

  local norm = build_opts.normalize_suffixes and r.normalize_name(name) or vim.trim(name)
  local parts = vim.split(norm, ' ', { trimempty = true })

  local domain_pat = domain:gsub('%.', '%%.')
  local path_filter = ''
  if acct_cfg and acct_cfg.notmuch_path then
    path_filter = ' AND path:' .. acct_cfg.notmuch_path .. '/**'
  end

  local tried, found = 0, false
  local total = #candidates * 2  -- from: + to: per candidate

  local function done(email)
    if found then return end
    found = true
    if email then save_to_khard(parts[1], parts[#parts], email) end
    cb(email)
  end

  for _, cand in ipairs(candidates) do
    for _, dir in ipairs({ 'from:', 'to:' }) do
      local query = dir .. cand .. '@' .. domain .. path_filter
      local nm_ok = pcall(vim.system,
        { 'notmuch', 'address', '--deduplicate=address', query },
        { text = true },
        function(result)
          tried = tried + 1
          if found then return end
          for _, line in ipairs(vim.split(result.stdout or '', '\n')) do
            local dname, email = line:match('^(.-)%s*<([^>]+@' .. domain_pat .. ')>')
            if email and dname and r.validate_notmuch_match(dname, name) then
              done(email); return
            end
          end
          if tried >= total then done(nil) end
        end)
      if not nm_ok then
        tried = tried + 1
        if tried >= total and not found then done(nil) end
      end
    end
  end
end

--- 3-stage resolver for a single name, account-aware.
---@param name string
---@param account_name string?
---@param cb fun(email: string?)
local function resolve_name(name, account_name, cb)
  local resolver_cfg, acct_cfg = get_resolver_config(account_name)

  -- Build khard command from account config (falls back to plain khard)
  local khard_base
  if acct_cfg and acct_cfg.cmd then
    khard_base = { acct_cfg.cmd }
    vim.list_extend(khard_base, acct_cfg.args or { 'email', '-p', '--remove-first-line' })
  else
    khard_base = { 'khard', 'email', '--parsable', '--remove-first-line' }
  end

  -- Prepare khard query variants: original → suffix-stripped → first+last
  local norm = r.normalize_name(name)
  local parts = vim.split(norm, ' ', { trimempty = true })
  local first_last = #parts >= 2 and (parts[1] .. ' ' .. parts[#parts]) or norm
  local khard_queries = { name }
  if norm ~= name then khard_queries[#khard_queries + 1] = norm end
  if first_last ~= norm then khard_queries[#khard_queries + 1] = first_last end

  local function try_khard(i)
    if i > #khard_queries then
      local function try_ldap()
        if resolver_cfg and resolver_cfg.ldap then
          ldap_lookup(name, resolver_cfg.ldap, cb)
        else
          cb(nil)
        end
      end
      -- Stage 2: notmuch (only if resolver has email_pattern + domain)
      if resolver_cfg and resolver_cfg.email_pattern and resolver_cfg.domain then
        notmuch_lookup(name, resolver_cfg, acct_cfg, function(email)
          if email then cb(email) else try_ldap() end
        end)
      else
        -- Stage 3: LDAP fires whether or not notmuch is configured.
        try_ldap()
      end
      return
    end
    local cmd = {}
    vim.list_extend(cmd, khard_base)
    cmd[#cmd + 1] = khard_queries[i]
    local khard_ok = pcall(vim.system, cmd, { text = true }, function(result)
      local email = r.parse_khard(result.stdout)
      if email then cb(email) else try_khard(i + 1) end
    end)
    if not khard_ok then try_khard(i + 1) end
  end
  try_khard(1)
end

--- Resolve all unresolved contacts in the mail headers of buffer `bufnr`.
function M.resolve_buffer(bufnr)
  local contacts = require('nvim-mail.contacts')
  local account_name = contacts.detect_account()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local unresolved = {}
  local header_end = 0

  -- Find end of header block
  for i, l in ipairs(lines) do
    if l == '' then header_end = i - 1; break end
  end

  -- Collect To/Cc/Bcc entries that have no @ (unresolved display names)
  local tasks = {}  -- { idx, line, entries[], names[] }
  for i = 1, header_end do
    local line = lines[i]
    if contacts.is_header_line(line) then
      local after = line:match('^%a+:%s*(.*)')
      if after and after ~= '' then
        local entries = vim.split(after, ',', { trimempty = true })
        local names = {}
        for _, e in ipairs(entries) do
          e = vim.trim(e)
          if not e:find('@') then names[#names + 1] = e end
        end
        if #names > 0 then
          tasks[#tasks + 1] = { idx = i, line = line, entries = entries, names = names }
        end
      end
    end
  end

  local pending = 0
  for _, t in ipairs(tasks) do pending = pending + #t.names end
  if pending == 0 then
    vim.notify('All addresses already resolved', vim.log.levels.INFO)
    return
  end

  local resolved_lines = {}
  local done_count = 0
  local total = #tasks

  local function finish()
    done_count = done_count + 1
    if done_count < total then return end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      -- Refetch current buffer state to avoid clobbering concurrent user edits.
      local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local current_header_end = #current_lines
      for i, l in ipairs(current_lines) do
        if l == '' then current_header_end = i - 1; break end
      end
      for _, t in ipairs(tasks) do
        if resolved_lines[t.idx] and t.idx <= current_header_end and current_lines[t.idx] then
          -- Only replace if the current line still looks like a header field.
          if current_lines[t.idx]:match('^%a+:') then
            current_lines[t.idx] = resolved_lines[t.idx]
          end
        end
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, current_header_end, false, vim.list_slice(current_lines, 1, current_header_end))
      if #unresolved > 0 then
        vim.notify('⚠ No email found for: ' .. table.concat(unresolved, ', '), vim.log.levels.WARN)
      else
        vim.notify('✓ All contacts resolved', vim.log.levels.INFO)
      end
    end)
  end

  for _, t in ipairs(tasks) do
    local name_results = {}
    local name_pending = #t.names
    for _, name in ipairs(t.names) do
      resolve_name(name, account_name, function(email)
        if email and email ~= '' then
          name_results[name] = string.format('%s <%s>', name, email)
        else
          name_results[name] = nil
          unresolved[#unresolved + 1] = name
        end
        name_pending = name_pending - 1
        if name_pending == 0 then
          -- Rebuild the header line with resolved addresses
          local new_entries = {}
          for _, e in ipairs(t.entries) do
            local trimmed = vim.trim(e)
            new_entries[#new_entries + 1] = name_results[trimmed] or trimmed
          end
          local prefix = t.line:match('^(%a+:%s*)')
          resolved_lines[t.idx] = prefix .. table.concat(new_entries, ', ')
          finish()
        end
      end)
    end
  end
end

return M
