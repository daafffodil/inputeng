# inputeng for macOS v0.6.1

macOS 版现在与 Windows 版共用同一套 Rime 核心、中文词库、双向离线词典和 Lua 行为。鼠须管只负责 macOS 候选窗口与上屏。

## 系统要求

- macOS 13 或更高版本。
- 官方鼠须管 1.1.2 或更新正式版；需要包含 `librime-lua`。近期官方安装包已经随附 Lua 插件。

鼠须管下载：<https://github.com/rime/squirrel/releases/latest>

首次安装鼠须管后，请按官方提示注销当前 macOS 账户并重新登录，再安装 inputeng。

## 与 Windows 版一致的核心能力

- 173,035 条高频简体中文核心词库。
- 全拼与搜狗双拼，按 `F4` 直接切换。
- 中文候选显示短英文；不能完整解析为拼音的英文显示短中文。
- 第一次手动组合出的中文短语会保存在本机，下次直接成为候选。
- 离线词典优先；中译英 59,872 条，英译中 58,129 条。
- 可选 DeepSeek 缺词翻译，停顿后由本机 LaunchAgent 在后台处理，不阻塞 Rime。
- 可设置玫粉色候选强调色、中文候选字号和英文小字字号。

## 安装

1. 完整解压 ZIP，不要直接在压缩包预览中运行脚本。
2. 打开“终端”，输入 `bash `（末尾保留一个空格），把 `install.sh` 拖入终端并按回车；也可以在当前目录运行：

   ```bash
   bash install.sh
   ```

3. 安装器会复制文件、加入全拼和搜狗双拼方案、安装本机后台 worker 并让鼠须管重新加载。
4. 在鼠须管中选择 **inputeng**；按 `F4` 在全拼与搜狗双拼间切换。

安装器不会写入任何作者 API Key，也不会读取应用正文或剪贴板。

## 设置与 AI 翻译

安装结束后运行：

```bash
open "$HOME/Library/Application Support/inputeng/settings.command"
```

设置入口可以：

- 修改强调色、中文候选字号和英文小字字号；
- 查看词库总量和筛选说明；
- 填写或停用自己的 DeepSeek API Key。

API Key 保存到当前 macOS 账户的“钥匙串”，不会以明文写入 Rime 目录、源码或发布包。只有离线词典仍然缺失的短词会发送到 DeepSeek；结果缓存在 `~/Library/Rime`。

> 鼠须管的候选外观属于全局前端配置。因此 inputeng 的强调色和字号会同时影响该鼠须管实例中的其他 Rime 方案。输入逻辑、词库与个人短语仍只属于 inputeng 方案。

## 已知边界

- macOS 与 Windows 已实现源码级核心功能一致，但 macOS 版仍需要不同型号的真实 Mac 做最终视觉和安装验收。
- Rime Lua 无法在没有新按键时主动重绘静止的候选页；AI 新结果会在下一次候选刷新时出现。
- GitHub 下载的 shell 脚本没有 Apple Developer 签名。如果 Finder 阻止直接打开 `.command`，请按上述方式在终端中运行。

## 卸载

```bash
bash uninstall.sh
```

卸载器会恢复安装前被替换的同名 Rime 文件；用户后来修改过的文件会保留。个人短语、AI 缓存、外观偏好和钥匙串 Key 默认不删除。
