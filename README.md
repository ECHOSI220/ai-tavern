# 幻境酒馆

**中文** · [English](README.en.md)


幻境酒馆是一款本地优先的 Flutter AI 角色扮演、角色聊天和单人/多人跑团应用，提供 Windows x64 与 Android arm64 版本。

## 1.1.1 更新内容 · 2026.9.14

角色社交预览与流式气泡修复，369 项自动测试通过；记忆整理不再阻挡回复展示。

完整 Phase 10 及双真机验收尚未完成。

参阅[实现报告](CHARACTER_SOCIAL_LIFE_REPORT.md)与[显示修复说明](SOCIAL_CHAT_DISPLAY_FIX_1.1.1.md)。

## 下载

- [最新版本](https://github.com/ECHOSI220/ai-tavern/releases/latest)
- [云端社区](https://ai-tavern-cloud.pages.dev)
- [我的作品](https://ai-tavern-cloud.pages.dev/me/uploads)
- [百度网盘下载](https://pan.baidu.com/s/52ffw3X-MMLAoWp3TDZNVTg)
- [开源网页源码](https://github.com/ECHOSI220/ai-tavern/tree/main/community)

Windows 请完整解压 ZIP 后运行 `ai_tavern.exe`，不要拆开 DLL 和 `data` 目录；安卓安装 arm64 APK。升级前请备份本地存档。

## 1.0.39 更新内容

- 修复多人结算未使用系统代理、DNS 解析失败导致无法调用模型的问题。
- Windows 自动读取系统代理，安卓接入系统代理选择。
- 保留 DeepSeek 工具调用轮次的推理上下文，重试时保留已执行工具结果。
- 增加超时保护、重复/迟到回复拦截、主持恢复和安全诊断日志。
- 多人调用链已用真实 OpenAI-compatible API 完成工具调用往返验证。

## 功能

- 独立本地故事、角色卡、世界书和持久记忆。
- 支持用户配置 OpenAI-compatible 服务商的流式聊天。
- 支持单人冒险和多人 TRPG，包含骰子、回合及服务器权威规则。
- 可选图像理解和语音功能。
- 响应式 JSON 分享、发现和封面图社区。
- Windows 与安卓端提供社区及作品快捷入口。

## 目录结构

|目录 |用途 |
| --- | --- |
| `lib/` |Flutter 界面、模型、仓储、服务和组件 |
| `android/` |安卓宿主与原生集成 |
| `windows/` |Windows runner 与 CMake 集成 |
| `assets/`, `examples/` |运行时资源与示例 |
| `test/` |Flutter 测试 |
| `community/` |TypeScript/Vite 社区网站 |
| `server/` |Cloudflare Worker 与 Durable Objects 后端 |
| `shared/` |共享协议与测试夹具 |
| `supabase/` |SQL 迁移与访问测试 |
| `tool/` |构建、部署和诊断工具 |

## 构建

需要 Dart **3.12.2 或兼容的更高版本**、JDK 17 和 Android SDK；Windows 构建需要 Visual Studio C++ 桌面开发工具与 Windows SDK。

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release --target-platform android-arm64
```

云端功能需要自行配置后端；不要把 admin/service-role 密钥放进应用构建产物。

当前安卓侧载包使用 debug 签名；发布到应用商店前请配置自己的签名。

## 安全与发布范围

本仓库是经过筛选的源码快照，已排除生产密钥、签名材料、本地存档、聊天记录、构建缓存和开发日志。应用在本地保存 API Key，诊断日志会隐藏密钥、提示词、消息正文和授权信息。

部署前请审查仓库中的 Cloudflare/Supabase 配置，并先在自己的开发项目中测试。

本次上传不代表新增任何许可证授权；依赖和资源仍适用其原有许可。
