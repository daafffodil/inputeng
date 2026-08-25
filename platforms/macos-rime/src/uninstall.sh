#!/bin/bash
set -eu

RIME_DIR="${HOME}/Library/Rime"

rm -f "${RIME_DIR}/bilingual_pinyin.schema.yaml"
rm -f "${RIME_DIR}/bilingual_english.tsv"
rm -f "${RIME_DIR}/common_gloss_overrides.tsv"
rm -f "${RIME_DIR}/lua/bilingual_comment.lua"

echo "核心文件已删除。"
echo "请打开 ${RIME_DIR}/default.custom.yaml，删除 bilingual_pinyin 对应的两行，然后重新部署鼠须管。"
