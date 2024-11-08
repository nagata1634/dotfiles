--[[
pythonの設定
https://github.com/neovim/pynvim.git
]]
vim.g.python3_host_prog = vim.fn.exepath('python3')

--[[
lazy.nvimのインストール
https://github.com/folke/lazy.nvim.git
]]
require('config.lazy')

--[[
lualine.nvimのインストール
https://github.com/nvim-lualine/lualine.nvim.git
]]
require('config.lualine')

-- 基本設定

-- エディター画面
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 4

-- テキストエディター
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- 検索
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- 連携
vim.opt.clipboard:append("unnamedplus")
