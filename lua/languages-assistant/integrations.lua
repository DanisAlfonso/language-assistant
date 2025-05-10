-- Integrations module for language assistant plugin
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Set up which-key integration
function M.setup_which_key()
    -- Check if which-key is available
    local ok, which_key = pcall(require, "which-key")
    if not ok then
        return false
    end
    
    -- Get prefix from config
    local prefix = parent.config.keymaps.prefix
    
    -- Register group with which-key
    which_key.register({
        [prefix] = { name = "Language Assistant" }
    })
    
    return true
end

-- Set up telescope integration (stub for future implementation)
function M.setup_telescope()
    -- Check if telescope is available
    local ok, telescope = pcall(require, "telescope")
    if not ok then
        return false
    end
    
    -- This is a placeholder for future telescope integration
    -- For now, just return true to indicate it's available
    return true
end

return M
