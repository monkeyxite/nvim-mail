-- Telescope contact picker: search notmuch addresses, insert or create khard contacts
-- Usage: require('telescope').extensions.nvim_mail.contacts()
local M = {}

local function contacts_picker(opts)
  opts = opts or {}

  local function parse_entries(stdout)
    local entries, seen = {}, {}
    for _, line in ipairs(vim.split(stdout or '', '\n')) do
      if line ~= '' then
        local name, email = line:match('^(.-)%s*<([^>]+)>')
        if not email then email = vim.trim(line); name = '' end
        email = vim.trim(email or '')
        if email:find('@') and not seen[email] then
          seen[email] = true
          entries[#entries + 1] = { email = email, name = vim.trim(name or '') }
        end
      end
    end
    return entries
  end

  local function open(entries)
    local pickers      = require('telescope.pickers')
    local finders      = require('telescope.finders')
    local conf         = require('telescope.config').values
    local actions      = require('telescope.actions')
    local action_state = require('telescope.actions.state')
    local previewers   = require('telescope.previewers')

    pickers.new(opts, {
      prompt_title = '  Contacts (' .. #entries .. ')',
      finder = finders.new_table({
        results = entries,
        entry_maker = function(r)
          local display = r.name ~= '' and string.format('%s <%s>', r.name, r.email) or r.email
          return {
            value   = { email = r.email, name = r.name, type = 'notmuch' },
            display = display,
            ordinal = r.name .. ' ' .. r.email,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = 'Contact Details',
        define_preview = function(self, entry)
          if not entry or not entry.value then return end
          local r = entry.value
          local lines = { '# ' .. (r.name or ''), '', 'Email: ' .. (r.email or ''), '' }
          local res = vim.system({ 'khard', 'show', r.name or '' }, { text = true }):wait()
          if res.code == 0 and res.stdout ~= '' then
            vim.list_extend(lines, vim.split(res.stdout, '\n'))
          end
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        -- Enter: insert "Name <email>" at cursor
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if not entry then return end
          local r = entry.value
          vim.api.nvim_put({ string.format('%s <%s>', r.name, r.email) }, 'c', true, true)
        end)

        -- C-y: yank email
        map({ 'i', 'n' }, '<C-y>', function()
          local entry = action_state.get_selected_entry()
          if not entry then return end
          vim.fn.setreg('+', entry.value.email or '')
          vim.notify('Copied: ' .. (entry.value.email or ''), vim.log.levels.INFO)
        end)

        -- C-n: create new khard contact
        map({ 'i', 'n' }, '<C-n>', function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          local name  = entry and entry.value.name  or ''
          local email = entry and entry.value.email or ''
          local parts = vim.split(name, ' ', { trimempty = true })
          local first = parts[1] or ''
          local last  = table.concat(vim.list_slice(parts, 2), ' ')
          vim.ui.input({ prompt = 'First name: ', default = first }, function(fn)
            if not fn then return end
            vim.ui.input({ prompt = 'Last name: ', default = last }, function(ln)
              if not ln then return end
              vim.ui.input({ prompt = 'Email: ', default = email }, function(em)
                if not em or em == '' then return end
                vim.ui.select({ 'work', 'home', 'other' }, { prompt = 'Email type:' }, function(etype)
                  if not etype then return end
                  local vcard = table.concat({
                    'BEGIN:VCARD', 'VERSION:3.0',
                    'FN:' .. fn .. ' ' .. ln,
                    'N:' .. ln .. ';' .. fn .. ';;;',
                    'EMAIL;TYPE=' .. etype:upper() .. ':' .. em,
                    'END:VCARD',
                  }, '\n')
                  local res = vim.system({ 'khard', 'add', '--input-format=vcard' },
                    { text = true, stdin = vcard }):wait()
                  if res.code == 0 then
                    vim.notify('✓ Contact created: ' .. fn .. ' ' .. ln, vim.log.levels.INFO)
                  else
                    vim.notify('✗ khard add failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
                  end
                end)
              end)
            end)
          end)
        end)

        return true
      end,
    }):find()
  end

  -- Load async, open picker when ready
  vim.system(
    { 'notmuch', 'address', '--format=text', '--deduplicate=address', '*' },
    { text = true },
    function(result)
      local entries = parse_entries(result.stdout)
      vim.schedule(function() open(entries) end)
    end
  )
end

M.contacts = contacts_picker
return M
