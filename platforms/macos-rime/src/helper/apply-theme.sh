#!/bin/bash
set -eu

RIME_DIR="${INPUTENG_RIME_DIR:-${HOME}/Library/Rime}"
STATE_ROOT="${INPUTENG_STATE_ROOT:-${HOME}/Library/Application Support/inputeng}"
TARGET="${RIME_DIR}/squirrel.custom.yaml"
SETTINGS="${STATE_ROOT}/appearance.conf"
MARKER_BEGIN="# >>> inputeng:theme"
MARKER_END="# <<< inputeng:theme"

mkdir -p "${RIME_DIR}" "${STATE_ROOT}"

strip_block() {
  input="$1"
  output="$2"
  awk -v begin="${MARKER_BEGIN}" -v end="${MARKER_END}" '
    index($0, begin) { skipping=1; next }
    index($0, end) { skipping=0; next }
    !skipping { print }
  ' "${input}" > "${output}"
}

reload_squirrel() {
  if [ "${INPUTENG_SKIP_RELOAD:-0}" = "1" ]; then
    return
  fi
  squirrel="${INPUTENG_SQUIRREL_ROOT:-/Library/Input Methods/Squirrel.app/Contents}/MacOS/Squirrel"
  if [ -x "${squirrel}" ]; then
    "${squirrel}" --reload >/dev/null 2>&1 || true
  fi
}

if [ "${1:-}" = "--remove" ]; then
  if [ -f "${TARGET}" ]; then
    temporary="${TARGET}.inputeng.$$"
    strip_block "${TARGET}" "${temporary}"
    mv "${temporary}" "${TARGET}"
  fi
  reload_squirrel
  exit 0
fi

accent="#EC4899"
candidate_font=16
comment_font=12
if [ -f "${SETTINGS}" ]; then
  saved_accent="$(awk -F= '$1 == "accent" { print $2; exit }' "${SETTINGS}")"
  saved_candidate="$(awk -F= '$1 == "candidate_font" { print $2; exit }' "${SETTINGS}")"
  saved_comment="$(awk -F= '$1 == "comment_font" { print $2; exit }' "${SETTINGS}")"
  case "${saved_accent}" in \#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) accent="${saved_accent}" ;; esac
  case "${saved_candidate}" in ''|*[!0-9]*) ;; *) [ "${saved_candidate}" -ge 12 ] && [ "${saved_candidate}" -le 24 ] && candidate_font="${saved_candidate}" ;; esac
  case "${saved_comment}" in ''|*[!0-9]*) ;; *) [ "${saved_comment}" -ge 8 ] && [ "${saved_comment}" -le 18 ] && comment_font="${saved_comment}" ;; esac
fi

hex="$(printf '%s' "${accent#\#}" | tr '[:lower:]' '[:upper:]')"
red="$(printf '%s' "${hex}" | cut -c1-2)"
green="$(printf '%s' "${hex}" | cut -c3-4)"
blue="$(printf '%s' "${hex}" | cut -c5-6)"
# Squirrel color values use ABGR ordering.
accent_abgr="0xff${blue}${green}${red}"

block="${STATE_ROOT}/squirrel-theme.block"
cat > "${block}" <<EOF
  ${MARKER_BEGIN}
  "style/color_scheme": inputeng_light
  "style/color_scheme_dark": inputeng_dark
  "style/candidate_list_layout": stacked
  "style/inline_preedit": true
  "style/candidate_format": "[label]. [candidate] [comment]"
  "style/font_point": ${candidate_font}
  "style/comment_font_point": ${comment_font}
  "preset_color_schemes/inputeng_light/name": "inputeng Light"
  "preset_color_schemes/inputeng_light/back_color": 0xffffffff
  "preset_color_schemes/inputeng_light/border_color": 0xffe5e7eb
  "preset_color_schemes/inputeng_light/text_color": 0xff111827
  "preset_color_schemes/inputeng_light/candidate_text_color": 0xff111827
  "preset_color_schemes/inputeng_light/label_color": 0xffafaaa3
  "preset_color_schemes/inputeng_light/comment_text_color": 0xff988f8a
  "preset_color_schemes/inputeng_light/hilited_candidate_text_color": 0xffffffff
  "preset_color_schemes/inputeng_light/hilited_candidate_label_color": 0xffffffff
  "preset_color_schemes/inputeng_light/hilited_comment_text_color": 0xffffffff
  "preset_color_schemes/inputeng_light/hilited_candidate_back_color": ${accent_abgr}
  "preset_color_schemes/inputeng_dark/name": "inputeng Dark"
  "preset_color_schemes/inputeng_dark/back_color": 0xff242120
  "preset_color_schemes/inputeng_dark/border_color": 0xff43403c
  "preset_color_schemes/inputeng_dark/text_color": 0xfff4f3f1
  "preset_color_schemes/inputeng_dark/candidate_text_color": 0xfff4f3f1
  "preset_color_schemes/inputeng_dark/label_color": 0xffa6a09a
  "preset_color_schemes/inputeng_dark/comment_text_color": 0xffa6a09a
  "preset_color_schemes/inputeng_dark/hilited_candidate_text_color": 0xffffffff
  "preset_color_schemes/inputeng_dark/hilited_candidate_label_color": 0xffffffff
  "preset_color_schemes/inputeng_dark/hilited_comment_text_color": 0xffffffff
  "preset_color_schemes/inputeng_dark/hilited_candidate_back_color": ${accent_abgr}
  ${MARKER_END}
EOF

if [ ! -f "${TARGET}" ]; then
  printf 'patch:\n' > "${TARGET}"
fi

clean="${TARGET}.inputeng.clean.$$"
strip_block "${TARGET}" "${clean}"
if ! grep -Eq '^patch:[[:space:]]*(#.*)?$' "${clean}"; then
  rm -f "${clean}"
  cp "${block}" "${RIME_DIR}/inputeng-squirrel-theme-patch.txt"
  echo "无法安全识别现有 squirrel.custom.yaml 的 patch: 结构。" >&2
  echo "未改动原文件；可把 inputeng-squirrel-theme-patch.txt 的内容合并到 patch: 下。" >&2
  exit 2
fi

temporary="${TARGET}.inputeng.$$"
awk -v block="${block}" '
  BEGIN { inserted=0 }
  {
    print
    if (!inserted && $0 ~ /^patch:[[:space:]]*(#.*)?$/) {
      while ((getline line < block) > 0) print line
      close(block)
      inserted=1
    }
  }
' "${clean}" > "${temporary}"
mv "${temporary}" "${TARGET}"
rm -f "${clean}" "${block}"
reload_squirrel

