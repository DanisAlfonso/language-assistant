-- Flashcards UI module
local M = {}

-- Get parent module
local parent = require("languages-assistant")
local flashcards = require("languages-assistant.flashcards")
local ui = require("languages-assistant.ui")

-- Color palette (supports both dark and light themes)
local colors = {
  header_bg = "#4a4a4a", -- Dark gray for header bg
  header_fg = "#f0f0f0", -- Light text for header
  card_again_bg = "#ab4642", -- Red for "Again" button
  card_hard_bg = "#dc9656", -- Orange for "Hard" button
  card_good_bg = "#7ca456", -- Green for "Good" button
  card_easy_bg = "#6a9fb5", -- Blue for "Easy" button
  card_button_fg = "#f0f0f0", -- Light text color for buttons
  card_front_bg = "#383838", -- Slightly darker for front
  card_back_bg = "#303030", -- Darker for back
  card_fg = "#f0f0f0", -- Light text for cards
  stats_fg = "#a1b56c", -- Light green for stats
  border_fg = "#585858", -- Medium gray for borders
}

-- UI state
M.state = {
  review_buffer = nil,
  review_window = nil,
  current_card_index = 1,
  cards = {},
  card_side = "front", -- "front" or "back"
  session_stats = {
    total = 0,
    again = 0,
    hard = 0,
    good = 0,
    easy = 0,
    started_at = nil,
  },
}

-- Function to extract the main translation from a verbose translation text
local function extract_primary_translation(text)
  if not text then return "" end
  
  -- Case 1: Full translation format with TRANSLATION prefix
  local translation = text:match("TRANSLATION:%s*([^%.]+)")
  if translation then
    -- Return just the translation part, remove the prefix and trim whitespace
    return translation:gsub("^%s*", ""):gsub("%s*$", "")
  end
  
  -- Case 2: Simple text without formatting, just return the first sentence
  local first_sentence = text:match("^([^%.]+)")
  if first_sentence and first_sentence:len() < text:len() / 2 then
    -- If first sentence is significantly shorter than full text, likely a summary
    return first_sentence .. "."
  end
  
  -- Case 3: Default fallback, return the text as is but limit length
  if text:len() > 200 then
    -- If text is very long, truncate it
    return text:sub(1, 197) .. "..."
  end
  
  -- Otherwise return text as is
  return text
end

-- Function to wrap text at a specific width
function M.wrap_text(text, width)
  if not text then return {} end
  
  local lines = {}
  local current_line = ""
  
  -- Split the text by spaces
  for word in text:gmatch("%S+") do
    -- If adding this word would exceed the width
    if #current_line + #word + 1 > width then
      -- Add the current line to our list of lines
      table.insert(lines, current_line)
      -- Start a new line with this word
      current_line = word
    elseif current_line == "" then
      -- First word on the line
      current_line = word
    else
      -- Add the word with a space
      current_line = current_line .. " " .. word
    end
  end
  
  -- Add the last line if it's not empty
  if current_line ~= "" then
    table.insert(lines, current_line)
  end
  
  -- Handle case of empty lines
  if #lines == 0 then
    table.insert(lines, "")
  end
  
  return lines
end

-- Initialize UI module
function M.setup()
  -- Set up autocommands
  vim.api.nvim_create_augroup("LanguagesAssistantFlashcards", { clear = true })
  
  -- Close flashcards buffer when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    group = "LanguagesAssistantFlashcards",
    callback = function(args)
      local winnr = tonumber(args.match)
      if winnr and winnr == M.state.review_window then
        M.cleanup_review()
      end
    end
  })
end

-- Review due flashcards
function M.review_due_cards()
  -- Get due cards
  local due_cards = flashcards.get_due_cards()
  
  if #due_cards == 0 then
    vim.notify("No flashcards due for review", vim.log.levels.INFO)
    return
  end
  
  -- Update UI state
  M.state.cards = due_cards
  M.state.current_card_index = 1
  M.state.card_side = "front"
  M.state.session_stats = {
    total = #due_cards,
    again = 0,
    hard = 0,
    good = 0,
    easy = 0,
    started_at = os.time(),
  }
  
  -- Create review UI
  M.show_review_ui()
end

-- Browse all flashcards
function M.browse_flashcards()
  -- Get all cards
  local all_cards = flashcards.get_all_cards()
  
  if #all_cards == 0 then
    vim.notify("No flashcards found", vim.log.levels.INFO)
    return
  end
  
  -- Sort by due date
  table.sort(all_cards, function(a, b)
    return (a.due_date or 0) < (b.due_date or 0)
  end)
  
  -- Update UI state
  M.state.cards = all_cards
  M.state.current_card_index = 1
  M.state.card_side = "front"
  M.state.session_stats = {
    total = #all_cards,
    again = 0,
    hard = 0,
    good = 0,
    easy = 0,
    started_at = os.time(),
  }
  
  -- Create browse UI
  M.show_browse_ui()
end

-- Create a nice centered window for flashcards
function M.create_flashcard_window()
  -- Calculate dimensions
  local cfg = parent.config.ui.flashcards
  local width = cfg.card_width or 80
  local height = math.floor(vim.o.lines * 0.7)
  
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "languages-assistant-flashcards")
  
  -- Calculate position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  -- Window options
  local opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Flashcards Review ",
    title_pos = "center",
  }
  
  -- Create window
  local win = vim.api.nvim_open_win(buf, true, opts)
  
  -- Set window options
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
  
  if cfg.hide_scrollbar then
    vim.api.nvim_win_set_option(win, "fillchars", "eob: ")
  end
  
  return buf, win
end

-- Set up common keybindings for the flashcard UI
function M.setup_keybindings(buf, mode)
  local keymaps = require("languages-assistant.keymaps").flashcard_keybindings
  
  -- Define action callbacks
  local actions = {
    ["Next Card"] = function() M.next_card() end,
    ["Previous Card"] = function() M.prev_card() end,
    ["Flip Card"] = function() M.flip_card() end,
    ["Again (1)"] = function()
      if mode == "review" and M.state.card_side == "back" then
        M.rate_card(flashcards.RATING.AGAIN)
      end
    end,
    ["Hard (2)"] = function()
      if mode == "review" and M.state.card_side == "back" then
        M.rate_card(flashcards.RATING.HARD)
      end
    end,
    ["Good (3)"] = function()
      if mode == "review" and M.state.card_side == "back" then
        M.rate_card(flashcards.RATING.GOOD)
      end
    end,
    ["Easy (4)"] = function()
      if mode == "review" and M.state.card_side == "back" then
        M.rate_card(flashcards.RATING.EASY)
      end
    end,
    ["Edit Card"] = function() M.edit_current_card() end,
    ["Delete Card"] = function() M.delete_current_card() end,
    ["Add Tag"] = function() M.add_tag_to_card() end,
    ["Mark Suspended"] = function() M.toggle_suspend_card() end,
    ["Quit"] = function() M.cleanup_review() end,
  }
  
  -- Apply all keybindings
  for _, keymap in ipairs(keymaps) do
    local mode, key, desc = unpack(keymap)
    
    vim.api.nvim_buf_set_keymap(buf, mode, key, "", {
      noremap = true,
      silent = true,
      desc = desc,
      callback = actions[desc]
    })
  end
end

-- Show the review UI
function M.show_review_ui()
  -- Create window
  local buf, win = M.create_flashcard_window()
  
  -- Update UI state
  M.state.review_buffer = buf
  M.state.review_window = win
  
  -- Set up keybindings
  M.setup_keybindings(buf, "review")
  
  -- Render the current card
  M.render_current_card()
end

-- Show the browse UI
function M.show_browse_ui()
  -- Create window
  local buf, win = M.create_flashcard_window()
  
  -- Update UI state
  M.state.review_buffer = buf
  M.state.review_window = win
  
  -- Set up keybindings
  M.setup_keybindings(buf, "browse")
  
  -- Render the current card
  M.render_current_card()
end

-- Render the current card in the review window
function M.render_current_card()
  local buf = M.state.review_buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Get current card
  local card = M.state.cards[M.state.current_card_index]
  if not card then
    return
  end
  
  -- Clear buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  
  -- Get window dimensions
  local win_width = vim.api.nvim_win_get_width(M.state.review_window)
  
  -- Calculate padding
  local padding = math.floor((win_width - 60) / 2)
  padding = math.max(padding, 2) -- At least 2 spaces padding
  local pad_str = string.rep(" ", padding)
  
  -- Extract clean translation if this is from history
  local front_text = card.front
  local back_text = extract_primary_translation(card.back)
  
  -- Render header
  local header_lines = M.render_header()
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, header_lines)
  
  -- Render card content
  local card_lines = {}
  
  -- Add empty lines for spacing
  table.insert(card_lines, "")
  table.insert(card_lines, "")
  
  -- Front content with clean horizontal dividers
  if front_text then
    local wrapped_front = M.wrap_text(front_text, 60)
    
    -- Top divider with rounded corners
    table.insert(card_lines, pad_str .. "╭" .. string.rep("─", 62) .. "╮")
    
    -- Card label - Remove "Front" label
    -- table.insert(card_lines, pad_str .. "Front")
    table.insert(card_lines, "")
    
    -- Add front content
    for _, line in ipairs(wrapped_front) do
      local spaces = 60 - vim.fn.strdisplaywidth(line)
      local centered_line = string.rep(" ", math.floor(spaces/2)) .. line
      table.insert(card_lines, pad_str .. centered_line)
    end
    
    -- Show prompt if on front side
    if M.state.card_side == "front" then
      table.insert(card_lines, "")
    end
    
    -- Bottom divider with rounded corners
    table.insert(card_lines, pad_str .. "╰" .. string.rep("─", 62) .. "╯")
  end
  
  -- Add back content if card is flipped
  if M.state.card_side == "back" and back_text then
    -- Add spacing between front and back
    table.insert(card_lines, "")
    table.insert(card_lines, "")
    
    -- Top divider with rounded corners
    table.insert(card_lines, pad_str .. "╭" .. string.rep("─", 62) .. "╮")
    
    -- Back label - Remove "Back" label
    -- table.insert(card_lines, pad_str .. "Back")
    table.insert(card_lines, "")
    
    local wrapped_back = M.wrap_text(back_text, 60)
    
    -- Add back content
    for _, line in ipairs(wrapped_back) do
      local spaces = 60 - vim.fn.strdisplaywidth(line)
      local centered_line = string.rep(" ", math.floor(spaces/2)) .. line
      table.insert(card_lines, pad_str .. centered_line)
    end
    
    -- Add rating buttons for review mode
    if M.is_review_mode() then
      table.insert(card_lines, "")
      
      -- Center the rating buttons
      local buttons_text = "[1] Again     [2] Hard     [3] Good     [4] Easy"
      local button_spaces = 60 - vim.fn.strdisplaywidth(buttons_text)
      local centered_buttons = string.rep(" ", math.floor(button_spaces/2)) .. buttons_text
      table.insert(card_lines, pad_str .. centered_buttons)
    end
    
    -- Bottom divider with rounded corners
    table.insert(card_lines, pad_str .. "╰" .. string.rep("─", 62) .. "╯")
  end
  
  -- Add card metadata but make it minimal
  if card.tags and #card.tags > 0 then
    table.insert(card_lines, "")
    local tags_text = table.concat(card.tags, ", ")
    table.insert(card_lines, pad_str .. "Tags: " .. tags_text)
  end
  
  -- Add responsive help text at the bottom that adapts to window width
  table.insert(card_lines, "")
  local help_text = M.get_responsive_help_text(win_width - (padding * 2))
  table.insert(card_lines, pad_str .. help_text)
  
  -- Add all lines to buffer
  vim.api.nvim_buf_set_lines(buf, #header_lines, -1, false, card_lines)
  
  -- Apply syntax highlighting
  M.highlight_flashcard_buffer(buf)
  
  -- Make buffer non-modifiable
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Render a cleaner, more minimal header
function M.render_header()
  local header_lines = {}
  local win_width = vim.api.nvim_win_get_width(M.state.review_window)
  
  -- Calculate padding for centering
  local title = "Languages Assistant Flashcards"
  local padding = math.floor((win_width - #title) / 2)
  local pad_str = string.rep(" ", padding)
  
  -- Calculate session statistics
  local stats = M.state.session_stats
  local elapsed = os.time() - (stats.started_at or os.time())
  local elapsed_str = string.format("%02d:%02d", math.floor(elapsed / 60), elapsed % 60)
  local progress = string.format("%d/%d", M.state.current_card_index, #M.state.cards)
  
  -- Create header content
  table.insert(header_lines, "")
  table.insert(header_lines, pad_str .. title)
  table.insert(header_lines, pad_str .. string.rep("─", #title))
  table.insert(header_lines, "")
  
  -- Add progress info in a clean way
  local progress_text = "Progress: " .. progress .. "    ·    Time: " .. elapsed_str
  local progress_padding = math.floor((win_width - #progress_text) / 2)
  table.insert(header_lines, string.rep(" ", progress_padding) .. progress_text)
  
  table.insert(header_lines, "")
  
  return header_lines
end

-- Generate help text that fits the available width
function M.get_responsive_help_text(available_width)
  -- All commands we want to display
  local commands = {
    {"j/k", "navigate"},
    {"space", "flip"},
    {"1-4", "rate"},
    {"e", "edit"},
    {"d", "delete"},
    {"q", "quit"}
  }
  
  -- Full text would be: "j/k: navigate    space: flip    1-4: rate    e: edit    d: delete    q: quit"
  -- Calculate if it fits
  local spacer = "    "
  local full_text = ""
  for i, cmd in ipairs(commands) do
    full_text = full_text .. cmd[1] .. ": " .. cmd[2]
    if i < #commands then
      full_text = full_text .. spacer
    end
  end
  
  -- If full text fits, use it
  if vim.fn.strdisplaywidth(full_text) <= available_width then
    return full_text
  end
  
  -- If not, let's try shorter descriptions with smaller spacers
  spacer = "  "
  full_text = ""
  for i, cmd in ipairs(commands) do
    full_text = full_text .. cmd[1] .. ": " .. cmd[2]
    if i < #commands then
      full_text = full_text .. spacer
    end
  end
  
  -- If it fits now, use this
  if vim.fn.strdisplaywidth(full_text) <= available_width then
    return full_text
  end
  
  -- If still too wide, use a compact format
  full_text = ""
  for i, cmd in ipairs(commands) do
    full_text = full_text .. cmd[1] .. ":" .. cmd[2]
    if i < #commands then
      full_text = full_text .. " "
    end
  end
  
  -- If it fits now, use this
  if vim.fn.strdisplaywidth(full_text) <= available_width then
    return full_text
  end
  
  -- Last resort: show commands on multiple lines
  -- We'll return the first set of commands that fits
  local first_line = ""
  local remaining_commands = {}
  
  for i, cmd in ipairs(commands) do
    local next_part = cmd[1] .. ": " .. cmd[2]
    if i < #commands then
      next_part = next_part .. spacer
    end
    
    if vim.fn.strdisplaywidth(first_line .. next_part) <= available_width then
      first_line = first_line .. next_part
    else
      table.insert(remaining_commands, cmd)
    end
  end
  
  -- If we have a subset of commands that fit, show those
  if #remaining_commands == 0 or vim.fn.strdisplaywidth(first_line) == 0 then
    -- Either everything fit, or nothing fit 
    -- Just return what we have as best effort
    return first_line
  end
  
  -- Otherwise, create a second line for the remaining commands
  -- and add it to the display
  local second_line = ""
  for i, cmd in ipairs(remaining_commands) do
    second_line = second_line .. cmd[1] .. ": " .. cmd[2]
    if i < #remaining_commands then
      second_line = second_line .. spacer
    end
  end
  
  -- Insert the second line before returning
  table.insert(card_lines, pad_str .. second_line)
  
  return first_line
end

-- Custom highlighting for the improved UI
function M.highlight_flashcard_buffer(buf)
  -- Create highlight groups if they don't exist
  vim.cmd("highlight default FlashcardHeader gui=bold guifg=" .. colors.header_fg)
  vim.cmd("highlight default FlashcardBorder guifg=" .. colors.border_fg)
  vim.cmd("highlight default FlashcardTitle gui=bold guifg=" .. colors.header_fg)
  vim.cmd("highlight default FlashcardStats guifg=" .. colors.stats_fg)
  vim.cmd("highlight default FlashcardText guifg=" .. colors.card_fg)
  vim.cmd("highlight default FlashcardPrompt guifg=#8be9fd gui=italic")
  vim.cmd("highlight default FlashcardAgain guifg=#ff5555 gui=bold")
  vim.cmd("highlight default FlashcardHard guifg=#ffb86c gui=bold")
  vim.cmd("highlight default FlashcardGood guifg=#50fa7b gui=bold")
  vim.cmd("highlight default FlashcardEasy guifg=#8be9fd gui=bold")
  vim.cmd("highlight default FlashcardHelp guifg=#6272a4")
  
  -- Apply highlights using extmarks
  local ns_id = vim.api.nvim_create_namespace("flashcards_highlights")
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  
  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  
  for i, line in ipairs(lines) do
    -- Adjust to 0-indexed
    local idx = i - 1
    
    -- Header 
    if i <= 6 then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardHeader", idx, 0, -1)
    -- Card borders and labels
    elseif line:match("^%s*╭") or line:match("^%s*╰") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardBorder", idx, 0, -1)
    elseif line:match("^%s*Front%s*$") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardTitle", idx, 0, -1)
    elseif line:match("^%s*Back%s*$") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardTitle", idx, 0, -1)
    -- Card content - highlight all non-empty lines that aren't special elements
    elseif not line:match("^%s*$") and 
           not line:match("Tags:") and 
           not line:match("j/k:") and 
           not line:match("%[%d%]") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardText", idx, 0, -1)
    -- Help text
    elseif line:match("j/k:") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardHelp", idx, 0, -1)
    -- Tags
    elseif line:match("Tags:") then
      vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardStats", idx, 0, -1)
    end
    
    -- Highlight rating buttons if present
    if line:match("%[1%]%s+Again") then
      -- Find and highlight each button
      local again_start = line:find("%[1%]")
      local again_end = line:find("Again") + 4
      if again_start then 
        vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardAgain", idx, again_start-1, again_end)
      end
      
      local hard_start = line:find("%[2%]")
      local hard_end = line:find("Hard") + 3
      if hard_start then
        vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardHard", idx, hard_start-1, hard_end)
      end
      
      local good_start = line:find("%[3%]")
      local good_end = line:find("Good") + 3
      if good_start then
        vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardGood", idx, good_start-1, good_end)
      end
      
      local easy_start = line:find("%[4%]")
      local easy_end = line:find("Easy") + 3
      if easy_start then
        vim.api.nvim_buf_add_highlight(buf, ns_id, "FlashcardEasy", idx, easy_start-1, easy_end)
      end
    end
  end
end

-- Move to the next card
function M.next_card()
  if M.state.current_card_index < #M.state.cards then
    M.state.current_card_index = M.state.current_card_index + 1
    M.state.card_side = "front"
    M.render_current_card()
  else
    vim.notify("Already at the last card", vim.log.levels.INFO)
  end
end

-- Move to the previous card
function M.prev_card()
  if M.state.current_card_index > 1 then
    M.state.current_card_index = M.state.current_card_index - 1
    M.state.card_side = "front"
    M.render_current_card()
  else
    vim.notify("Already at the first card", vim.log.levels.INFO)
  end
end

-- Flip the current card
function M.flip_card()
  M.state.card_side = M.state.card_side == "front" and "back" or "front"
  M.render_current_card()
end

-- Rate the current card
function M.rate_card(rating)
  -- Get the current card
  local card = M.state.cards[M.state.current_card_index]
  if not card then return end
  
  -- Update the card in the database
  local result = flashcards.update_card(card.id, rating)
  if not result then return end
  
  -- Update the card in our local state
  M.state.cards[M.state.current_card_index] = result.card
  
  -- Update session stats
  if rating == flashcards.RATING.AGAIN then
    M.state.session_stats.again = M.state.session_stats.again + 1
  elseif rating == flashcards.RATING.HARD then
    M.state.session_stats.hard = M.state.session_stats.hard + 1
  elseif rating == flashcards.RATING.GOOD then
    M.state.session_stats.good = M.state.session_stats.good + 1
  elseif rating == flashcards.RATING.EASY then
    M.state.session_stats.easy = M.state.session_stats.easy + 1
  end
  
  -- Show notification with next review date
  vim.notify("Card rated " .. rating .. ". Next review: " .. result.next_date, vim.log.levels.INFO)
  
  -- Move to the next card if available
  if M.state.current_card_index < #M.state.cards then
    M.state.current_card_index = M.state.current_card_index + 1
    M.state.card_side = "front"
    M.render_current_card()
  else
    -- We've reviewed all cards, show summary
    M.show_review_summary()
  end
end

-- Show a summary of the review session
function M.show_review_summary()
  local buf = M.state.review_buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Calculate session statistics
  local stats = M.state.session_stats
  local elapsed = os.time() - stats.started_at
  local elapsed_str = string.format("%d:%02d", math.floor(elapsed / 60), elapsed % 60)
  local cards_per_min = elapsed > 0 and (stats.again + stats.hard + stats.good + stats.easy) / (elapsed / 60) or 0
  
  -- Clear buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  
  -- Create summary content
  local lines = {
    "╔" .. string.rep("═", 76) .. "╗",
    "║ Review Session Complete                                                    ║",
    "╠" .. string.rep("═", 76) .. "╣",
    "║                                                                            ║",
    "║  Session Statistics:                                                       ║",
    "║                                                                            ║",
    string.format("║  • Cards reviewed: %-59d ║", #M.state.cards),
    string.format("║  • Session time: %-60s ║", elapsed_str),
    string.format("║  • Cards per minute: %-56.1f ║", cards_per_min),
    "║                                                                            ║",
    string.format("║  • Again: %-67d ║", stats.again),
    string.format("║  • Hard: %-68d ║", stats.hard),
    string.format("║  • Good: %-68d ║", stats.good),
    string.format("║  • Easy: %-68d ║", stats.easy),
    "║                                                                            ║",
    "║  Press 'q' to close or 'r' to start another review session                ║",
    "║                                                                            ║",
    "╚" .. string.rep("═", 76) .. "╝",
  }
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Add keymapping for new review session
  vim.api.nvim_buf_set_keymap(buf, 'n', 'r', "", {
    noremap = true,
    silent = true,
    callback = function()
      M.cleanup_review()
      M.review_due_cards()
    end
  })
  
  -- Make buffer non-modifiable
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

-- Clean up review state and close window
function M.cleanup_review()
  -- Close the window if it exists
  if M.state.review_window and vim.api.nvim_win_is_valid(M.state.review_window) then
    vim.api.nvim_win_close(M.state.review_window, true)
  end
  
  -- Reset state
  M.state.review_buffer = nil
  M.state.review_window = nil
  M.state.cards = {}
  M.state.current_card_index = 1
  M.state.card_side = "front"
end

-- Check if we're in review mode (vs browse mode)
function M.is_review_mode()
  -- We're in review mode if we were launched from review_due_cards
  local due_cards = flashcards.get_due_cards()
  
  for _, card in ipairs(due_cards) do
    if card.id == M.state.cards[M.state.current_card_index].id then
      return true
    end
  end
  
  return false
end

-- Edit the current card
function M.edit_current_card()
  local card = M.state.cards[M.state.current_card_index]
  if not card then return end
  
  -- Create input buffer for front
  local function edit_front()
    vim.ui.input({
      prompt = "Edit front side: ",
      default = card.front,
    }, function(front)
      if front then
        -- Now edit the back
        vim.ui.input({
          prompt = "Edit back side: ",
          default = card.back,
        }, function(back)
          if back then
            -- Update the card
            local success = flashcards.edit_card(card.id, {
              front = front,
              back = back
            })
            
            if success then
              -- Update local copy
              card.front = front
              card.back = back
              
              -- Re-render
              M.render_current_card()
              
              -- Show success notification
              vim.notify("Card updated successfully", vim.log.levels.INFO)
            else
              vim.notify("Failed to update card", vim.log.levels.ERROR)
            end
          end
        end)
      end
    end)
  end
  
  -- Start editing
  edit_front()
end

-- Delete the current card
function M.delete_current_card()
  local card = M.state.cards[M.state.current_card_index]
  if not card then return end
  
  -- Ask for confirmation
  vim.ui.select({"Yes", "No"}, {
    prompt = "Are you sure you want to delete this card?",
  }, function(choice)
    if choice == "Yes" then
      -- Delete the card
      if flashcards.delete_card(card.id) then
        -- Remove from the local array
        table.remove(M.state.cards, M.state.current_card_index)
        
        -- Update the UI
        if #M.state.cards == 0 then
          -- No more cards to show
          vim.notify("No more cards to display", vim.log.levels.INFO)
          M.cleanup_review()
        else
          -- Adjust index if needed
          if M.state.current_card_index > #M.state.cards then
            M.state.current_card_index = #M.state.cards
          end
          
          -- Reset to front
          M.state.card_side = "front"
          
          -- Render
          M.render_current_card()
          
          -- Show success notification
          vim.notify("Card deleted successfully", vim.log.levels.INFO)
        end
      else
        vim.notify("Failed to delete card", vim.log.levels.ERROR)
      end
    end
  end)
end

-- Add a tag to the current card
function M.add_tag_to_card()
  local card = M.state.cards[M.state.current_card_index]
  if not card then return end
  
  vim.ui.input({
    prompt = "Add tag: ",
  }, function(tag)
    if tag and tag ~= "" then
      -- Get current tags
      local tags = card.tags or {}
      
      -- Add new tag if it doesn't exist
      if not vim.tbl_contains(tags, tag) then
        table.insert(tags, tag)
        
        -- Update the card
        flashcards.edit_card(card.id, {
          tags = tags
        })
        
        -- Update local copy
        card.tags = tags
        
        -- Re-render
        M.render_current_card()
      end
    end
  end)
end

-- Toggle suspended status of card
function M.toggle_suspend_card()
  local card = M.state.cards[M.state.current_card_index]
  if not card then return end
  
  -- Toggle suspended state
  local new_suspended = not (card.suspended or false)
  
  -- Update the card
  flashcards.edit_card(card.id, {
    suspended = new_suspended
  })
  
  -- Update local copy
  card.suspended = new_suspended
  
  -- Show notification
  vim.notify("Card " .. (new_suspended and "suspended" or "unsuspended"), vim.log.levels.INFO)
  
  -- Re-render
  M.render_current_card()
end

-- Convert history entries to flashcards
function M.convert_history_to_flashcards()
  local count = flashcards.convert_history_to_flashcards()
  
  if count > 0 then
    vim.ui.select({"View Flashcards Now", "Close"}, {
      prompt = "Converted " .. count .. " history entries to flashcards. View them now?",
    }, function(choice)
      if choice == "View Flashcards Now" then
        M.browse_flashcards()
      end
    end)
  end
end

return M 