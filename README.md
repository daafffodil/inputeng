# inputeng

[中文](README.md) | [English](README_EN.md)

[![Windows validation](https://github.com/daafffodil/inputeng/actions/workflows/validate.yml/badge.svg)](https://github.com/daafffodil/inputeng/actions/workflows/validate.yml)
[![Latest release](https://img.shields.io/github/v/release/daafffodil/inputeng)](https://github.com/daafffodil/inputeng/releases/latest)
[![Code license: MIT](https://img.shields.io/badge/code%20license-MIT-blue.svg)](LICENSE)

inputeng 是一个基于 Rime 的简体中文输入方案。正常输入中文时，候选词旁会显示简短英文释义；直接输入英文时，也可以显示简短中文释义。选择候选后只上屏原词，旁边的翻译不会进入正文。

![inputeng 候选窗预览](docs/assets/inputeng-preview.png)

> Windows 版已经过真实小狼毫和 librime 验证。macOS 版已经升级到相同核心功能，并通过 macOS GitHub Runner 的安装与脚本测试；候选视觉和实际输入体验仍等待真实 Mac 验收。

## 功能

- 简体中文全拼，候选词旁显示短英文释义。
- 按 `F4` 在全拼和搜狗双拼之间直接切换。
- 输入无法解析为拼音的英文时，显示中文小字并保持英文上屏。
- 离线词典优先，不开启 AI 也能正常使用。
- 第一次成功组合出的中文短语会保存在本机，下一次可以直接候选。
- 可调整候选强调色、中文候选字号和英文小字字号。
- 可选 DeepSeek 缺词翻译；只处理离线词典没有的短词。

## 下载与安装

### Windows

[下载最新版本](https://github.com/daafffodil/inputeng/releases/latest)

1. 下载并完整解压 `inputeng-windows-v0.6.2.zip`。
2. 双击 `install.cmd`。
3. 如果电脑尚未安装小狼毫，安装器会询问是否从 Rime 官方 GitHub 下载固定版本，并校验 SHA-256。
4. 安装完成后，在 Windows 输入法列表中选择 **小狼毫**；inputeng 方案已经在其中启用。
5. 从开始菜单打开 **inputeng 设置**，可以调整外观、查看词库说明或配置 AI 翻译。

从 v0.6.1 起，安装器不再默认修改小狼毫共用的 Windows 系统名称或图标，也不会提示注销并重新登录。`Win + Space` 显示“小狼毫”属于正常现象，不影响 inputeng 的输入方案、候选翻译或设置入口。卸载时双击 `uninstall.cmd`；卸载器不会删除小狼毫，也不会删除用户自己学习的词语。

### macOS

macOS 版依赖近期正式版鼠须管。v0.6.2 与 Windows 共用同一套优化后的中文核心词库、原生双向离线释义、全拼/搜狗双拼、F4 切换、首次组合学习和 DeepSeek 缺词翻译；API Key 保存到 macOS 钥匙串。安装步骤见 [macOS 说明](platforms/macos-rime/README.md)。

## v0.6.2 输入延迟优化

离线注释、英文直输、F4 切换和组合学习现在由 librime 原生组件处理；每次按键只保留一个轻量 Lua 过滤器读取 AI 缓存，不再让 Lua 加载并逐键查询约 5.9 万条离线释义。在 Windows + 小狼毫 0.17.4 的隔离测试中，逐键处理耗时中位数从约 8.86 ms 降至 0.32 ms，p95 从约 17.13 ms 降至 1.19 ms。

## AI 翻译与 API Key

AI 翻译完全可选。仓库和发布包中**不包含作者的 API Key，也不会提供共用 Key**。

- 每位使用者需要在本机自行填写自己的 DeepSeek API Key。
- Windows 使用 DPAPI、macOS 使用系统钥匙串按当前账户保存 Key，不把明文写入项目目录或 Rime 配置文件。
- 只会发送离线词典仍然缺失的短词，不发送应用正文、此前上屏内容或完整输入历史。
- 翻译结果缓存在本机，已有结果不会重复请求。
- 未配置 API 时，中文输入和离线双语释义仍可正常使用。

## 词库

- 中文核心词库：173,036 条。基础词来自经过筛选的 [Rime Ice](https://github.com/iDvel/rime-ice) 简体词库，并保留规范汉字读音。
- 中译英短释义：59,873 条，来自 [CC-CEDICT](https://www.mdbg.net/chinese/dictionary?page=cc-cedict) 的裁剪和短释义转换。
- 英译中短释义：58,129 条，来自 [ECDICT](https://github.com/skywind3000/ECDICT) 的常用词裁剪。

详细来源、修改说明和许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。项目代码采用 MIT License；第三方词库继续遵循各自许可证。

## 隐私

inputeng 不包含遥测，不读取剪贴板，也不读取当前应用正文。个人短语、外观设置、AI 队列和翻译缓存只保存在本机。只有使用者主动配置并启用 DeepSeek 后，缺失短词才会发送到 DeepSeek API。

## 从源码构建

Windows：

```powershell
python platforms/windows/scripts/package.py
python platforms/windows/scripts/test_package.py
```

macOS 安装包：

```powershell
python platforms/macos-rime/scripts/package.py
```

Windows 的完整候选冒烟测试还需要本机存在可加载的 librime / 小狼毫运行环境：

```powershell
python platforms/windows/scripts/smoke_rime.py
python platforms/windows/scripts/benchmark_rime.py --max-p95-ms 5
```

## 项目结构

```text
inputeng/
├─ platforms/
│  ├─ windows/          # 小狼毫方案、安装器、设置界面和测试
│  └─ macos-rime/       # 鼠须管实验方案和安装脚本
├─ shared/dictionary/   # 双向离线词典构建数据
├─ docs/                # 架构说明和预览图
├─ licenses/            # 第三方许可证全文
└─ scripts/             # 公共安全检查
```

## 已知边界

- Windows 版是小狼毫扩展，不是独立 TSF 输入法。
- 小狼毫会按同页最长中文候选统一放置英文注释列，当前配置不能让每一行完全独立紧贴。
- Rime Lua 无法在没有新按键事件时主动重绘已经打开的候选页，因此后台补齐的 AI 释义会在下一次候选刷新时出现。
- macOS 与 Windows 已共用相同的 Rime 核心文件和词典；macOS 真实设备的安装、候选视觉与快捷键体验仍待最终验收。
- Windows 和 macOS 都是官方 Rime 前端的扩展，不是独立系统输入法；系统列表可能继续显示上游“小狼毫”或“鼠须管”的名称和图标。

## 参与开发

欢迎提交 Issue 或 Pull Request。提交前请运行 Windows 包校验，并确保没有提交 API Key、缓存、个人词频或其他本机数据。
