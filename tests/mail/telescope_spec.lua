describe('mail.telescope reply', function()
  describe('from address detection via notmuch_path', function()
    it('matches work path to work from address', function()
      local contacts = require('nvim-mail.contacts')

      contacts.config.accounts = {
        work = { notmuch_path = 'work', from = 'John Doe <john@work.com>' },
        personal = { notmuch_path = 'monkeyxite@gmail.com', from = 'John Doe <john@gmail.com>' },
      }

      local file_path = '/home/user/.local/share/mail/work/INBOX/cur/123.eml'
      local my_from = ''
      for _, acct_cfg in pairs(contacts.config.accounts) do
        if acct_cfg.notmuch_path and file_path:find(acct_cfg.notmuch_path, 1, true) then
          my_from = acct_cfg.from or ''
          break
        end
      end
      assert.equals('John Doe <john@work.com>', my_from)
    end)

    it('matches gmail path to personal address', function()
      local contacts = require('nvim-mail.contacts')

      contacts.config.accounts = {
        work = { notmuch_path = 'work', from = 'John Doe <john@work.com>' },
        personal = { notmuch_path = 'monkeyxite@gmail.com', from = 'John Doe <john@gmail.com>' },
      }

      local file_path = '/home/user/.local/share/mail/monkeyxite@gmail.com/INBOX/cur/456.eml'
      local my_from = ''
      for _, acct_cfg in pairs(contacts.config.accounts) do
        if acct_cfg.notmuch_path and file_path:find(acct_cfg.notmuch_path, 1, true) then
          my_from = acct_cfg.from or ''
          break
        end
      end
      assert.equals('John Doe <john@gmail.com>', my_from)
    end)

    it('falls back to first from_list entry for unknown path', function()
      local contacts = require('nvim-mail.contacts')
      local init = require('nvim-mail')

      contacts.config.accounts = {
        work = { notmuch_path = 'work', from = 'John Doe <john@work.com>' },
      }
      init.config.from_list = { 'John Doe <john@default.com>' }

      local file_path = '/home/user/.local/share/mail/unknown/INBOX/cur/789.eml'
      local my_from = ''
      for _, acct_cfg in pairs(contacts.config.accounts) do
        if acct_cfg.notmuch_path and file_path:find(acct_cfg.notmuch_path, 1, true) then
          my_from = acct_cfg.from or ''
          break
        end
      end
      if my_from == '' then
        my_from = init.config.from_list[1]
      end
      assert.equals('John Doe <john@default.com>', my_from)
    end)
  end)
end)
