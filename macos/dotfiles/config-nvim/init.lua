
vim.cmd([[
  set runtimepath^=~/.vim runtimepath+=~/.vim/after
  let &packpath = &runtimepath
  source ~/.vimrc
]])
require("config.lazy")
require("lazy").setup("plugins")
vim.g.python3_host_prog = '~/adminvenv/bin/python'
vim.opt.laststatus = 3

require'nvim-treesitter.configs'.setup {
   ensure_installed = { "terraform" }, -- List of languages to install automatically
   highlight = {
     enable = true,              -- Enable syntax highlighting
     additional_vim_regex_highlighting = false, -- Do NOT enable additional vim highlighting
   },
}

vim.cmd("colorscheme habamax")
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  command = "%s/\\s\\+$//ge",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 8
    vim.opt_local.shiftwidth = 8
    vim.opt_local.softtabstop = 8
  end,
})
