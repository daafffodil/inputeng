#!/bin/bash
set -u

RIME_DIR="${INPUTENG_RIME_DIR:-${HOME}/Library/Rime}"
STATE_ROOT="${INPUTENG_STATE_ROOT:-${HOME}/Library/Application Support/inputeng}"
CONFIG="${STATE_ROOT}/deepseek.conf"
JSON_HELPER="${STATE_ROOT}/helper/worker-json.js"
ENABLED="${RIME_DIR}/input_translate_ai_enabled"
LOG="${STATE_ROOT}/worker.log"
LOCK="${STATE_ROOT}/worker.lock"
KEYCHAIN_SERVICE="io.github.daafffodil.inputeng.deepseek"

[ -f "${ENABLED}" ] || exit 0
[ -f "${CONFIG}" ] || exit 0
[ -f "${JSON_HELPER}" ] || exit 0
mkdir -p "${STATE_ROOT}" "${RIME_DIR}"
if ! mkdir "${LOCK}" 2>/dev/null; then exit 0; fi
trap 'rmdir "${LOCK}" >/dev/null 2>&1 || true' EXIT INT TERM

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${LOG}"
  if [ -f "${LOG}" ] && [ "$(wc -c < "${LOG}")" -gt 65536 ]; then
    tail -n 300 "${LOG}" > "${LOG}.tmp" && mv "${LOG}.tmp" "${LOG}"
  fi
}

endpoint="$(awk -F= '$1 == "endpoint" { print substr($0, index($0, "=") + 1); exit }' "${CONFIG}")"
model="$(awk -F= '$1 == "model" { print substr($0, index($0, "=") + 1); exit }' "${CONFIG}")"
case "${endpoint}" in https://*) ;; *) endpoint="https://api.deepseek.com/chat/completions" ;; esac
case "${model}" in ''|*[!A-Za-z0-9._-]*) model="deepseek-v4-flash" ;; esac

secret="$(/usr/bin/security find-generic-password -a "${USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null || true)"
[ -n "${secret}" ] || exit 0

process_job() {
  direction="$1"
  queue="$2"
  cache="$3"
  version="$4"
  offline="$5"
  [ -s "${queue}" ] || return 0
  modified="$(/usr/bin/stat -f '%m' "${queue}" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  [ $((now - modified)) -ge 1 ] || return 0

  work="${queue}.work.$$"
  if ! mv "${queue}" "${work}" 2>/dev/null; then return 0; fi
  body="${STATE_ROOT}/request.$$.json"
  terms="${STATE_ROOT}/terms.$$.json"
  response="${STATE_ROOT}/response.$$.json"
  trap 'rm -f "${work}" "${body}" "${terms}" "${response}"; rmdir "${LOCK}" >/dev/null 2>&1 || true' EXIT INT TERM

  count="$(/usr/bin/osascript -l JavaScript "${JSON_HELPER}" prepare "${direction}" "${work}" "${cache}" "${offline}" "${model}" "${body}" "${terms}" "${queue}" 2>>"${LOG}" || echo 0)"
  rm -f "${work}"
  case "${count}" in ''|0|*[!0-9]*) rm -f "${body}" "${terms}"; return 0 ;; esac

  http_code="$(
    printf 'header = "Authorization: Bearer %s"\n' "${secret}" |
      /usr/bin/curl --config - --silent --show-error --max-time 20 \
        --output "${response}" --write-out '%{http_code}' \
        --header 'Content-Type: application/json; charset=utf-8' \
        --request POST --data-binary "@${body}" "${endpoint}" 2>>"${LOG}" || true
  )"
  if [ "${http_code}" != "200" ]; then
    /usr/bin/osascript -l JavaScript "${JSON_HELPER}" requeue "${terms}" "${queue}" >/dev/null 2>>"${LOG}" || true
    log "API request failed for ${direction} (HTTP ${http_code:-network})."
    rm -f "${body}" "${terms}" "${response}"
    return 0
  fi

  if added="$(/usr/bin/osascript -l JavaScript "${JSON_HELPER}" apply "${direction}" "${response}" "${terms}" "${cache}" "${version}" 2>>"${LOG}")"; then
    log "Translated ${added} of ${count} queued ${direction} terms."
  else
    /usr/bin/osascript -l JavaScript "${JSON_HELPER}" requeue "${terms}" "${queue}" >/dev/null 2>>"${LOG}" || true
    log "Invalid API response for ${direction}; queued terms retained."
  fi
  rm -f "${body}" "${terms}" "${response}"
}

process_job "zh-en" \
  "${RIME_DIR}/input_translate_missing.txt" \
  "${RIME_DIR}/input_translate_ai_cache.tsv" \
  "${RIME_DIR}/input_translate_ai_cache.version" \
  "${RIME_DIR}/bilingual_english.tsv"
process_job "en-zh" \
  "${RIME_DIR}/input_translate_english_missing.txt" \
  "${RIME_DIR}/input_translate_ai_chinese_cache.tsv" \
  "${RIME_DIR}/input_translate_ai_chinese_cache.version" \
  "/dev/null"

