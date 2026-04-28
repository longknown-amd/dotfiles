return require('packer').startup(
    function(use)
        use 'wbthomason/packer.nvim'
        use 'preservim/tagbar'
        use 'neovim/nvim-lspconfig'
    end
)
