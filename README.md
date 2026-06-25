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
2. 打开仓库 → **Actions** → **Build Android APK** → **Run workflow**
3. 完成后在 Artifacts 中下载 `personal-butler-apk`
4. 将 `app-release.apk` 传到手机安装（需允许未知来源）

### 方式二：请开发者代为打包

将项目文件夹提供给有 Flutter 环境的人，执行：

```bash
flutter pub get
flutter build apk --release
```

APK 路径：`build/app/outputs/flutter-apk/app-release.apk`

## 首次使用

1. 安装 APK，打开应用
2. 按提示验证指纹完成初始化
3. 授予相册、通知、指纹权限
4. 建议在「我的 → 数据备份与恢复」设置备份密码并导出一份加密备份

## 数据与安全

- 数据存储在手机本地 SQLCipher 加密数据库
- 截图仅保存相册 `assetId` 引用，不复制原图到应用目录
- 密码库字段单独 AES 加密
- 默认不上传云端

## 技术栈

Flutter · SQLCipher · ML Kit 中文 OCR · local_auth · photo_manager
