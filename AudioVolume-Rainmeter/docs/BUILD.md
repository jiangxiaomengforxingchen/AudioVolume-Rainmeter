# 构建与打包

## 1. 环境要求

| 用途 | 依赖 |
| --- | --- |
| 编译采集程序 | .NET Framework 4.x 自带的 `csc.exe`（路径见下），无需安装 SDK |
| 打包 zip | PowerShell 5.1 的 `Compress-Archive` |
| 生成 .rmskin | Rainmeter 自带的 Skin Packager（图形界面，见第 3 节） |

`csc.exe` 默认路径：

```
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
```

## 2. 一键构建

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

脚本会依次做三件事：

1. 用 `csc.exe` 重新编译 `src/AudioLevelHelper.cs`，输出到
   `skin/AudioVolume/@Resources/bin/AudioLevelHelper.exe`
2. 把皮肤打包成 `dist/AudioVolume-v<版本>.zip`（内含 `skin/`、`install.bat`、`README.md`、`LICENSE`）
   —— 注意 `dist/` 已被 `.gitignore` 排除，这个包**只作为 Release 附件**发布，不提交进仓库
3. 如果本机装了 Rainmeter，尝试调用 Skin Packager 生成 `.rmskin`（可选，见下）

## 3. 生成官方 .rmskin（为什么仓库里带不了）

`.rmskin` **不是**普通 zip：它是 Rainmeter Skin Packager 生成的**签名包**，
Rainmeter 安装前会校验签名，把 zip 改名成 `.rmskin` 会被直接拒绝。
签名密钥内置在 Rainmeter 里，第三方无法离线生成。

因此本仓库只用 zip + `install.bat` 分发（体验一致，且不需要管理员权限）。
如果你确实需要 `.rmskin`，用 Rainmeter 自带工具手工生成，一次即可：

1. 打开 Rainmeter → 托盘右键 → `Manage`
2. 左下角点 `Create .rmskin package...`
3. 填写：
   - Name：`AudioVolume`
   - Author：你的名字
   - Version：`1.0.0`
4. 点 `Add skin...`，选择仓库里的 `skin/AudioVolume` 文件夹
5. 下一步：`After installation` 选 **Load skin**，并选中 `AudioVolume.ini`
6. 再下一步（Advanced）：如需保留用户已有配色，可把 `AudioVolume.ini` 填进
   `Variables files`（**不要**同时勾 `Merge skins`，两者互斥）
7. 点 `Create package`，得到 `AudioVolume_1.0.0.rmskin`
8. 把它放进 `dist/` 一起发布

## 4. 打包内容清单

`tools/build.ps1` 打出的 zip 结构：

```
AudioVolume-v1.0.0.zip
├─ install.bat                  一键安装（复制到 Skins 目录并加载）
├─ README.md
├─ LICENSE
└─ skin/AudioVolume/            皮肤本体，整个文件夹原样复制
   ├─ AudioVolume.ini
   └─ @Resources/bin/
      ├─ AudioLevelHelper.exe   采集程序
      ├─ levels-out.lua         扬声器通道
      ├─ levels-mic.lua         麦克风通道
      ├─ theme.lua              主题切换
      ├─ start-helper.vbs       静默启动采集程序
      ├─ start-helper.bat       带窗口启动（调试用）
      └─ stop-helper.bat        停止采集程序
```

**不打包**运行期产物：`level.txt`（电平数据）、`state.txt`（主题状态），
它们会在首次运行时自动生成。

## 5. 发布前自检

- [ ] 跑一次 `powershell -File tools\scan-secrets.ps1`，确认无凭据泄露
- [ ] `skin/AudioVolume/AudioVolume.ini` 里**没有非 ASCII 字符**
      （`Select-String -Path <file> -Pattern '[^\x00-\x7F]'` 应无输出）
- [ ] `.lua` 文件都是 **ASCII 无 BOM**（带 BOM 会导致 `SKIN` 未定义报错）
- [ ] 采集程序能在 64 位系统上运行（`/platform:x64`）
- [ ] 至少在一台机器上跑一遍：加载皮肤 → 放音乐 → 两条卡片数值互不相等
- [ ] `dist/` 里的 zip 解压后 `install.bat` 能正常装进干净环境
- [ ] `dist/` 没有出现在要提交的文件列表里（`.gitignore` 已排除）

CI（`.github/workflows/build.yml`）会在每次 push 时自动编译 + 跑上面三道编码/顺序自检 + 打包，
产物在 Actions 页面的 `AudioVolume-package` artifact 里，可用来核对本地包是否一致。

## 6. 版本号

改版本号需要同时更新两处：

1. `skin/AudioVolume/AudioVolume.ini` 的 `[Metadata]` → `Version=`
2. `tools/build.ps1` 顶部的 `$Version`
