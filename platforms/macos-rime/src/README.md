# inputeng for macOS v0.2.0

这是一个最小、离线的鼠须管配置：正常使用简体拼音，命中本地词典时在候选词旁显示统一短英文释义。

## 系统要求

- macOS 13 或更高版本
- 官方鼠须管 1.1.2（或带 `librime-lua` 插件的近期版本）

鼠须管官方下载：<https://github.com/rime/squirrel/releases/latest>

## 安装

1. 先安装鼠须管；首次安装后按照官方提示退出当前 macOS 用户并重新登录。
2. 解压本安装包。
3. 打开“终端”，先输入 `bash `（末尾有一个空格），再把 `install.sh` 拖进终端窗口，按回车运行。若终端已经位于解压后的文件夹，也可以执行：

   ```bash
   bash install.sh
   ```

4. 点击 macOS 菜单栏里的鼠须管图标，选择“重新部署”。
5. 按 `Control + 反引号`（或 `F4`）打开方案菜单，选择“**inputeng**”。

安装器会调用鼠须管自带的 `rime_deployer` 安全地把新方案加入列表；复制前会备份同名旧文件。

## 测试

依次输入：

- `fanyi` → `翻译  to translate`
- `fanyi` → `反义  antonymous`
- `fanzui` → `犯罪  to commit a crime`

选择候选后只会上屏中文，英文不会进入正文。

## 特点与边界

- 完全离线，不使用 AI，不调用 API。
- 英文来自本地 CC-CEDICT 派生词典，只显示一个常用义项并限制为约 24 个英文字符。
- 只有词典中存在的完整候选才显示英文；目前不对长句进行机器翻译。
- 本版本只实现候选英文注释，不调整鼠须管的候选排序和界面。
- 该版本尚未完成真实 Mac 验收，属于实验预览版。

## 卸载

在终端运行：

```bash
bash uninstall.sh
```

然后按脚本提示清理 `default.custom.yaml` 并重新部署。
