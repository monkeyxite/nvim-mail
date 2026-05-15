# nvim-mail

Neovim Lua plugin for mail compose enhancements. Designed for neomutt + nvr workflow.

## Features

- **Attachment awareness** — warns on save if body mentions "attach/enclosed/PFA" but no actual attachment marker found
- **Muttlook marker visibility** — shows `↩ replying to:` and `🔗 thread:` as virtual text over raw markers
- **Thread context** (`<leader>mt`) — opens notmuch thread in a read-only vsplit
- **Contact completion** — nvim-cmp source for khard address book on To/Cc/Bcc lines
- **Markdown preview** (`<leader>mp`) — renders mail body via pandoc and opens in browser
- **Smart snippets** — context-aware luasnip snippets based on recipient domain (work/personal)

## Install

lazy.nvim (local path):
```lua
{ dir = '~/codebase/tools/nvim-mail', ft = 'mail' }
```

Or from GitHub:
```lua
{ 'monkeyxite/nvim-mail', ft = 'mail' }
```

## Configuration

```lua
require('nvim-mail').setup({
  contacts = {
    cmd = 'khard',
    args = { 'email', '-p', '--remove-first-line' },
  },
  snippets = {
    domains = {
      ['ericsson%.com'] = 'work',
      ['gmail%.com'] = 'personal',
    },
    snippets = {
      work = {
        { trigger = 'br', body = 'Best regards,\nJohn' },
      },
    },
  },
})
```

## Keymaps

| Key | Action |
|-----|--------|
| `<leader>mt` | Show notmuch thread context in vsplit |
| `<leader>mp` | Preview mail body as HTML in browser |

## Dependencies

- **notmuch** — for thread context
- **pandoc** — for markdown preview
- **khard** — for contact completion
- **nvim-cmp** — for completion integration (optional)
- **luasnip** — for smart snippets (optional)

## Tests

```bash
cd ~/codebase/tools/nvim-mail
nvim --headless --clean -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/mail/ {minimal_init = 'tests/minimal_init.lua'}"
```

## Structure

```
lua/nvim-mail/
├── init.lua        — setup, keymaps, autocmds
├── attachment.lua  — attachment mention detection
├── marker.lua      — muttlook marker extmarks
├── thread.lua      — notmuch thread vsplit
├── contacts.lua    — nvim-cmp source for khard
├── preview.lua     — pandoc HTML preview
└── snippets.lua    — context-aware snippets
```

## Roadmap

- [x] Attachment awareness
- [x] Muttlook marker visibility (reply-to + references)
- [x] Thread context split
- [x] Contact autocomplete (nvim-cmp source)
- [x] Inline markdown preview
- [x] Smart snippets by recipient
- [ ] Auto-signature selection
- [ ] Neomutt Lua integration (when PR #4707 lands)
