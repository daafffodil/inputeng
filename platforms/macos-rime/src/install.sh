#!/bin/bash
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RIME_DIR="${INPUTENG_RIME_DIR:-${HOME}/Library/Rime}"
STATE_ROOT="${INPUTENG_STATE_ROOT:-${HOME}/Library/Application Support/inputeng}"
LAUNCH_AGENTS_DIR="${INPUTENG_LAUNCH_AGENTS_DIR:-${HOME}/Library/LaunchAgents}"
SQUIRREL_ROOT="${INPUTENG_SQUIRREL_ROOT:-/Library/Input Methods/Squirrel.app/Contents}"
RIME_DEPLOYER="${SQUIRREL_ROOT}/MacOS/rime_deployer"
SQUIRREL_BIN="${SQUIRREL_ROOT}/MacOS/Squirrel"
LABEL="io.github.daafffodil.inputeng.worker"
PLIST="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
ORIGINAL_INDEX="${STATE_ROOT}/original-files.tsv"
MANIFEST="${STATE_ROOT}/install-manifest.tsv"
ORIGINAL_ROOT="${STATE_ROOT}/original-rime-files"

if [ ! -x "${RIME_DEPLOYER}" ] && [ "${INPUTENG_ALLOW_MISSING_SQUIRREL:-0}" != "1" ]; then
  echo "没有找到鼠须管。请先从 https://github.com/rime/squirrel/releases/latest 安装近期正式版。" >&2
  echo "首次安装鼠须管后，macOS 通常要求注销当前账户并重新登录。" >&2
  exit 20
fi

mkdir -p "${RIME_DIR}/lua" "${STATE_ROOT}/helper" "${LAUNCH_AGENTS_DIR}" "${ORIGINAL_ROOT}"
touch "${ORIGINAL_INDEX}"

sha256_file() { /usr/bin/shasum -a 256 "$1" | awk '{print $1}'; }

original_recorded() {
  awk -F '\t' -v wanted="$1" '$1 == wanted { found=1 } END { exit(found ? 0 : 1) }' "${ORIGINAL_INDEX}"
}

record_original() {
  relative="$1"
  target="${RIME_DIR}/${relative}"
  if original_recorded "${relative}"; then return; fi
  if [ -e "${target}" ]; then
    backup="${ORIGINAL_ROOT}/${relative}"
    mkdir -p "$(dirname -- "${backup}")"
    cp -p "${target}" "${backup}"
    printf '%s\t1\t%s\n' "${relative}" "$(sha256_file "${target}")" >> "${ORIGINAL_INDEX}"
  else
    printf '%s\t0\t-\n' "${relative}" >> "${ORIGINAL_INDEX}"
  fi
}

managed_files='bilingual_pinyin.schema.yaml
bilingual_sogou.schema.yaml
input_translate_core.dict.yaml
cn_dicts/8105.dict.yaml
cn_dicts/base.dict.yaml
cn_dicts/modern.dict.yaml
bilingual_english.tsv
common_gloss_overrides.tsv
english_chinese.tsv
lua/bilingual_comment.lua
lua/english_comment_translator.lua
lua/english_mode_filter.lua
lua/personal_phrase_processor.lua
lua/personal_phrase_translator.lua
lua/schema_toggle_processor.lua'

manifest_tmp="${MANIFEST}.tmp.$$"
: > "${manifest_tmp}"
printf '%s\n' "${managed_files}" | while IFS= read -r relative; do
  [ -n "${relative}" ] || continue
  source_file="${SCRIPT_DIR}/${relative}"
  target_file="${RIME_DIR}/${relative}"
  if [ ! -f "${source_file}" ]; then
    echo "安装包缺少文件：${relative}" >&2
    exit 30
  fi
  record_original "${relative}"
  mkdir -p "$(dirname -- "${target_file}")"
  cp -p "${source_file}" "${target_file}"
  printf '%s\t%s\n' "${relative}" "$(sha256_file "${target_file}")" >> "${manifest_tmp}"
done
mv "${manifest_tmp}" "${MANIFEST}"

# Install platform helpers outside the Rime directory. API keys are never
# copied here; configure-deepseek.command stores them in the macOS Keychain.
cp -p "${SCRIPT_DIR}/helper/apply-theme.sh" "${STATE_ROOT}/helper/apply-theme.sh"
cp -p "${SCRIPT_DIR}/helper/worker.sh" "${STATE_ROOT}/helper/worker.sh"
cp -p "${SCRIPT_DIR}/helper/worker-json.js" "${STATE_ROOT}/helper/worker-json.js"
cp -p "${SCRIPT_DIR}/settings.command" "${STATE_ROOT}/settings.command"
cp -p "${SCRIPT_DIR}/configure-deepseek.command" "${STATE_ROOT}/configure-deepseek.command"
chmod 755 "${STATE_ROOT}/helper/apply-theme.sh" "${STATE_ROOT}/helper/worker.sh" \
  "${STATE_ROOT}/settings.command" "${STATE_ROOT}/configure-deepseek.command"
chmod 644 "${STATE_ROOT}/helper/worker-json.js"

if [ "${INPUTENG_NO_LAUNCH_AGENT:-0}" != "1" ]; then
  cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>${STATE_ROOT}/helper/worker.sh</string></array>
  <key>StartInterval</key><integer>2</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
  /bin/launchctl bootout "gui/${UID}" "${PLIST}" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "gui/${UID}" "${PLIST}" >/dev/null 2>&1 || true
fi

if [ -x "${RIME_DEPLOYER}" ]; then
  (
    cd "${RIME_DIR}"
    DYLD_LIBRARY_PATH="${SQUIRREL_ROOT}/Frameworks" \
      "${RIME_DEPLOYER}" --add-schema bilingual_pinyin bilingual_sogou
  )
else
  default_custom="${RIME_DIR}/default.custom.yaml"
  if [ ! -f "${default_custom}" ]; then
    cat > "${default_custom}" <<'EOF'
patch:
  schema_list/+:
    - schema: bilingual_pinyin
    - schema: bilingual_sogou
EOF
  fi
fi

INPUTENG_RIME_DIR="${RIME_DIR}" INPUTENG_STATE_ROOT="${STATE_ROOT}" \
  INPUTENG_SQUIRREL_ROOT="${SQUIRREL_ROOT}" INPUTENG_SKIP_RELOAD="${INPUTENG_SKIP_RELOAD:-0}" \
  "${STATE_ROOT}/helper/apply-theme.sh" || true

if [ "${INPUTENG_SKIP_RELOAD:-0}" != "1" ] && [ -x "${SQUIRREL_BIN}" ]; then
  "${SQUIRREL_BIN}" --reload >/dev/null 2>&1 || true
fi

echo
echo "inputeng 0.6.0 已安装到：${RIME_DIR}"
echo "全拼和搜狗双拼已启用；按 F4 可直接切换。"
echo "设置入口：${STATE_ROOT}/settings.command"
echo "也可以在终端运行：open \"${STATE_ROOT}/settings.command\""
echo "DeepSeek 为可选功能，必须由每位用户自行填写自己的 API Key。"
