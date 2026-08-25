# inputeng / macOS Rime

## 状态

鼠须管扩展 v0.6.1。macOS 与 Windows 现在共用同一套核心方案、173,035 条简体中文词库、双向离线释义、个人短语学习和 DeepSeek 缺词队列；平台差异只保留在安装、外观设置、密钥存储和后台 worker。

发布包：`dist/macos/inputeng-macos-v0.6.1.zip`

## 架构

- Rime 的 engine、translators、filters、词典与 Lua 从 `platforms/windows/src/` 共用；打包时只去掉 Weasel 专用的候选窗 `style` 段，改由鼠须管全局外观补丁管理。
- `scripts/package.py` 调用同一套运行时词典生成逻辑，生成相同的中译英表，并复制共享英译中表。
- `src/install.sh` 使用鼠须管自带的 `rime_deployer --add-schema` 安全加入全拼和搜狗双拼。
- `src/helper/worker.sh` 由用户级 LaunchAgent 定时运行；网络请求在 Rime 进程外执行。
- `src/helper/worker-json.js` 使用 macOS 自带 JXA 生成和解析 JSON，不要求 Homebrew、Node.js 或 Python。
- API Key 使用 macOS Keychain 保存；配置和缓存不进入仓库或发布包。
- `src/settings.command` 提供 macOS 原生对话框式设置入口。

## 构建与验证

```powershell
python platforms/macos-rime/scripts/package.py
python platforms/macos-rime/scripts/test_package.py
```

GitHub Actions 在 `macos-latest` 上执行 shell 语法、JXA 自检、YAML、安装/卸载隔离测试和 ZIP 权限验证。真实输入体验仍需在安装了鼠须管的 Mac 上验收。
