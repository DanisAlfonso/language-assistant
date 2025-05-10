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
    table.insert(lines, "Press <Enter> to view details, 'c' to clear history, 'q' or <Esc> to close")
    table.insert(lines, "")
    
    -- Define entry line numbers for interaction
    local entry_lines = {}
    
    -- Add history entries
    for i, entry in ipairs(history) do
        -- Stop at 20 entries to keep it readable
        if i > 20 then
            table.insert(lines, "")
            table.insert(lines, "... (more entries not shown)")
            break
        end
        
        -- Store the line number for this entry
        entry_lines[#lines + 1] = i
        
        -- Add a section for this entry with fancier formatting
        local entry_type_icon = "📝" -- Default icon
        if entry.type == "translation" then
            entry_type_icon = "🔄"
        elseif entry.type == "explanation" then
            entry_type_icon = "📚"
        end
        
        local entry_title = "## " .. entry_type_icon .. " " .. i .. ". " .. entry.text:gsub("\n", " ")
        table.insert(lines, entry_title)
        table.insert(lines, "")
        
        -- Process result to avoid newlines in each line
        -- Get just the first line or a short summary
        local result_preview = ""
        local first_line = entry.result:match("^([^\n\r]+)")
        if first_line then
            -- Get first line and truncate it if too long
            result_preview = first_line:sub(1, 80) .. (first_line:len() > 80 and "..." or "")
        else
            -- If no clear first line, just get the first part and truncate
            result_preview = entry.result:sub(1, 80):gsub("\n", " ") .. "..."
        end
        
        -- Add a fancy quote-style preview
        table.insert(lines, "> " .. result_preview)
        table.insert(lines, "")
        
        -- Add metadata with a visual indicator for interactive elements
        local date_parts = entry.timestamp:match("(%d+%-%d+%-%d+) (%d+:%d+:%d+)")
        local formatted_date = date_parts and date_parts or entry.timestamp
        table.insert(lines, "*" .. formatted_date .. "* · [**Click to view full details**]")
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
    end
    
    -- Set content
    pcall(function()
        vim.api.nvim_buf_set_option(buf, "modifiable", true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        
        -- Add mapping to clear history
        vim.api.nvim_buf_set_keymap(buf, "n", "c", 
            ":lua require('languages-assistant.history').clear_history()<CR>", 
            { noremap = true, silent = true, desc = "Clear history" }
        )
        
        -- Save the history data in the buffer for reference
        vim.api.nvim_buf_set_var(buf, "language_history", history)
        vim.api.nvim_buf_set_var(buf, "entry_lines", entry_lines)
        
        -- Add mapping to view entry details
        vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", 
            ":lua require('languages-assistant.ui').show_history_entry_details()<CR>", 
            { noremap = true, silent = true, desc = "View entry details" }
        )
        
        vim.api.nvim_buf_set_option(buf, "modifiable", false)
    end)
end

-- Show details for a specific history entry
function M.show_history_entry_details()
    -- Get current buffer and cursor position
    local buf = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    
    -- Get entry lines and history from buffer variables
    local ok, entry_lines = pcall(vim.api.nvim_buf_get_var, buf, "entry_lines")
    if not ok then
        vim.notify("Could not get entry line information", vim.log.levels.ERROR)
        return
    end
    
    local ok, history = pcall(vim.api.nvim_buf_get_var, buf, "language_history")
    if not ok then
        vim.notify("Could not get history information", vim.log.levels.ERROR)
        return
    end
    
    -- Find which entry we're on
    local entry_index = nil
    for line, idx in pairs(entry_lines) do
        -- Check if cursor is on or after this line and before the next entry line
        if cursor_line >= line then
            -- Find the next entry line
            local next_line = nil
            for l, _ in pairs(entry_lines) do
                if l > line and (next_line == nil or l < next_line) then
                    next_line = l
                end
            end
            
            -- If cursor is before the next entry line or there is no next entry
            if next_line == nil or cursor_line < next_line then
                entry_index = idx
            end
        end
    end
    
    -- If we found an entry, show its details
    if entry_index and history[entry_index] then
        local entry = history[entry_index]
        
        -- We have two options for showing the details:
        -- 1. New floating window
        -- 2. Replace current window content with details view
        
        -- Option 1: Show in a new floating window (better for comparing entries)
        local entry_type_icon = "📝" -- Default icon
        if entry.type == "translation" then
            entry_type_icon = "🔄"
        elseif entry.type == "explanation" then
            entry_type_icon = "📚"
        end
        
        local window_title = entry_type_icon .. " " .. entry.text:sub(1, 30)
        if #entry.text > 30 then window_title = window_title .. "..." end
        
        -- Get a larger window size for details
        local config = vim.deepcopy(parent.config.ui.window)
        config.width = math.min(config.width + 20, 120) -- Wider window for details
        config.height = math.min(config.height + 10, 40) -- Taller window for details
        
        local detail_buf, detail_win = M.create_floating_window(window_title)
        
        -- Prepare content for the detail view
        local entry_type = entry.type or "unknown"
        local detail_lines = {}
        
        -- Common header with fancy formatting
        table.insert(detail_lines, "# " .. entry_type_icon .. " " .. entry.text)
        table.insert(detail_lines, "")
        
        -- Pretty timestamp with additional info
        local date_parts = entry.timestamp:match("(%d+%-%d+%-%d+) (%d+:%d+:%d+)")
        local formatted_date = date_parts and date_parts or entry.timestamp
        
        local type_name = "Unknown"
        if entry_type == "translation" then
            type_name = "Translation"
        elseif entry_type == "explanation" then
            type_name = "Vocabulary Lookup"
        end
        
        table.insert(detail_lines, "*" .. type_name .. " · " .. formatted_date .. "*")
        table.insert(detail_lines, "")
        table.insert(detail_lines, "---")
        table.insert(detail_lines, "")
        
        -- Format based on entry type
        if entry_type == "translation" then
            -- Source section
            table.insert(detail_lines, "## Source Text (" .. (entry.source_lang or "unknown") .. ")")
            table.insert(detail_lines, "")
            table.insert(detail_lines, "> " .. entry.text)
            table.insert(detail_lines, "")
            
            -- Translation section
            table.insert(detail_lines, "## Translation (" .. (entry.target_lang or "unknown") .. ")")
            table.insert(detail_lines, "")
        elseif entry_type == "explanation" then
            -- Explanation section
            table.insert(detail_lines, "## Explanation")
            table.insert(detail_lines, "")
        end
        
        -- Process the result content with proper section formatting
        local current_section = ""
        local in_code_block = false
        
        for line in entry.result:gmatch("[^\r\n]+") do
            -- Check if this line is a section header
            local section_match = line:match("^([A-Z][A-Z%s]+):$")
            
            if section_match then
                -- This is a new section
                current_section = section_match
                table.insert(detail_lines, "### " .. section_match)
                table.insert(detail_lines, "")
            elseif line:match("^```") then
                -- Handle code blocks
                in_code_block = not in_code_block
                table.insert(detail_lines, line)
            elseif in_code_block then
                -- Preserve code block content
                table.insert(detail_lines, line)
            elseif line:match("^%s*[•●]%s") or line:match("^%d+%.%s") then
                -- Bullet points - add some indentation
                table.insert(detail_lines, line)
            elseif line:match("^%s*-%s") then
                -- List items - add some indentation
                table.insert(detail_lines, line)
            else
                -- Regular content
                table.insert(detail_lines, line)
            end
        end
        
        -- Set the content
        pcall(function()
            vim.api.nvim_buf_set_option(detail_buf, "modifiable", true)
            vim.api.nvim_buf_set_lines(detail_buf, 0, -1, false, detail_lines)
            
            -- Set filetype for syntax highlighting
            vim.api.nvim_buf_set_option(detail_buf, "filetype", "markdown")
            
            -- Add keymapping to close window
            vim.api.nvim_buf_set_keymap(detail_buf, "n", "q", ":q<CR>", 
                { noremap = true, silent = true, desc = "Close window" }
            )
            vim.api.nvim_buf_set_keymap(detail_buf, "n", "<Esc>", ":q<CR>", 
                { noremap = true, silent = true, desc = "Close window" }
            )
            
            vim.api.nvim_buf_set_option(detail_buf, "modifiable", false)
        end)
    else
        vim.notify("No entry found at this position", vim.log.levels.WARN)
    end
end

return M
