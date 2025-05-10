-- UI module for language learning plugin
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Create floating window for displaying content
function M.create_floating_window(title)
    -- Get config
    local config = parent.config.ui.window
    
    -- Calculate dimensions
    local width = config.width or 80
    local height = config.height or 20
    local col = (vim.o.columns - width) / 2
    local row = (vim.o.lines - height) / 2
    
    -- Adjust position if needed
    if config.position == "top" then
        row = 2
    elseif config.position == "bottom" then
        row = vim.o.lines - height - 2
    elseif config.position == "left" then
        col = 2
    elseif config.position == "right" then
        col = vim.o.columns - width - 2
    end
    
    -- Create buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
    
    -- Set window options
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = config.border or "rounded",
        title = title or "Language Assistant",
        title_pos = "center"
    }
    
    -- Create window
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    
    -- Set window-local options
    vim.api.nvim_win_set_option(win, "conceallevel", 2)
    vim.api.nvim_win_set_option(win, "wrap", true)
    
    -- Enable proper word wrapping to prevent words from being split
    vim.api.nvim_win_set_option(win, "linebreak", true)
    vim.api.nvim_win_set_option(win, "breakindent", true)
    vim.api.nvim_win_set_option(win, "breakindentopt", "shift:2")
    
    -- Add keybindings to close window
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":q<CR>", { noremap = true, silent = true })
    
    return buf, win
end

-- Display loading indicator
function M.set_loading_content(buf, query)
    -- Use pcall to safely check buffer validity
    local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
    if not ok or not is_valid then return end
    
    -- Get icon if enabled
    local loading_icon = ""
    if parent.config.ui.icons and parent.config.ui.icons.enabled then
        loading_icon = parent.config.ui.icons.loading .. " "
    end
    
    -- Set content
    local ok, _ = pcall(function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            loading_icon .. "Loading...",
            "",
            "Query: " .. query
        })
        
        -- Make buffer modifiable
        vim.api.nvim_buf_set_option(buf, "modifiable", false)
    end)
    
    if not ok then
        vim.notify("Failed to set loading content", vim.log.levels.ERROR)
    end
end

-- Update window with content
function M.update_content(buf, content)
    -- Use pcall to safely check buffer validity
    local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
    if not ok or not is_valid then return end
    
    -- Get window ID associated with this buffer (if any)
    local win_id = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if pcall(function() return vim.api.nvim_win_get_buf(w) == buf end) then
            win_id = w
            break
        end
    end
    
    -- Perform all buffer operations inside pcall
    local ok, err = pcall(function()
        -- Make buffer modifiable
        vim.api.nvim_buf_set_option(buf, "modifiable", true)
        
        -- Split content into lines
        local lines = {}
        for line in content:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end
        
        -- Get window width if available for text formatting decisions
        local win_width = 80 -- default
        if win_id and pcall(vim.api.nvim_win_get_width, win_id) then
            win_width = vim.api.nvim_win_get_width(win_id) - 4 -- account for margins
        end
        
        -- Add some styling to the content by adding blank lines and formatting
        local styled_lines = {}
        local section = ""
        
        for _, line in ipairs(lines) do
            -- Check if this is a heading (section title)
            if line:match("^[A-Z][A-Z%s]+:$") then
                -- Add a blank line before each section except the first
                if #styled_lines > 0 then
                    table.insert(styled_lines, "")
                end
                
                section = line:match("^([A-Z][A-Z%s]+):")
                
                -- Add styled section heading (with width that fits window)
                local header_width = math.min(win_width - 6, 60) -- limit header width
                local separator = string.rep("─", header_width - #line - 4)
                table.insert(styled_lines, "── " .. line .. " " .. separator)
            else
                -- Process section content differently based on section
                if section == "EXAMPLES" then
                    -- Don't modify example lines
                    table.insert(styled_lines, line)
                elseif section == "PRONUNCIATION" or section == "PRONUNCIATION GUIDE" then
                    -- Enhance IPA content
                    if line:match("%[.+%]") then
                        table.insert(styled_lines, "  " .. line) -- Indent IPA
                    else
                        table.insert(styled_lines, line)
                    end
                elseif line:match("^%s*[•●]%s") then
                    -- Format bullet points with better indentation and optional wrapping
                    -- Keep bullet points with original formatting
                    table.insert(styled_lines, "  " .. line)
                elseif line:match("^%s*-%s") then
                    -- Format dash bullet points with better indentation
                    table.insert(styled_lines, "  " .. line)
                else
                    table.insert(styled_lines, line)
                end
            end
        end
        
        -- Update buffer
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, styled_lines)
        
        -- Add syntax highlighting for markdown
        vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
        
        -- Make buffer non-modifiable again
        vim.api.nvim_buf_set_option(buf, "modifiable", false)
    end)
    
    if not ok then
        vim.notify("Failed to update content: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
end

-- Show history window
function M.show_history_window()
    -- Get history
    local history = parent.state.history
    
    -- Check if there's anything to show
    if #history == 0 then
        vim.notify("No history entries yet", vim.log.levels.INFO)
        return
    end
    
    -- Create window
    local buf, win = M.create_floating_window("Language Learning History")
    
    -- Prepare content
    local lines = {}
    table.insert(lines, "# Language Learning History")
    table.insert(lines, "")
    
    -- Add history entries
    for i, entry in ipairs(history) do
        -- Stop at 20 entries to keep it readable
        if i > 20 then
            table.insert(lines, "")
            table.insert(lines, "... (more entries not shown)")
            break
        end
        
        table.insert(lines, "## " .. i .. ". " .. entry.text)
        table.insert(lines, "")
        table.insert(lines, entry.result:sub(1, 80) .. (entry.result:len() > 80 and "..." or ""))
        table.insert(lines, "")
        table.insert(lines, "*" .. entry.timestamp .. "*")
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
    end
    
    -- Set content
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

return M
