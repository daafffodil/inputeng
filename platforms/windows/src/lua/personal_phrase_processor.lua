-- Observe committed Chinese text without changing normal key handling.
-- A multi-segment phrase is learned after its first successful composition.
-- A committed short term is queued for a missing English gloss immediately.

local M = {}

local RUNTIME_REFRESH_SECONDS = 1

local function normalize_code(value)
  if not value then
    return ""
  end
  return value:lower():gsub("[^a-z]", "")
end

local function is_han_codepoint(codepoint)
  return (codepoint >= 0x3400 and codepoint <= 0x4DBF)
      or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
      or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
      or (codepoint >= 0x20000 and codepoint <= 0x2CEAF)
      or codepoint == 0x3007
end

local function is_han_text(text, minimum, maximum)
  if not text or text == "" or text:find("[\t\r\n]") then
    return false
  end
  if not utf8 or not utf8.codes then
    return false
  end
  local count = 0
  local ok = pcall(function()
    for _, codepoint in utf8.codes(text) do
      if not is_han_codepoint(codepoint) then
        error("non-han")
      end
      count = count + 1
    end
  end)
  return ok and count >= minimum and count <= maximum
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function append_line(path, value)
  local file = io.open(path, "a")
  if not file then
    return false
  end
  file:write(value, "\n")
  file:close()
  return true
end

local function phrase_exists(path, code, text)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  local found = false
  for line in file:lines() do
    local normalized = line:gsub("^\239\187\191", ""):gsub("\r$", "")
    local saved_code, saved_text = normalized:match("^([^\t]+)\t([^\t]+)$")
    if saved_code == code and saved_text == text then
      found = true
      break
    end
  end
  file:close()
  return found
end

local function append_phrase(env, code, text)
  if phrase_exists(env.phrase_path, code, text) then
    return true
  end
  local file = io.open(env.phrase_path, "a")
  if not file then
    return false
  end
  file:write(code, "\t", text, "\n")
  file:close()
  env.version_counter = env.version_counter + 1
  local version = tostring(os.time()) .. "-" .. tostring(env.version_counter)
  local version_file = io.open(env.version_path, "w")
  if version_file then
    version_file:write(version, "\n")
    version_file:close()
  end
  return true
end

local function refresh_ai_enabled(env)
  local now = os.time()
  if now >= env.next_ai_refresh then
    env.ai_enabled = file_exists(env.ai_enabled_path)
    env.next_ai_refresh = now + RUNTIME_REFRESH_SECONDS
  end
end

local function record_commit(env, text)
  if is_han_text(text, 1, 8) then
    refresh_ai_enabled(env)
    if env.ai_enabled then
      -- The background worker removes terms already covered by the offline or
      -- AI dictionary, so writing the committed term here stays lightweight.
      append_line(env.missing_path, text)
    end
  end
end

local function reset_composition(env)
  env.active_code = ""
  env.prior_selection_count = 0
end

function M.init(env)
  local user_dir = rime_api.get_user_data_dir()
  env.phrase_path = user_dir .. "/input_translate_personal_phrases.tsv"
  env.version_path = user_dir .. "/input_translate_personal_phrases.version"
  env.missing_path = user_dir .. "/input_translate_missing.txt"
  env.ai_enabled_path = user_dir .. "/input_translate_ai_enabled"
  env.active_code = ""
  env.prior_selection_count = 0
  env.version_counter = 0
  env.ai_enabled = file_exists(env.ai_enabled_path)
  env.next_ai_refresh = os.time() + RUNTIME_REFRESH_SECONDS

  -- v0.5.0 learns on the first composition, so the old second-confirmation
  -- state is no longer meaningful.
  os.remove(user_dir .. "/input_translate_phrase_pending.tsv")

  local context = env.engine.context
  env.update_connection = context.update_notifier:connect(function(ctx)
    local code = normalize_code(ctx.input)
    if code ~= env.active_code then
      env.active_code = code
      env.prior_selection_count = 0
    end
  end)

  env.select_connection = context.select_notifier:connect(function(ctx)
    local code = normalize_code(ctx.input)
    if code == "" then
      return
    end
    if code ~= env.active_code then
      env.active_code = code
      env.prior_selection_count = 0
    end
    -- ExpressEditor commits inside Rime's earlier final-selection callback.
    -- Therefore >= 1 here means at least one segment was selected before the
    -- final segment, so the result was manually composed from multiple parts.
    env.prior_selection_count = env.prior_selection_count + 1
  end)

  env.commit_connection = context.commit_notifier:connect(function(ctx)
    local code = normalize_code(ctx.input)
    local text = ctx:get_commit_text() or ""

    record_commit(env, text)

    local qualifies = env.prior_selection_count >= 1
        and #code >= 4 and #code <= 64
        and is_han_text(text, 2, 8)
    if qualifies then
      append_phrase(env, code, text)
    end
    reset_composition(env)
  end)
end

function M.func(_, _)
  return 2 -- kNoop: observation only; normal key processing stays untouched.
end

function M.fini(env)
  if env.update_connection then env.update_connection:disconnect() end
  if env.select_connection then env.select_connection:disconnect() end
  if env.commit_connection then env.commit_connection:disconnect() end
  env.update_connection = nil
  env.select_connection = nil
  env.commit_connection = nil
end

return M
