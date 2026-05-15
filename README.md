# nvim-mail

Neovim Lua plugin for mail compose enhancements. Replaces `vim-mail` with a pure Lua implementation. Designed for neomutt + nvr workflow.

## Features

- **Navigation** — jump to headers (To/Cc/Bcc/Subject/From/Reply-To), body, signature, quoted reply
- **Switch From** — select sender from configured address list
- **Kill quoted sig** — remove quoted signatures from replies
- **Spell lang cycling** — cycle through configured spell languages
- **Attachment awareness** — warns on save if body mentions "attach/enclosed/PFA" but no attachment marker found
- **Muttlook marker visibility** — shows `↩ replying to:` and `🔗 thread:` as virtual text over raw markers
- **Thread context** — opens the replied-to message rendered via `nm-html-extract` in a terminal split below (ANSI colors)
- **Contact completion** — blink-cmp provider for khard, scoped by account (work/personal based on From: header)
- **Markdown preview** — renders mail body via pandoc and opens in browser
- **Smart snippets** — context-aware snippets via vscode JSON format (luasnip)

## Install

lazy.nvim (local path):
```lua
{
  dir = '~/codebase/tools/nvim-mail',
  ft = 'mail',
  opts = {
    from_list = {
      'John Doe <john@work.com>',
      'John Doe <john@gmail.com>',
    },
    spell_langs = { 'en', 'sv' },
    contacts = {
      from_map = { ['work%.com'] = 'work', ['gmail%.com'] = 'personal' },
      accounts = {
        work = { cmd = 'khard', args = { 'email', '-p', '--remove-first-line', '-A', 'work' } },
        personal = { cmd = 'khard', args = { 'email', '-p', '--remove-first-line', '-A', 'personal' } },
      },
    },
  },
}
```

## Keymaps

All under configurable prefix (default `,m`):

### Navigation (replaces vim-mail)

| Key | Action |
|-----|--------|
| `,mt` | Go to To: field |
| `,mc` | Go to Cc: field |
| `,mb` | Go to Bcc: field |
| `,ms` | Go to Subject: field |
| `,mf` | Go to From: field |
| `,mF` | Switch From address |
| `,mR` | Go to Reply-To: field |
| `,mB` | Jump to body |
| `,mS` | Jump to signature |
| `,mr` | Jump to first quoted line |
| `,mE` | End of reply (before quotes) |
| `,mk` | Kill quoted signature |
| `,ml` | Cycle spell language |

### New features

| Key | Action |
|-----|--------|
| `,mT` | Thread context (nm-html-extract in terminal split) |
| `,mp` | Preview mail body as HTML in browser |

### Automatic

| Trigger | Action |
|---------|--------|
| `:w` | Warns if "attach" mentioned but no attachment marker |
| Buffer open | Muttlook markers shown as virtual text |
| Completion | khard contacts on To:/Cc:/Bcc: lines (blink-cmp) |

## Snippets

Loaded via vscode JSON format at `snips/snippets/mail.json`:

| Trigger | Expands to |
|---------|-----------|
| `mbr` | Best regards,\n[name] |
| `mty` | Thanks for the update. |
| `mpfa` | Please find attached. |
| `mfyi` | FYI — [context]. |
| `mack` | Acknowledged, will follow up by [date]. |
| `mch` | Cheers,\n[name] |
| `mlmk` | Let me know what you think. |
| `msig` | Best,\n[name] |

## Dependencies

| Tool | Used by | Required |
|------|---------|----------|
| `notmuch` | Thread context | Yes (for `,mT`) |
| `nm-html-extract` | Thread rendering | Yes (for `,mT`) |
| `muttlook` | Thread rendering (via nm-html-extract) | Yes (for `,mT`) |
| `pandoc` | Markdown preview | Yes (for `,mp`) |
| `khard` | Contact completion | Yes (for contacts) |
| `blink.cmp` | Completion framework | Optional |
| `luasnip` | Snippet expansion | Optional |

## Configuration

```lua
require('nvim-mail').setup({
  prefix = ',m',           -- keymap prefix
  from_list = {},          -- addresses for ,mF switch
  spell_langs = { 'en' },  -- languages for ,ml cycling
  contacts = {
    cmd = 'khard',         -- fallback contact command
    args = { 'email', '-p', '--remove-first-line' },
    from_map = {},         -- From: pattern → account name
    accounts = {},         -- per-account { cmd, args }
  },
})
```

### Blink-cmp provider

Add to your blink config:
```lua
sources = {
  per_filetype = {
    mail = { 'mail_contacts', 'snippets', 'buffer', 'spell', 'path' },
  },
  providers = {
    mail_contacts = {
      name = 'Contacts',
      module = 'nvim-mail.contacts',
      score_offset = 10,
      enabled = function() return vim.bo.filetype == 'mail' end,
    },
  },
}
```

## Tests

```bash
cd ~/codebase/tools/nvim-mail
nvim --headless --clean -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/mail/ {minimal_init = 'tests/minimal_init.lua'}"
```

51 tests covering: attachment detection, marker parsing, thread commands, navigation, contacts, snippets, preview.

## Structure

```
lua/nvim-mail/
├── init.lua        — setup, keymaps, autocmds
├── attachment.lua  — attachment mention detection
├── marker.lua      — muttlook marker extmarks (reply-to + references)
├── thread.lua      — nm-html-extract thread in terminal split
├── contacts.lua    — blink-cmp provider for khard (per-account)
├── preview.lua     — pandoc HTML preview
├── snippets.lua    — context detection (snippets via vscode JSON)
└── navigate.lua    — header/body/signature navigation
```

## Migrating from vim-mail

This plugin replaces `dbeniamine/vim-mail`. Remove it from your lazy config and use nvim-mail instead. All vim-mail navigation keys are preserved under the same `,m` prefix.
