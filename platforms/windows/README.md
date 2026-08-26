# Windows

## 状态

小狼毫 / Rime 扩展 v0.6.2 已在 Windows + 小狼毫 0.17.4 开发，并通过自动安装包验证、真实 librime C API 验证与逐键延迟基准测试。

发布包：`dist/windows/inputeng-windows-v0.6.2.zip`

构建完成后以同目录 `.sha256` 文件为准。

## 当前能力

- 一个高频简体中文核心词库，共 173,036 条词和规范汉字读音。
- 全拼与搜狗双拼；`F4` 由 librime 原生 key binder 直接切换，`Ctrl+反引号` 保留标准方案菜单。
- 中文候选旁显示短英文，非拼音英文候选旁显示短中文。
- 连续拼音组句；多片段组合第一次上屏后由 librime 原生用户词典记住。
- WPF 设置界面提供强调色、加减式字号调节；词库页只展示中文核心词库与离线双语释义的总量和筛选依据。
- 已移除词频页面并停止采集上屏词频。
- 输入字母固定留在应用输入框内，候选窗顶部不重复显示。

## 实现路线

- Windows 宿主使用官方小狼毫 0.17.4，不从零开发 TSF 输入法。
- `bilingual_pinyin.schema.yaml` 和 `bilingual_sogou.schema.yaml` 使用 librime 原生 reverse lookup 提供精确离线注释；全拼方案再使用原生 table translator 提供英文直输。
- 构建时把中译英与英译中离线表编译成原生 Rime 词典，Lua 不再加载约 5.9 万条离线释义；搜狗双拼方案为避免短码冲突，不启用英文直输页。
- 候选缺词先写入本机队列，PowerShell worker 等待队列稳定约 500 ms 后批量调用用户配置的 DeepSeek API。
- 每次按键只经过一个轻量 Lua filter，它读取 DeepSeek 动态缓存并排入缺词队列；网络请求不会阻塞 Rime 候选生成线程。
- API Key 由 Windows DPAPI 按当前账户加密，缓存保存在 Rime 用户目录。
- 全新电脑的无人值守安装必须显式传入 `-InstallWeasel -AcceptWeaselDownload -SilentWeaselInstall`；固定下载 URL、版本和 SHA-256 不变。
- 普通安装不再改写小狼毫共用的 TSF 名称或图标，也不再要求注销；Windows 输入法列表显示“小狼毫”不影响 inputeng 方案。
- Rime Lua 无法从外部 worker 主动重绘静止的现有候选页，因此异步结果在下一次候选刷新时出现。商业输入法通常由原生候选 UI 持有异步服务回调，收到云端结果后直接更新当前候选模型。

## 目录

```text
windows/
├─ src/                    # 发布包源文件
│  ├─ cn_dicts/            # 精简简体核心词库
│  ├─ lua/                 # 仅保留 AI 缓存与缺词队列过滤器
│  └─ helper/              # 设置 UI、DeepSeek worker、部署脚本
├─ upstream/               # 固定版本完整 Rime Ice 基础表，仅供再生成
├─ package/                # 构建生成的可安装目录
└─ scripts/
   ├─ package.py           # 构建确定性 ZIP 与 SHA-256
   ├─ smoke_rime.py        # 真实 librime 候选及 F4 切换验证
   └─ test_package.py      # 词典、YAML、ZIP、安装与卸载测试
```

## 构建与验证

```powershell
python platforms/windows/scripts/package.py
python platforms/windows/scripts/test_package.py
python platforms/windows/scripts/smoke_rime.py
python platforms/windows/scripts/benchmark_rime.py --max-p95-ms 5
```

`test_package.py` 需要 `PyYAML==6.0.2`。隔离测试不会改动真实 `%APPDATA%\Rime`；`smoke_rime.py` 和 `benchmark_rime.py` 使用已安装小狼毫的真实 C API，但会复制到独立测试目录，不连接用户正在使用的 LevelDB。

v0.6.2 在小狼毫 0.17.4 的隔离 librime 基准中，逐键处理耗时中位数为 0.32 ms、p95 为 1.19 ms；v0.6.1 基线分别约为 8.86 ms 和 17.13 ms。
