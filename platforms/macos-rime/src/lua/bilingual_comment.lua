-- Display a short English gloss beside Chinese Rime candidates.
-- Local data is always used first. An optional background helper can append
-- DeepSeek translations to the AI cache without blocking Rime's candidate
-- generation thread.

local M = {}

local MAX_GLOSS_BYTES = 24
local RUNTIME_REFRESH_SECONDS = 1
local MISSING_BATCH_SIZE = 5

local function read_first_line(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local line = file:read("*l") or ""
  file:close()
  return line:gsub("^\239\187\191", ""):gsub("\r$", "")
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function load_tsv(path)
  local dictionary = {}
  local file = io.open(path, "r")
  if not file then
    return dictionary
  end

  for line in file:lines() do
    local normalized = line:gsub("^\239\187\191", ""):gsub("\r$", "")
    if normalized ~= "" and normalized:sub(1, 1) ~= "#" then
      local chinese, english = normalized:match("^([^\t]+)\t(.+)$")
      if chinese and english and dictionary[chinese] == nil then
        dictionary[chinese] = english
      end
    end
  end

  file:close()
  return dictionary
end

local function short_gloss(value)
  if not value or value == "" then
    return ""
  end

  -- Windows packages pre-normalize the active core dictionary, and the AI
  -- worker already writes normalized values. Keep a fast path while retaining
  -- the full normalizer for the shared macOS dictionary and older caches.
  if #value <= MAX_GLOSS_BYTES
      and not value:find("[;(),]")
      and not value:find("^%s")
      and not value:find("%s$") then
    return value
  end

  local gloss = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  gloss = gloss:gsub("^simplified form of Chinese characters.*", "simplified Chinese")
  gloss = gloss:gsub("^traditional form of Chinese characters.*", "traditional Chinese")
  gloss = gloss:gsub("%s*%b()", "")
  gloss = gloss:match("^([^%(%)]+)") or gloss
  gloss = gloss:match("^([^;]+)") or gloss
  gloss = gloss:gsub("%s+$", "")

  if #gloss > MAX_GLOSS_BYTES then
    local comma = gloss:match("^([^,]+)")
    if comma and #comma >= 4 then
      gloss = comma:gsub("%s+$", "")
    end
  end

  if #gloss > MAX_GLOSS_BYTES then
    local prefix = gloss:sub(1, MAX_GLOSS_BYTES)
    local whole_words = prefix:gsub("%s+%S*$", "")
    if #whole_words >= 8 then
      gloss = whole_words
    else
      gloss = prefix
    end
  end

  return gloss:gsub("[%s,;:.-]+$", "")
end

local function is_han_codepoint(codepoint)
  return (codepoint >= 0x3400 and codepoint <= 0x4DBF)
      or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
      or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
      or (codepoint >= 0x20000 and codepoint <= 0x2CEAF)
      or codepoint == 0x3007
end

local function is_short_han_candidate(text)
  if not text or text == "" or text:find("[\t\r\n]") or #text > 32 then
    return false
  end

  if utf8 and utf8.codes then
    local count = 0
    local ok = pcall(function()
      for _, codepoint in utf8.codes(text) do
        if not is_han_codepoint(codepoint) then
          error("non-han")
        end
        count = count + 1
      end
    end)
    return ok and count > 0 and count <= 8
  end

  -- Old Lua runtimes may not expose utf8.codes. In that case, accept only
  -- non-ASCII text and let the background helper perform strict validation.
  return not text:match("^[%z\1-\127]+$")
end

local function refresh_runtime_state(env)
  local now = os.time()
  if now < env.next_runtime_refresh then
    return
  end
  env.next_runtime_refresh = now + RUNTIME_REFRESH_SECONDS
  env.ai_enabled = file_exists(env.ai_enabled_path)
  if not env.ai_enabled then
    env.pending_missing = {}
    return
  end

  local version = read_first_line(env.ai_version_path)
  if version == env.ai_version then
    return
  end
  env.ai_dictionary = load_tsv(env.ai_cache_path)
  env.ai_version = version
end

local function flush_pending_missing(env)
  if not env.ai_enabled or #env.pending_missing == 0 then
    return
  end

  local file = io.open(env.missing_path, "a")
  if not file then
    return
  end
  for _, text in ipairs(env.pending_missing) do
    file:write(text, "\n")
  end
  file:close()
  env.pending_missing = {}
end

local function queue_missing(env, text)
  if not env.ai_enabled or env.queued[text] or not is_short_han_candidate(text) then
    return
  end

  env.queued[text] = true
  table.insert(env.pending_missing, text)
  -- Rime filters are lazy. Flush before yielding the last candidate on a
  -- normal five-item page; smaller partial batches flush on the next refresh.
  if #env.pending_missing >= MISSING_BATCH_SIZE then
    flush_pending_missing(env)
  end
end

function M.init(env)
  local user_dir = rime_api.get_user_data_dir()
  env.override_dictionary = load_tsv(user_dir .. "/common_gloss_overrides.tsv")
  env.local_dictionary = load_tsv(user_dir .. "/bilingual_english.tsv")
  env.ai_cache_path = user_dir .. "/input_translate_ai_cache.tsv"
  env.ai_version_path = user_dir .. "/input_translate_ai_cache.version"
  env.ai_enabled_path = user_dir .. "/input_translate_ai_enabled"
  env.missing_path = user_dir .. "/input_translate_missing.txt"
  env.ai_enabled = file_exists(env.ai_enabled_path)
  env.ai_version = read_first_line(env.ai_version_path)
  env.ai_dictionary = load_tsv(env.ai_cache_path)
  env.next_runtime_refresh = os.time() + RUNTIME_REFRESH_SECONDS
  env.queued = {}
  env.pending_missing = {}
end

function M.func(input, env)
  refresh_runtime_state(env)
  -- Write the prior candidate refresh as one batch instead of opening the
  -- queue file once for every missing candidate.
  flush_pending_missing(env)
  local local_dictionary = env.local_dictionary or {}
  local override_dictionary = env.override_dictionary or {}
  local ai_dictionary = env.ai_dictionary or {}

  for candidate in input:iter() do
    local raw = override_dictionary[candidate.text]
    if not raw or raw == "" then
      raw = local_dictionary[candidate.text]
    end
    if not raw or raw == "" then
      raw = ai_dictionary[candidate.text]
    end

    local english = short_gloss(raw)
    if english ~= "" then
      -- ShadowCandidate keeps the original range, score and commit text. Only
      -- the visible comment is replaced with the normalized English gloss.
      yield(ShadowCandidate(candidate, candidate.type, candidate.text, english))
    else
      queue_missing(env, candidate.text)
      yield(candidate)
    end
  end
end

function M.fini(env)
  flush_pending_missing(env)
  env.override_dictionary = nil
  env.local_dictionary = nil
  env.ai_dictionary = nil
  env.queued = nil
  env.pending_missing = nil
end

return M
