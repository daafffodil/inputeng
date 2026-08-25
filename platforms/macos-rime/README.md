# inputeng / macOS Rime

## 目标

在 macOS 的鼠须管输入法中，为普通简体拼音候选追加统一短英文释义；保持中文候选的上屏内容、排序和输入习惯不变。

## MVP 结构

- `src/bilingual_pinyin.schema.yaml`：基于鼠须管自带的朙月拼音简体方案。
- `src/lua/bilingual_comment.lua`：按候选文本查询本地 TSV，并只修改候选 `comment`。
- `scripts/build_dictionary.py`：把 CC-CEDICT 转换成适合候选窗口的短释义。
- `src/install.sh`、`src/uninstall.sh`：Mac 安装和卸载脚本。
- `package/`：由构建脚本生成的临时目录，不提交到 Git。
- `dist/`：最终可交付 ZIP。

## 构建词典

```powershell
python scripts/build_dictionary.py cedict_1_0_ts_utf-8_mdbg.txt.gz ../../shared/dictionary/bilingual_english.tsv
python scripts/package.py
```

`package.py` 会把共享词典和最新源码同步到安装包暂存目录，再把 ZIP 输出到项目根目录的 `dist/macos/`。

## MVP 边界

- 当前 Mac 安装包不启用 AI 或在线翻译；Lua 已兼容以后加入本机后台缓存。
- 不翻译没有完整命中词典的长句。
- 不修改鼠须管源码和候选窗口样式。
- 首轮需要在真实 Mac 上验证安装、部署和显示效果。

## 后续候选功能（暂不开发）

- 本地统计用户实际上屏的中文词语及词频。实现时应监听 Rime 的真实上屏／提交事件，而不是只统计空格键，以免漏掉数字键、回车或鼠标选词；统计数据只保存在用户 Mac 本地。
