-- When the dedicated English candidate wins the merged translation stream,
-- keep that page English-only instead of exposing loose Pinyin fragments.

local M = {}

function M.func(input, _)
  local english_mode = false
  local first = true
  for candidate in input:iter() do
    if first then
      english_mode = candidate.type == "english"
      first = false
    end
    if not english_mode or candidate.type == "english" then
      yield(candidate)
    end
  end
end

return M
