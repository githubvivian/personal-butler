# 个人管家

本地加密、中文 OCR、家庭日程管理的 Android 个人助手。

## 功能

- 收件箱：相册选图（仅存引用）+ 中文 OCR + **语音转文字** + 确认入库
- 日历：日/周视图、本地提醒
- 悬而未决：报账/评审流程跟踪、延期提醒
- 家庭：贝贝 / 核桃课表与活动（多选筛选）
- 生日：阴历 / 阳历、倒计时
- 灵感库、密码保险库（无银行卡）
- 加密备份与恢复（.pbak）
- 指纹解锁，2 小时内免重复验证

## 您如何安装（无需开发环境）

### 方式一：GitHub Actions 自动打包（推荐）

1. 将本项目推送到您的 GitHub 仓库
2. 打开仓库 → **Actions** → **Android CI** → **Run workflow**
3. 完成后在 Artifacts 中下载名称以 `personal-butler-ci-release-` 开头的压缩包
4. 解压 Artifact，得到 `app-release.apk`
5. 将 APK 传到手机安装（需允许该文件来源安装应用）

### 方式二：请开发者代为打包

将项目文件夹提供给有 Flutter 环境的人，按下方“开发构建与验证”完成依赖解析和构建。

APK 路径：`build/app/outputs/flutter-apk/app-release.apk`

> [!WARNING]
> 当前 CI 生成的是 **release 模式、debug 密钥签名**的 APK，仅适合测试和个人使用。不同电脑或 CI 环境生成的 APK 可能使用不同 debug 密钥，不能保证可以覆盖安装。若要长期保留数据并持续升级，应创建、妥善备份并始终使用同一个 release keystore。若必须卸载当前版本，请先在“我的 → 数据备份与恢复”中导出 `.pbak` 加密备份。

## 开发构建与验证

CI 使用锁定依赖，并在同一依赖解析结果上依次执行静态检查、测试和两种 APK 构建。Flutter 版本及 Android/JDK 版本以 [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml) 为准。

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --debug --no-pub --android-project-arg=kotlin.incremental=false
flutter build apk --release --no-pub --android-project-arg=kotlin.incremental=false
```

Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`

Release 模式 APK：`build/app/outputs/flutter-apk/app-release.apk`

## 华为 Android / 兼容 Android APK 的 EMUI、HarmonyOS 真机说明

- 本项目输出标准 Android APK，当前支持与验证范围仅包括华为 Android 设备，以及仍兼容 Android APK 的 EMUI、HarmonyOS 版本。HarmonyOS NEXT 不支持 Android APK，不在当前支持或验证范围内。
- 安装前确认系统允许当前文件管理器、浏览器或 ADB 安装应用；不同 EMUI/HarmonyOS 版本的设置入口可能不同。
- 首次启动后按实际需要授予通知、相册/媒体、麦克风等运行时权限，并按应用提示完成生物识别验证。提醒功能还可能需要在系统设置中允许精确闹钟、后台运行或自启动，并将应用从严格省电限制中移出。
- 当前环境中的构建、自动化测试和静态检查已经通过，但这不能替代目标华为设备验证，也不代表已经完全兼容所有 EMUI/HarmonyOS 版本。
- 仍需在实际目标手机上验证：安装与覆盖升级、冷/热启动、无 GMS 环境、通知与精确闹钟、后台/重启后的提醒、相册与 OCR、语音输入、生物识别、数据库持久化及 `.pbak` 导出恢复。
- 真机测试前建议先保留现有数据备份；测试时同时观察应用行为和 `adb logcat`，以便定位权限拒绝、后台终止、崩溃或 ANR。

## 首次使用

1. 安装 APK，打开应用
2. 按提示完成生物识别验证和初始化
3. 按实际需要授予通知、相册/媒体、麦克风等运行时权限
4. 建议在「我的 → 数据备份与恢复」设置备份密码并导出一份加密备份

## 数据与安全

- 数据存储在手机本地 SQLCipher 加密数据库
- 截图仅保存相册 `assetId` 引用，不复制原图到应用目录
- 密码库字段单独 AES 加密
- 默认不上传云端

## 技术栈

Flutter · SQLCipher · ML Kit 中文 OCR · local_auth · photo_manager
