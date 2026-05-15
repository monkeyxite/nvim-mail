-- Minimal init for running tests
local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')

-- Try local plenary path (dev machine), fall back to rtp (CI)
local plenary_path = vim.fn.expand('~/.local/Cellar/neovim/0.12.2/share/nvim/kickstart/lazy/plenary.nvim')
if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = '/tmp/plenary.nvim'
end

vim.opt.rtp:prepend(plugin_path)
vim.opt.rtp:prepend(plenary_path)

package.path = plugin_path .. '/lua/?.lua;'
  .. plugin_path .. '/lua/?/init.lua;'
  .. package.path
