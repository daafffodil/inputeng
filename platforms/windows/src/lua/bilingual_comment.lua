-- Keep inputeng's live AI cache dynamic without putting the large offline
-- dictionaries on the per-key Lua path. Static Chinese/English comments are
-- supplied by librime's native reverse-lookup filter configured in the schema.

local M = {}

local RUNTIME_REFRESH_SECONDS = 1
local MISSING_BATCH_SIZE = 5

local shared = rawget(_G, "__inputeng_ai_filter_shared")
if not shared then
  shared = { runtime = {} }
  rawset(_G, "__inputeng_ai_filter_shared", shared)
end

local function read_first_line(path)
  local file = io.open(path, "r")
  if not file then return "" end
  local line = file:read("*l") or ""
  file:close()
  return line:gsub("^\239\187\191", ""):gsub("\r$", "")
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then return false end
  file:close()
  return true
end

local function load_tsv(path)
  local dictionary = {}
  local file = io.open(path, "r")
  if not file then return dictionary end
  for line in file:lines() do
    local normalized = line:gsub("^\239\187\191", ""):gsub("\r$", "")
    if normalized ~= "" and normalized:sub(1, 1) ~= "#" then
      local key, value = normalized:match("^([^\t]+)\t(.+)$")
      if key and value and dictionary[key] == nil then
        dictionary[key] = value
      end
    end
  end
  file:close()
  return dictionary
end

local function is_han_codepoint(codepoint)
  return (codepoint >= 0x3400 and codepoint <= 0x4DBF)
      or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
      or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
      or (codepoint >= 0x20000 and codepoint <= 0x2CEAF)
      or codepoint == 0x3007
end

local function is_short_han(text)
  if not text or text == "" or text:find("[\t\r\n]") or #text > 32 then
    return false
  end
  if utf8 and utf8.codes then
    local count = 0
    local ok = pcall(function()
      for _, codepoint in utf8.codes(text) do
        if not is_han_codepoint(codepoint) then error("non-han") end
        count = count + 1
      end
    end)
    return ok and count > 0 and count <= 8
  end
  return not text:match("^[%z\1-\127]+$")
end

local function is_ascii_word(text)
  return text and #text >= 3 and text:match("^[A-Za-z][A-Za-z'-]*$") ~= nil
end

local function runtime_for(user_dir)
  local cached = shared.runtime[user_dir]
  if cached then return cached end
  local runtime = {
    cache_path = user_dir .. "/input_translate_ai_cache.tsv",
    version_path = user_dir .. "/input_translate_ai_cache.version",
    enabled_path = user_dir .. "/input_translate_ai_enabled",
    missing_path = user_dir .. "/input_translate_missing.txt",
    enabled = false,
    version = "",
    dictionary = {},
    next_refresh = 0,
    queued = {},
    pending = {},
  }
  runtime.enabled = file_exists(runtime.enabled_path)
  runtime.version = read_first_line(runtime.version_path)
  runtime.dictionary = load_tsv(runtime.cache_path)
  runtime.next_refresh = os.time() + RUNTIME_REFRESH_SECONDS
  shared.runtime[user_dir] = runtime
  return runtime
end

local function refresh(runtime)
  local now = os.time()
  if now < runtime.next_refresh then return end
  runtime.next_refresh = now + RUNTIME_REFRESH_SECONDS
  runtime.enabled = file_exists(runtime.enabled_path)
  if not runtime.enabled then
    runtime.pending = {}
    return
  end
  local version = read_first_line(runtime.version_path)
  if version ~= runtime.version then
    runtime.dictionary = load_tsv(runtime.cache_path)
    runtime.version = version
  end
end

local function flush(runtime)
  if not runtime.enabled or #runtime.pending == 0 then return end
  local file = io.open(runtime.missing_path, "a")
  if not file then return end
  for _, text in ipairs(runtime.pending) do file:write(text, "\n") end
  file:close()
  runtime.pending = {}
end

local function queue_missing(runtime, text)
  if not runtime.enabled or runtime.queued[text] or not is_short_han(text) then
    return
  end
  runtime.queued[text] = true
  table.insert(runtime.pending, text)
  if #runtime.pending >= MISSING_BATCH_SIZE then flush(runtime) end
end

function M.init(env)
  env.runtime = runtime_for(rime_api.get_user_data_dir())
  env.commit_connection = env.engine.context.commit_notifier:connect(function(context)
    local text = context:get_commit_text() or ""
    refresh(env.runtime)
    if not env.runtime.dictionary[text] then
      queue_missing(env.runtime, text)
      -- A composed phrase may never have existed as one visible candidate.
      -- Flush after commit so the background worker can translate it at once.
      flush(env.runtime)
    end
  end)
end

function M.func(input, env)
  local runtime = env.runtime
  refresh(runtime)
  flush(runtime)

  local first = true
  local english_mode = false
  for candidate in input:iter() do
    if first then
      english_mode = candidate.type == "table" and is_ascii_word(candidate.text)
      first = false
    end

    if english_mode then
      if candidate.type == "table" and is_ascii_word(candidate.text) then
        yield(candidate)
      end
    else
      -- Native reverse lookup has already filled normal offline comments. Only touch a
      -- candidate when a newer DeepSeek result exists or no offline gloss does.
      local ai = runtime.dictionary[candidate.text]
      if ai and ai ~= "" then
        yield(ShadowCandidate(candidate, candidate.type, candidate.text, ai))
      else
        if not candidate.comment or candidate.comment == "" then
          queue_missing(runtime, candidate.text)
        end
        yield(candidate)
      end
    end
  end
end

function M.fini(env)
  if env.commit_connection then env.commit_connection:disconnect() end
  if env.runtime then flush(env.runtime) end
  env.commit_connection = nil
  env.runtime = nil
end

return M
