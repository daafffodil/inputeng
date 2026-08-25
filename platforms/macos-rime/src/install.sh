#!/bin/bash
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RIME_DIR="${HOME}/Library/Rime"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${RIME_DIR}/backup-inputeng-${STAMP}"

mkdir -p "${RIME_DIR}/lua"

backup_and_copy() {
  relative="$1"
  source_file="${SCRIPT_DIR}/${relative}"
  target_file="${RIME_DIR}/${relative}"

  if [ -e "${target_file}" ]; then
    mkdir -p "${BACKUP_DIR}/$(dirname -- "${relative}")"
    cp -p "${target_file}" "${BACKUP_DIR}/${relative}"
  fi

  mkdir -p "$(dirname -- "${target_file}")"
  cp -p "${source_file}" "${target_file}"
}

backup_and_copy "bilingual_pinyin.schema.yaml"
backup_and_copy "bilingual_english.tsv"
backup_and_copy "common_gloss_overrides.tsv"
backup_and_copy "lua/bilingual_comment.lua"

DEFAULT_CUSTOM="${RIME_DIR}/default.custom.yaml"
SQUIRREL_ROOT="/Library/Input Methods/Squirrel.app/Contents"
RIME_DEPLOYER="${SQUIRREL_ROOT}/MacOS/rime_deployer"

if [ -x "${RIME_DEPLOYER}" ]; then
  if [ -e "${DEFAULT_CUSTOM}" ]; then
    mkdir -p "${BACKUP_DIR}"
    cp -p "${DEFAULT_CUSTOM}" "${BACKUP_DIR}/default.custom.yaml"
  fi
  # Use Rime's own YAML-aware tool so an existing schema list is merged safely.
  (
    cd "${RIME_DIR}"
    DYLD_LIBRARY_PATH="${SQUIRREL_ROOT}/Frameworks" \
      "${RIME_DEPLOYER}" --add-schema bilingual_pinyin
  )
elif [ ! -e "${DEFAULT_CUSTOM}" ]; then
  cat > "${DEFAULT_CUSTOM}" <<'EOF'
patch:
  schema_list/+:
    - schema: bilingual_pinyin
EOF
elif grep -Eq 'schema:[[:space:]]*bilingual_pinyin([[:space:]]|$)' "${DEFAULT_CUSTOM}"; then
  : # Already enabled.
else
  # Do not guess how to merge an existing user configuration. Preserve it and
  # provide a tiny snippet instead, avoiding duplicate YAML keys or lost schemes.
  mkdir -p "${BACKUP_DIR}"
  cp -p "${DEFAULT_CUSTOM}" "${BACKUP_DIR}/default.custom.yaml"
  cat > "${RIME_DIR}/bilingual_default_patch.txt" <<'EOF'
请把下面两行合并到 default.custom.yaml 的 patch: 下面：

  schema_list/+:
    - schema: bilingual_pinyin
EOF
  echo
  echo "检测到你已有 ${DEFAULT_CUSTOM}，为避免破坏原配置，安装器没有修改它。"
  echo "请按照 ${RIME_DIR}/bilingual_default_patch.txt 的内容手动添加双语拼音方案。"
fi

SQUIRREL_BIN="${SQUIRREL_ROOT}/MacOS/Squirrel"
if [ -x "${SQUIRREL_BIN}" ]; then
  "${SQUIRREL_BIN}" --reload >/dev/null 2>&1 || true
fi

echo
echo "inputeng 文件已安装到：${RIME_DIR}"
if [ -d "${BACKUP_DIR}" ]; then
  echo "被替换文件的备份：${BACKUP_DIR}"
fi
echo "接下来在鼠须管菜单中选择『重新部署』，再按 Control+反引号 选择『inputeng』。"
