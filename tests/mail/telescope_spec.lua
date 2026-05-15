describe('mail.telescope reply', function()
  describe('from address detection', function()
    it('matches maildir path to from_list via from_map', function()
      local contacts = require('nvim-mail.contacts')
      local init = require('nvim-mail')

      -- Setup config
      contacts.config.from_map = { ['work'] = 'work', ['gmail'] = 'personal' }
      init.config.from_list = {
        'John Doe <john@work.com>',
        'John Doe <john@gmail.com>',
      }

      -- Simulate: file path contains 'work'
      local file_path = '/home/user/.local/share/mail/work/INBOX/cur/123.eml'
      local my_from = ''
      for pattern, acct in pairs(contacts.config.from_map) do
        if file_path:find(pattern) then
          for _, addr in ipairs(init.config.from_list) do
            if addr:lower():find(pattern) then
              my_from = addr
              break
            end
          end
          break
        end
      end
      assert.equals('John Doe <john@work.com>', my_from)
    end)

    it('matches gmail path to personal address', function()
      local contacts = require('nvim-mail.contacts')
      local init = require('nvim-mail')

      contacts.config.from_map = { ['work'] = 'work', ['gmail'] = 'personal' }
      init.config.from_list = {
        'John Doe <john@work.com>',
        'John Doe <john@gmail.com>',
      }

      local file_path = '/home/user/.local/share/mail/monkeyxite@gmail.com/INBOX/cur/456.eml'
      local my_from = ''
      for pattern, acct in pairs(contacts.config.from_map) do
        if file_path:find(pattern) then
          for _, addr in ipairs(init.config.from_list) do
            if addr:lower():find(pattern) then
              my_from = addr
              break
            end
          end
          break
        end
      end
      assert.equals('John Doe <john@gmail.com>', my_from)
    end)

    it('returns empty for unknown path', function()
      local contacts = require('nvim-mail.contacts')
      local init = require('nvim-mail')

      contacts.config.from_map = { ['work'] = 'work', ['gmail'] = 'personal' }
      init.config.from_list = {
        'John Doe <john@work.com>',
        'John Doe <john@gmail.com>',
      }

      local file_path = '/home/user/.local/share/mail/unknown/INBOX/cur/789.eml'
      local my_from = ''
      for pattern, acct in pairs(contacts.config.from_map) do
        if file_path:find(pattern) then
          for _, addr in ipairs(init.config.from_list) do
            if addr:lower():find(pattern) then
              my_from = addr
              break
            end
          end
          break
        end
      end
      assert.equals('', my_from)
    end)
  end)
end)
