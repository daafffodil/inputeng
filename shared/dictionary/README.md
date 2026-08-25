# Shared dictionary

`bilingual_english.tsv` 是 macOS 与 Windows 版本共用的离线中英候选查询表。用户界面只提供简体中文输入；繁体词形仅作为 Rime 候选底层文本的内部匹配别名，不提供繁体输入方案。

- 来源：CC-CEDICT，MDBG 发布；
- 当前源数据日期：2026-08-23；
- 当前查询键：197,816 条（含内部繁体别名）；
- 数据许可：CC BY-SA 4.0；
- 英文只作为候选注释，不作为上屏文本。

其他共享数据：

- `common_gloss_overrides.tsv`：少量常用义项优先规则，例如“东西”优先显示 `thing, stuff`。
- `english_chinese.tsv`：从 ECDICT 提取的常用英中短释义，用于英文候选旁的中文小字。
- `modern_common_words.txt`：受控现代中文补充词的人工审核入口，Windows 构建只收入同时通过上游来源交叉核对的词。

Mac 构建脚本位于 `platforms/macos-rime/scripts/build_dictionary.py`。
