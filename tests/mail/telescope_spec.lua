describe('mail.telescope reply', function()
  describe('build_reply_all_cc', function()
    local r

    before_each(function()
      package.loaded['nvim-mail.reply'] = nil
      r = require('nvim-mail.reply')
    end)

    it('returns empty string when no To or Cc', function()
      assert.equals('', r.build_reply_all_cc('', '', 'me@example.com'))
    end)

    it('uses orig_to as Cc when no orig_cc', function()
      local cc = r.build_reply_all_cc('alice@example.com', '', 'me@example.com')
      assert.equals('alice@example.com', cc)
    end)

    it('merges orig_to and orig_cc', function()
      local cc = r.build_reply_all_cc('alice@example.com', 'bob@example.com', 'me@example.com')
      assert.equals('alice@example.com, bob@example.com', cc)
    end)

    it('strips self (my_from) from result', function()
      local cc = r.build_reply_all_cc('alice@example.com, me@example.com', 'bob@example.com', 'me@example.com')
      assert.equals('alice@example.com, bob@example.com', cc)
    end)

    it('strips self when my_from is Name <email> form', function()
      local cc = r.build_reply_all_cc('Alice <alice@example.com>, Me <me@example.com>', '', 'Myself <me@example.com>')
      assert.equals('Alice <alice@example.com>', cc)
    end)

    it('deduplicates addresses across To and Cc', function()
      local cc = r.build_reply_all_cc('alice@example.com', 'alice@example.com, bob@example.com', 'me@example.com')
      assert.equals('alice@example.com, bob@example.com', cc)
    end)

    it('returns empty string when only self is in lists', function()
      local cc = r.build_reply_all_cc('me@example.com', '', 'me@example.com')
      assert.equals('', cc)
    end)

    it('self-matching is case-insensitive', function()
      local cc = r.build_reply_all_cc('ME@EXAMPLE.COM', 'bob@example.com', 'me@example.com')
      assert.equals('bob@example.com', cc)
    end)
  end)

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
