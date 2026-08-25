-- Commit plain English while showing a short Simplified Chinese gloss.
--
-- Automatic English candidates are offered only when the full input cannot be
-- segmented as normal Pinyin and the complete word already has a local or AI
-- gloss. An unfinished Pinyin tail such as "cesh" or "erqiet" must stay on the
-- Chinese path instead of being mistaken for raw English.

local M = {}

local RUNTIME_REFRESH_SECONDS = 1
local MIN_AUTO_LENGTH = 3

local PINYIN_SYLLABLES = {}
local PINYIN_PREFIXES = {}
for syllable in ([=[
a ai an ang ao e ei en eng er o ou
ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
fa fan fang fei fen feng fiao fo fou fu
ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
ha hai han hang hao he hei hen heng hm hng hong hou hu hua huai huan huang hui hun huo
ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo
la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve
ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
na nai nan nang nao ne nei nen neng ng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve
pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
wa wai wan wang wei wen weng wo wu
xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
]=]):gmatch("%S+") do
  PINYIN_SYLLABLES[syllable] = true
  for width = 1, #syllable - 1 do
    PINYIN_PREFIXES[syllable:sub(1, width)] = true
  end
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
      local english, chinese = normalized:match("^([^\t]+)\t(.+)$")
      if english and chinese and dictionary[english] == nil then
        dictionary[english] = chinese
      end
    end
  end
  file:close()
  return dictionary
end

local function is_full_pinyin(input)
  local length = #input
  if length == 0 or input:find("[^a-z]") then
    return false
  end
  local reachable = { [0] = true }
  for start = 0, length - 1 do
    if reachable[start] then
      for width = 1, 6 do
        local finish = start + width
        if finish <= length and PINYIN_SYLLABLES[input:sub(start + 1, finish)] then
          reachable[finish] = true
        end
      end
    end
  end
  return reachable[length] == true
end

local function has_incomplete_pinyin_tail(input)
  local length = #input
  if length == 0 or input:find("[^a-z]") then
    return false
  end
  local reachable = { [0] = true }
  for start = 0, length - 1 do
    if reachable[start] then
      local tail = input:sub(start + 1)
      if PINYIN_PREFIXES[tail] then
        return true
      end
      for width = 1, 6 do
        local finish = start + width
        if finish <= length and PINYIN_SYLLABLES[input:sub(start + 1, finish)] then
          reachable[finish] = true
        end
      end
    end
  end
  return false
end

local function refresh_ai_cache(env)
  local now = os.time()
  if now < env.next_runtime_refresh then
    return
  end
  env.next_runtime_refresh = now + RUNTIME_REFRESH_SECONDS
  env.ai_enabled = file_exists(env.ai_enabled_path)
  if not env.ai_enabled then
    return
  end
  local version = read_first_line(env.ai_version_path)
  if version ~= env.ai_version then
    env.ai_dictionary = load_tsv(env.ai_cache_path)
    env.ai_version = version
  end
end

local function queue_missing(env, word)
  if not env.ai_enabled or env.queued[word] then
    return
  end
  local file = io.open(env.missing_path, "a")
  if not file then
    return
  end
  file:write(word, "\n")
  file:close()
  env.queued[word] = true
end

function M.init(env)
  local user_dir = rime_api.get_user_data_dir()
  env.local_dictionary = load_tsv(user_dir .. "/english_chinese.tsv")
  env.ai_cache_path = user_dir .. "/input_translate_ai_chinese_cache.tsv"
  env.ai_version_path = user_dir .. "/input_translate_ai_chinese_cache.version"
  env.ai_enabled_path = user_dir .. "/input_translate_ai_enabled"
  env.missing_path = user_dir .. "/input_translate_english_missing.txt"
  env.ai_enabled = file_exists(env.ai_enabled_path)
  env.ai_version = read_first_line(env.ai_version_path)
  env.ai_dictionary = load_tsv(env.ai_cache_path)
  env.next_runtime_refresh = os.time() + RUNTIME_REFRESH_SECONDS
  env.queued = {}
  env.commit_connection = env.engine.context.commit_notifier:connect(function(context)
    local text = context:get_commit_text() or ""
    local lookup = text:lower()
    if #lookup >= MIN_AUTO_LENGTH
        and not lookup:find("[^a-z'-]")
        and not is_full_pinyin(lookup)
        and not has_incomplete_pinyin_tail(lookup)
        and not (env.local_dictionary or {})[lookup]
        and not (env.ai_dictionary or {})[lookup] then
      queue_missing(env, lookup)
    end
  end)
end

function M.func(input, segment, env)
  if not input or #input < MIN_AUTO_LENGTH or input:find("[^A-Za-z'-]") then
    return
  end

  local lookup = input:lower()
  if is_full_pinyin(lookup) then
    return
  end

  refresh_ai_cache(env)
  local chinese = (env.local_dictionary or {})[lookup]
  if (not chinese or chinese == "") and has_incomplete_pinyin_tail(lookup) then
    return
  end
  if not chinese or chinese == "" then
    chinese = (env.ai_dictionary or {})[lookup]
  end
  if not chinese or chinese == "" then
    return
  end

  local candidate = Candidate("english", segment.start, segment._end, input, chinese)
  candidate.quality = 100
  yield(candidate)
end

function M.fini(env)
  if env.commit_connection then env.commit_connection:disconnect() end
  env.commit_connection = nil
  env.local_dictionary = nil
  env.ai_dictionary = nil
  env.queued = nil
end

return M
