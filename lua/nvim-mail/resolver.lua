-- Async contact resolver: wraps resolve.lua pure functions with vim.system I/O.
-- Extracted from init.lua ,mC handler (issues #1 + #8).
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

-- Stage 2: notmuch lookup using Ericsson email pattern + name validation
local function notmuch_lookup(name, cb)
  local candidates = r.ericsson_candidates(name)
  if #candidates == 0 then cb(nil); return end
  local norm = r.normalize_name(name)
  local parts = vim.split(norm, ' ', { trimempty = true })
  local work_domain = require('nvim-mail.contacts').config.work_domain or 'example.com'
  local domain_pat = work_domain:gsub('%.', '%%.')
  local tried, found = 0, false
  local total = #candidates * 2  -- from: + to: per candidate

  local function done(email)
    if found then return end
    found = true
    if email then save_to_khard(parts[1], parts[#parts], email) end
    cb(email)
  end

  for _, cand in ipairs(candidates) do
    for _, cmd in ipairs({
      { 'notmuch', 'address', '--deduplicate=address', 'from:' .. cand .. '@' .. work_domain },
      { 'notmuch', 'address', '--deduplicate=address', 'to:' .. cand .. '@' .. work_domain },
    }) do
      -- Wrap in pcall so a missing notmuch binary doesn't crash the chain.
      local ok = pcall(vim.system, cmd, { text = true }, function(result)
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
      if not ok then
        tried = tried + 1
        if tried >= total and not found then done(nil) end
      end
    end
  end
end

-- 3-stage resolver: khard → notmuch → ldap (with 10-second timeout)
local function resolve_name(name, cb)
  local norm = r.normalize_name(name)
  local parts = vim.split(norm, ' ', { trimempty = true })
  local first_last = #parts >= 2 and (parts[1] .. ' ' .. parts[#parts]) or norm
  local khard_queries = { name }
  if norm ~= name then khard_queries[#khard_queries + 1] = norm end
  if first_last ~= norm then khard_queries[#khard_queries + 1] = first_last end

  local function try_khard(i)
    if i > #khard_queries then
      notmuch_lookup(name, function(email)
        if email then cb(email); return end
        -- Last resort: ldap (slow, DavMail) with 10-second timeout
        vim.schedule(function()
          vim.notify('⏳ LDAP lookup for: ' .. name, vim.log.levels.WARN)
        end)
        local norm2 = r.normalize_name(name)
        local p = vim.split(norm2, ' ', { trimempty = true })
        -- Wrap LDAP in pcall: `ldap_owa_query` may not be installed. Missing
        -- binary must not crash the resolver chain — treat as "no result".
        local ldap_ok = pcall(vim.system,
          { 'ldap_owa_query', p[1] or norm2, p[2] or '', 'work' },
          { text = true, timeout = 10000 },
          function(result)
            if result.code ~= 0 then
              if result.code == 124 then
                vim.schedule(function()
                  vim.notify('⚠ LDAP timeout for: ' .. name, vim.log.levels.WARN)
                end)
              end
              cb(nil); return
            end
            local line = vim.split(result.stdout or '', '\n')[1] or ''
            local email2 = vim.trim(vim.split(line, '\t')[1] or '')
            if email2:find('@') then
              local p2 = vim.split(r.normalize_name(name), ' ', { trimempty = true })
              save_to_khard(p2[1] or name, p2[#p2] or '', email2)
            end
            cb(email2:find('@') and email2 or nil)
          end)
        if not ldap_ok then cb(nil) end
      end)
      return
    end
    -- Wrap khard in pcall so a missing binary doesn't strand try_khard.
    local khard_ok = pcall(vim.system,
      { 'khard', 'email', '--parsable', '--remove-first-line', khard_queries[i] },
      { text = true },
      function(result)
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
    for _, t in ipairs(tasks) do
      if resolved_lines[t.idx] then lines[t.idx] = resolved_lines[t.idx] end
    end
    vim.schedule(function()
      vim.api.nvim_buf_set_lines(bufnr, 0, header_end, false, vim.list_slice(lines, 1, header_end))
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
      resolve_name(name, function(email)
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
