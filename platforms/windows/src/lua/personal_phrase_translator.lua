-- Yield locally learned exact phrases before the main Luna Pinyin translator.

local M = {}
local REFRESH_INTERVAL_SECONDS = 1

local function normalize_code(value)
  if not value then
    return ""
  end
  return value:lower():gsub("[^a-z]", "")
end

local function read_first_line(path)
  local file = io.open(path, "r")
  if not file then
    return ""
  end
  local line = file:read("*l") or ""
  file:close()
  return line:gsub("^\239\187\191", ""):gsub("\r$", "")
end

local function load_phrases(path)
  local mapping = {}
  local file = io.open(path, "r")
  if not file then
    return mapping
  end
  for line in file:lines() do
    local normalized = line:gsub("^\239\187\191", ""):gsub("\r$", "")
    local code, text = normalized:match("^([^\t]+)\t([^\t]+)$")
    code = normalize_code(code)
    if code ~= "" and text and text ~= "" then
      mapping[code] = mapping[code] or {}
      local duplicate = false
      for _, saved in ipairs(mapping[code]) do
        if saved == text then duplicate = true break end
      end
      if not duplicate then
        table.insert(mapping[code], text)
      end
    end
  end
  file:close()
  return mapping
end

local function refresh(env)
  local now = os.time()
  if now < env.next_refresh then
    return
  end
  env.next_refresh = now + REFRESH_INTERVAL_SECONDS
  local version = read_first_line(env.version_path)
  if version ~= env.version then
    env.phrases = load_phrases(env.phrase_path)
    env.version = version
  end
end

function M.init(env)
  local user_dir = rime_api.get_user_data_dir()
  env.phrase_path = user_dir .. "/input_translate_personal_phrases.tsv"
  env.version_path = user_dir .. "/input_translate_personal_phrases.version"
  env.version = read_first_line(env.version_path)
  env.phrases = load_phrases(env.phrase_path)
  env.next_refresh = os.time() + REFRESH_INTERVAL_SECONDS
end

function M.func(input, segment, env)
  refresh(env)
  local entries = env.phrases[normalize_code(input)]
  if not entries then
    return
  end
  -- Newer learned variants win ties while all stay ahead of the main lexicon.
  for index = #entries, 1, -1 do
    local candidate = Candidate(
      "personal_phrase",
      segment.start,
      segment._end,
      entries[index],
      ""
    )
    candidate.quality = 1000 + index
    yield(candidate)
  end
end

function M.fini(env)
  env.phrases = nil
end

return M
