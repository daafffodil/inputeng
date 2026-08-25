-- Toggle directly between inputeng full pinyin and Sogou double pinyin.
-- F4 is removed from Rime's global switcher hotkeys by the installer, so this
-- processor can switch schemas without opening the standard scheme menu.

local M = {}

local ACCEPTED = 1
local NOOP = 2

function M.func(key, env)
  if key:repr() ~= "F4" or key:release() then
    return NOOP
  end

  local current = env.engine.schema.schema_id
  local target = current == "bilingual_sogou"
      and "bilingual_pinyin"
      or "bilingual_sogou"

  -- Recent librime-lua exposes ConcreteEngine::ApplySchema as apply_schema
  -- and expects a Schema object rather than a schema-id string.
  env.engine:apply_schema(Schema(target))
  return ACCEPTED
end

return M
