-- Flashcards module for language learning plugin
local M = {}

-- Get parent module
local parent = require("languages-assistant")

-- Constants
M.STATE = {
  NEW = 1,
  LEARNING = 2,
  REVIEW = 3,
  RELEARNING = 4
}

M.RATING = {
  AGAIN = 1,
  HARD = 2,
  GOOD = 3,
  EASY = 4
}

-- Default FSRS parameters (optimized based on research)
local DEFAULT_PARAMETERS = {
  0.4, -- initial_stability_for_again_answer
  1.2, -- initial_stability_step_per_rating
  3.2, -- initial_difficulty_for_good_answer
  -0.5, -- initial_difficulty_step_per_rating
  -0.5, -- next_difficulty_step_per_rating
  0.2, -- next_difficulty_reversion_to_mean_speed
  1.4, -- next_stability_factor_after_success
  -0.12, -- next_stability_stabilization_decay_after_success
  0.8, -- next_stability_retrievability_gain_after_success
  2.0, -- next_interval_days_factor
  0.2, -- next_interval_fuzz_factor
  0.9, -- target_retention_rate
}

-- Helper functions
local function calculate_retrievability(elapsed_days, stability)
  return math.exp(math.log(0.9) * elapsed_days / stability)
end

local function calculate_difficulty(card, rating)
  local params = DEFAULT_PARAMETERS
  local difficulty = card.difficulty or params[3]
  
  -- Update difficulty based on rating
  if rating <= M.RATING.AGAIN then
    difficulty = difficulty + params[5]
  elseif rating == M.RATING.HARD then
    difficulty = difficulty + params[5] / 2
  elseif rating == M.RATING.GOOD then
    -- No change for "Good" responses
  elseif rating == M.RATING.EASY then
    difficulty = difficulty - params[5]
  end
  
  -- Reversion to mean
  difficulty = params[3] + (difficulty - params[3]) * (1 - params[6])
  
  -- Constrain between 1 and 5
  return math.max(1, math.min(5, difficulty))
end

local function calculate_stability(card, rating)
  local params = DEFAULT_PARAMETERS
  local stability = card.stability or 0
  
  if card.state == M.STATE.NEW then
    -- New cards
    if rating <= M.RATING.AGAIN then
      stability = params[1]
    else
      stability = params[1] + (rating - 1) * params[2]
    end
  else
    -- Learning/review cards
    if rating <= M.RATING.AGAIN then
      -- Failed card gets reset stability
      stability = params[1]
    else
      -- Calculate retrievability
      local elapsed_days = (os.time() - card.last_review) / (24 * 60 * 60)
      local retrievability = calculate_retrievability(elapsed_days, stability)
      
      -- Apply stability formula
      local stability_factor = params[7]
      local stability_decay = math.exp(params[8] * stability)
      local retrievability_gain = params[9] * (1 - retrievability)
      
      stability = stability * stability_factor * stability_decay + retrievability_gain
      
      -- Adjust based on rating
      if rating == M.RATING.HARD then
        stability = stability * 0.8 -- Reduce stability for hard cards
      elseif rating == M.RATING.EASY then
        stability = stability * 1.3 -- Increase stability for easy cards
      end
    end
  end
  
  -- Ensure minimum stability
  return math.max(0.1, stability)
end

local function calculate_interval(stability, rating)
  local params = DEFAULT_PARAMETERS
  local interval = 0
  
  if rating <= M.RATING.AGAIN then
    -- Failed card gets a 1-day interval
    interval = 1
  else
    -- Calculate interval based on stability and target retention
    local factor = params[10]
    if rating == M.RATING.HARD then
      factor = factor * 0.8
    elseif rating == M.RATING.EASY then
      factor = factor * 1.3
    end
    
    interval = math.ceil(stability * factor)
    
    -- Apply random fuzz if enabled
    if parent.config.flashcards.fuzzy_intervals then
      local fuzz = 1.0 + (math.random() - 0.5) * 2 * params[11]
      interval = math.ceil(interval * fuzz)
    end
    
    -- Constrain to maximum interval
    local max_interval = parent.config.flashcards.maximum_interval or 365
    interval = math.min(interval, max_interval)
    
    -- Minimum interval is 1 day
    interval = math.max(1, interval)
  end
  
  return interval
end

-- Load flashcards from storage
function M.load()
  local path = parent.config.storage.flashcards_path
  local file = io.open(path, "r")
  
  if file then
    local content = file:read("*all")
    file:close()
    
    if content and content ~= "" then
      local ok, data = pcall(vim.json.decode, content)
      if ok and data then
        parent.state.flashcards = data
        vim.notify("Loaded " .. #data .. " flashcards", vim.log.levels.INFO)
      else
        vim.notify("Failed to parse flashcards data", vim.log.levels.ERROR)
        parent.state.flashcards = {}
      end
    else
      parent.state.flashcards = {}
    end
  else
    parent.state.flashcards = {}
    -- Create the directory if it doesn't exist
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end
  
  return parent.state.flashcards
end

-- Save flashcards to storage
function M.save()
  local path = parent.config.storage.flashcards_path
  local file = io.open(path, "w")
  
  if file then
    local ok, content = pcall(vim.json.encode, parent.state.flashcards)
    if ok then
      file:write(content)
      file:close()
      return true
    else
      file:close()
      vim.notify("Failed to encode flashcards data", vim.log.levels.ERROR)
      return false
    end
  else
    vim.notify("Failed to open flashcards file for writing", vim.log.levels.ERROR)
    return false
  end
end

-- Add a new flashcard
function M.add_card(card_data)
  -- Ensure we have the minimum required fields
  if not card_data.front or not card_data.back then
    vim.notify("Card must have front and back content", vim.log.levels.ERROR)
    return false
  end
  
  -- Create a new card with FSRS properties
  local new_card = vim.tbl_extend("force", card_data, {
    id = tostring(os.time()) .. "_" .. math.random(1000, 9999),
    state = M.STATE.NEW,
    difficulty = DEFAULT_PARAMETERS[3], -- Default difficulty
    stability = 0,
    created_at = card_data.created_at or os.date("%Y-%m-%d %H:%M:%S"),
    last_review = os.time(),
    due_date = os.time(), -- Due immediately
    review_count = 0,
    lapses = 0,
    tags = card_data.tags or parent.config.flashcards.default_tags or {},
  })
  
  -- Add to the collection
  table.insert(parent.state.flashcards, new_card)
  
  -- Save if auto-save is enabled
  if parent.config.storage.auto_save then
    M.save()
  end
  
  vim.notify("Added new flashcard", vim.log.levels.INFO)
  return true
end

-- Update an existing flashcard based on review
function M.update_card(card_id, rating)
  -- Find the card
  local card_index = nil
  local card = nil
  
  for i, c in ipairs(parent.state.flashcards) do
    if c.id == card_id then
      card_index = i
      card = c
      break
    end
  end
  
  if not card then
    vim.notify("Card not found", vim.log.levels.ERROR)
    return false
  end
  
  -- Update card properties based on FSRS algorithm
  local old_state = card.state
  
  -- Update difficulty
  card.difficulty = calculate_difficulty(card, rating)
  
  -- Update stability
  card.stability = calculate_stability(card, rating)
  
  -- Determine new state
  if rating <= M.RATING.AGAIN then
    if old_state == M.STATE.NEW or old_state == M.STATE.LEARNING then
      card.state = M.STATE.LEARNING
    else
      card.state = M.STATE.RELEARNING
      card.lapses = (card.lapses or 0) + 1
    end
  else
    if old_state == M.STATE.NEW or old_state == M.STATE.LEARNING or old_state == M.STATE.RELEARNING then
      card.state = M.STATE.REVIEW
    end
  end
  
  -- Calculate next interval
  local interval = calculate_interval(card.stability, rating)
  
  -- Update due date
  card.last_review = os.time()
  card.due_date = os.time() + interval * 24 * 60 * 60
  card.review_count = (card.review_count or 0) + 1
  card.last_rating = rating
  
  -- Save the updated card
  parent.state.flashcards[card_index] = card
  
  -- Save if auto-save is enabled
  if parent.config.storage.auto_save then
    M.save()
  end
  
  return {
    card = card,
    interval = interval,
    next_date = os.date("%Y-%m-%d", card.due_date)
  }
end

-- Get cards due for review
function M.get_due_cards()
  local due_cards = {}
  local now = os.time()
  local learn_ahead_time = (parent.config.flashcards.learn_ahead_time or 0) * 24 * 60 * 60
  
  for _, card in ipairs(parent.state.flashcards) do
    if card.suspended ~= true and card.due_date <= now + learn_ahead_time then
      table.insert(due_cards, card)
    end
  end
  
  -- Sort cards by due date (oldest first)
  table.sort(due_cards, function(a, b)
    return (a.due_date or 0) < (b.due_date or 0)
  end)
  
  return due_cards
end

-- Get all flashcards
function M.get_all_cards()
  return parent.state.flashcards
end

-- Update an existing card's content
function M.edit_card(card_id, new_data)
  for i, card in ipairs(parent.state.flashcards) do
    if card.id == card_id then
      -- Update allowed fields
      if new_data.front ~= nil then card.front = new_data.front end
      if new_data.back ~= nil then card.back = new_data.back end
      if new_data.tags ~= nil then card.tags = new_data.tags end
      if new_data.notes ~= nil then card.notes = new_data.notes end
      if new_data.suspended ~= nil then card.suspended = new_data.suspended end
      
      -- Save if auto-save is enabled
      if parent.config.storage.auto_save then
        M.save()
      end
      
      return true
    end
  end
  
  return false
end

-- Delete a card
function M.delete_card(card_id)
  for i, card in ipairs(parent.state.flashcards) do
    if card.id == card_id then
      table.remove(parent.state.flashcards, i)
      
      -- Save if auto-save is enabled
      if parent.config.storage.auto_save then
        M.save()
      end
      
      return true
    end
  end
  
  return false
end

-- Export flashcards to a text file
function M.export_flashcards()
  local path = parent.config.storage.export_path
  local file = io.open(path, "w")
  
  if not file then
    vim.notify("Failed to open export file for writing", vim.log.levels.ERROR)
    return false
  end
  
  -- Write header
  file:write("# Language Assistant Flashcards Export\n")
  file:write("# Generated on " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  file:write("# Format: Front | Back | Tags | State | Due Date\n\n")
  
  -- Write cards
  for _, card in ipairs(parent.state.flashcards) do
    local state_names = { "NEW", "LEARNING", "REVIEW", "RELEARNING" }
    local state_name = state_names[card.state] or "UNKNOWN"
    local due_date = os.date("%Y-%m-%d", card.due_date or 0)
    local tags = table.concat(card.tags or {}, ", ")
    
    -- Format: Front | Back | Tags | State | Due Date
    file:write(card.front .. " | " .. card.back .. " | " .. tags .. " | " .. state_name .. " | " .. due_date .. "\n")
  end
  
  file:close()
  vim.notify("Exported " .. #parent.state.flashcards .. " flashcards to " .. path, vim.log.levels.INFO)
  return true
end

-- Convert history entries to flashcards
function M.convert_history_to_flashcards()
  if not parent.state.history or #parent.state.history == 0 then
    vim.notify("No history entries to convert", vim.log.levels.WARN)
    return 0
  end
  
  local count = 0
  local added_phrases = {}
  
  -- First, build a map of existing flashcards for quick lookup
  local existing_cards = {}
  for _, card in ipairs(parent.state.flashcards) do
    existing_cards[card.front] = true
  end
  
  for _, entry in ipairs(parent.state.history) do
    if entry.type == "translation" and entry.text and entry.result 
       and not added_phrases[entry.text] 
       and not existing_cards[entry.text] then -- Skip if already exists as a flashcard
      local card_data = {
        front = entry.text,
        back = entry.result,
        type = "translation",
        source_lang = entry.source_lang,
        target_lang = entry.target_lang,
        created_at = entry.timestamp,
        tags = {"from-history", "language-learning"}
      }
      
      if M.add_card(card_data) then
        count = count + 1
        added_phrases[entry.text] = true
      end
    end
  end
  
  if count > 0 then
    vim.notify("Converted " .. count .. " history entries to flashcards", vim.log.levels.INFO)
  else
    vim.notify("No new history entries to convert (all already exist as flashcards)", vim.log.levels.INFO)
  end
  
  return count
end

-- Calculate retention stats for the collection
function M.calculate_retention_stats()
  local total_reviews = 0
  local successful_reviews = 0
  
  for _, card in ipairs(parent.state.flashcards) do
    if card.review_count and card.review_count > 0 then
      total_reviews = total_reviews + card.review_count
      
      -- Estimate successful reviews based on last_rating
      if card.last_rating and card.last_rating >= M.RATING.GOOD then
        successful_reviews = successful_reviews + card.review_count - (card.lapses or 0)
      end
    end
  end
  
  local retention = 0
  if total_reviews > 0 then
    retention = successful_reviews / total_reviews
  end
  
  return {
    cards = #parent.state.flashcards,
    total_reviews = total_reviews,
    successful_reviews = successful_reviews,
    retention = retention,
    target_retention = parent.config.flashcards.target_retention or 0.9
  }
end

-- Reset all cards (for testing)
function M.reset_all_cards()
  for i, card in ipairs(parent.state.flashcards) do
    parent.state.flashcards[i] = vim.tbl_extend("force", card, {
      state = M.STATE.NEW,
      difficulty = DEFAULT_PARAMETERS[3],
      stability = 0,
      due_date = os.time(),
      review_count = 0,
      lapses = 0
    })
  end
  
  if parent.config.storage.auto_save then
    M.save()
  end
  
  vim.notify("Reset all flashcards to NEW state", vim.log.levels.INFO)
  return true
end

return M 