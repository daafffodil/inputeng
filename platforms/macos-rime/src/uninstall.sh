#!/bin/bash
set -eu

RIME_DIR="${INPUTENG_RIME_DIR:-${HOME}/Library/Rime}"
STATE_ROOT="${INPUTENG_STATE_ROOT:-${HOME}/Library/Application Support/inputeng}"
LAUNCH_AGENTS_DIR="${INPUTENG_LAUNCH_AGENTS_DIR:-${HOME}/Library/LaunchAgents}"
SQUIRREL_ROOT="${INPUTENG_SQUIRREL_ROOT:-/Library/Input Methods/Squirrel.app/Contents}"
LABEL="io.github.daafffodil.inputeng.worker"
PLIST="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
MANIFEST="${STATE_ROOT}/install-manifest.tsv"
ORIGINAL_INDEX="${STATE_ROOT}/original-files.tsv"
ORIGINAL_ROOT="${STATE_ROOT}/original-rime-files"

sha256_file() { /usr/bin/shasum -a 256 "$1" | awk '{print $1}'; }

if [ -f "${PLIST}" ]; then
  /bin/launchctl bootout "gui/${UID}" "${PLIST}" >/dev/null 2>&1 || true
  rm -f "${PLIST}"
fi

if [ -f "${MANIFEST}" ]; then
  while IFS=$'\t' read -r relative installed_hash; do
    [ -n "${relative}" ] || continue
    target="${RIME_DIR}/${relative}"
    if [ ! -e "${target}" ]; then continue; fi
    current_hash="$(sha256_file "${target}")"
    if [ "${current_hash}" != "${installed_hash}" ]; then
      echo "保留用户修改过的文件：${target}"
      continue
    fi
    original_state="$(awk -F '\t' -v wanted="${relative}" '$1 == wanted { print $2; exit }' "${ORIGINAL_INDEX}" 2>/dev/null || true)"
    if [ "${original_state}" = "1" ] && [ -f "${ORIGINAL_ROOT}/${relative}" ]; then
      cp -p "${ORIGINAL_ROOT}/${relative}" "${target}"
    else
      rm -f "${target}"
    fi
  done < "${MANIFEST}"
fi

if [ -x "${STATE_ROOT}/helper/apply-theme.sh" ]; then
  INPUTENG_RIME_DIR="${RIME_DIR}" INPUTENG_STATE_ROOT="${STATE_ROOT}" \
    INPUTENG_SQUIRREL_ROOT="${SQUIRREL_ROOT}" INPUTENG_SKIP_RELOAD=1 \
    "${STATE_ROOT}/helper/apply-theme.sh" --remove || true
fi

default_custom="${RIME_DIR}/default.custom.yaml"
if [ -f "${default_custom}" ]; then
  temporary="${default_custom}.inputeng.$$"
  awk '
    !/^[[:space:]]*-[[:space:]]*schema:[[:space:]]*bilingual_pinyin([[:space:]]|$)/ &&
    !/^[[:space:]]*-[[:space:]]*schema:[[:space:]]*bilingual_sogou([[:space:]]|$)/ { print }
  ' "${default_custom}" > "${temporary}"
  mv "${temporary}" "${default_custom}"
fi

rm -rf "${STATE_ROOT}/helper"
rm -f "${STATE_ROOT}/settings.command" "${STATE_ROOT}/configure-deepseek.command" \
  "${STATE_ROOT}/install-manifest.tsv"

if [ "${INPUTENG_SKIP_RELOAD:-0}" != "1" ]; then
  squirrel="${SQUIRREL_ROOT}/MacOS/Squirrel"
  if [ -x "${squirrel}" ]; then "${squirrel}" --reload >/dev/null 2>&1 || true; fi
fi

echo "inputeng 核心文件已卸载。"
echo "个人短语、AI 缓存、外观偏好和钥匙串中的 API Key 默认保留，便于以后重装。"
echo "如需彻底清理，可删除 ${STATE_ROOT}，并从钥匙串中删除 io.github.daafffodil.inputeng.deepseek。"
