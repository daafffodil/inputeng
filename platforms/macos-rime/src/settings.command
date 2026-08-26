#!/bin/bash
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RIME_DIR="${INPUTENG_RIME_DIR:-${HOME}/Library/Rime}"
STATE_ROOT="${INPUTENG_STATE_ROOT:-${HOME}/Library/Application Support/inputeng}"
APPLY_THEME="${STATE_ROOT}/helper/apply-theme.sh"
CONFIGURE="${STATE_ROOT}/configure-deepseek.command"

if [ ! -x "${APPLY_THEME}" ]; then APPLY_THEME="${SCRIPT_DIR}/helper/apply-theme.sh"; fi
if [ ! -x "${CONFIGURE}" ]; then CONFIGURE="${SCRIPT_DIR}/configure-deepseek.command"; fi

show_dictionary_status() {
  /usr/bin/osascript <<'APPLESCRIPT'
display dialog "中文核心词库：173,036 条\n筛选依据：高频简体基础词、规范汉字读音与受控现代词。\n\n离线双语释义：\n中译英 59,873 条\n英译中 58,129 条\n\nWindows 与 macOS 使用同一套核心 Rime 文件和离线词典。" with title "inputeng · 词库" buttons {"好"} default button "好"
APPLESCRIPT
}

configure_appearance() {
  accent="$(/usr/bin/osascript -e 'text returned of (display dialog "候选强调色（#RRGGBB）" default answer "#EC4899" with title "inputeng · 外观")')"
  candidate="$(/usr/bin/osascript -e 'text returned of (display dialog "中文候选字号（12–24）" default answer "16" with title "inputeng · 外观")')"
  comment="$(/usr/bin/osascript -e 'text returned of (display dialog "英文小字字号（8–18）" default answer "12" with title "inputeng · 外观")')"
  case "${accent}" in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) exit 2 ;; esac
  case "${candidate}" in ''|*[!0-9]*) exit 2 ;; esac
  case "${comment}" in ''|*[!0-9]*) exit 2 ;; esac
  [ "${candidate}" -ge 12 ] && [ "${candidate}" -le 24 ] || exit 2
  [ "${comment}" -ge 8 ] && [ "${comment}" -le 18 ] || exit 2
  mkdir -p "${STATE_ROOT}"
  cat > "${STATE_ROOT}/appearance.conf" <<EOF
accent=${accent}
candidate_font=${candidate}
comment_font=${comment}
EOF
  chmod 600 "${STATE_ROOT}/appearance.conf"
  INPUTENG_RIME_DIR="${RIME_DIR}" INPUTENG_STATE_ROOT="${STATE_ROOT}" "${APPLY_THEME}"
  /usr/bin/osascript -e 'display notification "外观已保存并重新加载。" with title "inputeng"' >/dev/null 2>&1 || true
}

while true; do
  choice="$(/usr/bin/osascript -e 'choose from list {"外观设置", "配置 DeepSeek", "停用 AI 翻译", "查看词库", "退出"} with title "inputeng 设置" with prompt "请选择设置项目" default items {"外观设置"}' | tr -d '\r')"
  case "${choice}" in
    外观设置) configure_appearance ;;
    "配置 DeepSeek") INPUTENG_RIME_DIR="${RIME_DIR}" INPUTENG_STATE_ROOT="${STATE_ROOT}" "${CONFIGURE}" ;;
    "停用 AI 翻译") INPUTENG_RIME_DIR="${RIME_DIR}" INPUTENG_STATE_ROOT="${STATE_ROOT}" "${CONFIGURE}" --disable ;;
    查看词库) show_dictionary_status ;;
    *) exit 0 ;;
  esac
done
