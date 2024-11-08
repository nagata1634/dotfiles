return {

    -- プラグインリスト
{
    "nvim-treesitter/nvim-treesitter", -- ツリーシッター
    run = ":TSUpdate"
},
{   "hrsh7th/nvim-cmp" },  -- 補完プラグイン
{   "nvim-lua/plenary.nvim" },  -- ユーティリティライブラリ
{
    "nvim-lualine/lualine.nvim", -- ステータスライン
    dependencies = { "nvim-tree/nvim-web-devicons"},
}
{
    "williamboman/mason.nvim", -- mason 言語サーバー
    "williamboman/mason-lspconfig.nvim",
    "neovim/nvim-lspconfig",
}

}
