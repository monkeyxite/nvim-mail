-- Telescope extension for notmuch mail search
-- Usage: require('telescope').extensions.nvim_mail.search()
local M = {}

local function search(opts)
  opts = opts or {}
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

  local contacts = require('nvim-mail.contacts')
  local acct = contacts.detect_account()
  local path_filter = ''
  if acct and contacts.config.accounts[acct] and contacts.config.accounts[acct].notmuch_path then
    path_filter = ' AND path:' .. contacts.config.accounts[acct].notmuch_path .. '/**'
  end

  pickers.new(opts, {
    prompt_title = '  Notmuch Search',
    finder = finders.new_async_job({
      command_generator = function(prompt)
        if not prompt or prompt == '' then return nil end
        local query = prompt .. path_filter
        return { 'notmuch', 'search', '--format=json', '--output=summary', query }
      end,
      entry_maker = function(line)
        local ok, data = pcall(vim.json.decode, line)
        if not ok or not data then return nil end
        -- notmuch search --format=json returns array, handle single entries
        if data.thread then
          return {
            value = data,
            display = string.format('%s  %s  %s', data.date_relative or '', data.authors or '', data.subject or ''),
            ordinal = (data.authors or '') .. ' ' .. (data.subject or ''),
            thread = data.thread,
          }
        end
        return nil
      end,
    }),
    previewer = previewers.new_termopen_previewer({
      get_command = function(entry)
        if not entry or not entry.thread then return { 'echo', 'No thread' } end
        -- Use nm-html-extract for styled preview (same as nms)
        -- Get latest message-id from thread, render with nm-html-extract
        return { 'sh', '-c',
          'msgid=$(notmuch search --output=messages --limit=1 thread:' .. entry.thread .. ' | sed "s/^id://") && nm-html-extract "$msgid"'
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if entry and entry.thread then
          -- Open in neomutt
          vim.cmd('terminal neomutt -f "notmuch://?query=thread:' .. entry.thread .. '"')
        end
      end)
      return true
    end,
  }):find()
end

M.search = search

return require('telescope').register_extension({
  exports = {
    search = search,
  },
})
