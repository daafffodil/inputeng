#!/bin/bash
set -eu

RIME_DIR="${INPUTENG_RIME_DIR:-${HOME}/Library/Rime}"
STATE_ROOT="${INPUTENG_STATE_ROOT:-${HOME}/Library/Application Support/inputeng}"
KEYCHAIN_SERVICE="io.github.daafffodil.inputeng.deepseek"
CONFIG="${STATE_ROOT}/deepseek.conf"
LABEL="io.github.daafffodil.inputeng.worker"

mkdir -p "${RIME_DIR}" "${STATE_ROOT}"

if [ "${1:-}" = "--disable" ]; then
  rm -f "${RIME_DIR}/input_translate_ai_enabled"
  /usr/bin/osascript -e 'display notification "AI 缺词翻译已停用，离线词典仍可正常使用。" with title "inputeng"' >/dev/null 2>&1 || true
  exit 0
fi

if [ -n "${INPUTENG_API_KEY:-}" ]; then
  api_key="${INPUTENG_API_KEY}"
else
  api_key="$(/usr/bin/osascript <<'APPLESCRIPT'
set resultDialog to display dialog "请输入你自己的 DeepSeek API Key。\n\nKey 只会保存到当前 macOS 账户的钥匙串，不会写入 Rime 配置或项目文件。" default answer "" with title "inputeng · AI 翻译" with hidden answer buttons {"取消", "保存"} default button "保存" cancel button "取消"
return text returned of resultDialog
APPLESCRIPT
)"
fi

case "${api_key}" in
  sk-*) ;;
  *)
    /usr/bin/osascript -e 'display alert "API Key 格式不正确" message "DeepSeek API Key 通常以 sk- 开头。" as critical' >/dev/null 2>&1 || true
    exit 2
    ;;
esac

if [ "${INPUTENG_SKIP_KEYCHAIN:-0}" != "1" ]; then
  /usr/bin/security add-generic-password -U -a "${USER}" -s "${KEYCHAIN_SERVICE}" -w "${api_key}" >/dev/null
fi
cat > "${CONFIG}" <<'EOF'
endpoint=https://api.deepseek.com/chat/completions
model=deepseek-v4-flash
EOF
chmod 600 "${CONFIG}"
touch "${RIME_DIR}/input_translate_ai_enabled"

if [ "${INPUTENG_NO_LAUNCH_AGENT:-0}" != "1" ]; then
  /bin/launchctl kickstart -k "gui/${UID}/${LABEL}" >/dev/null 2>&1 || true
fi
/usr/bin/osascript -e 'display notification "已启用；只翻译离线词典仍缺失的短词。" with title "inputeng · DeepSeek"' >/dev/null 2>&1 || true

