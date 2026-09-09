# AI Tavern / 幻境酒馆

AI Tavern is a local-first Flutter application for AI role-playing, character chat, and solo or multiplayer tabletop adventures. Windows x64 and Android arm64 builds are provided.

幻境酒馆是一款本地优先的 Flutter AI 角色扮演、角色聊天和单人/多人跑团应用，提供 Windows x64 与 Android arm64 版本。

## Downloads / 下载

- [Latest release / 最新版本](https://github.com/ECHOSI220/ai-tavern/releases/latest)
- [Web community / 云端社区](https://ai-tavern-cloud.pages.dev)
- [My creations / 我的作品](https://ai-tavern-cloud.pages.dev/me/uploads)
- [Baidu Netdisk downloads / 百度网盘下载](https://pan.baidu.com/s/5cdrHai0bnrtYimTjQr9n4Q)
- [Open-source web client / 开源网页源码](https://github.com/ECHOSI220/ai-tavern/tree/main/community)

For Windows, extract the entire ZIP and run `ai_tavern.exe`; keep its DLLs and `data` directory together. For Android, install the arm64 APK. Back up local saves before upgrading. / Windows 请完整解压 ZIP 后运行 `ai_tavern.exe`，不要拆开 DLL 和 `data` 目录；安卓安装 arm64 APK。升级前请备份本地存档。

## v1.0.39 highlights / 1.0.39 更新内容

- Fixed multiplayer settlement failures caused by missing system proxy routing and DNS lookup failures. / 修复多人结算未使用系统代理、DNS 解析失败导致无法调用模型的问题。
- Added Windows system-proxy detection and Android system `ProxySelector` integration. / Windows 自动读取系统代理，安卓接入系统代理选择。
- Preserved DeepSeek reasoning context across tool-call rounds and kept tool results during retries. / 保留 DeepSeek 工具调用轮次的推理上下文，重试时保留已执行工具结果。
- Added bounded timeouts, duplicate/late-response protection, host recovery, and safe diagnostic logs. / 增加超时保护、重复/迟到回复拦截、主持恢复和安全诊断日志。
- The multiplayer path was verified against a real OpenAI-compatible API with a tool-call round trip. / 多人调用链已用真实 OpenAI-compatible API 完成工具调用往返验证。

## Features / 功能

- Independent local stories, character cards, world books, and persistent memory. / 独立本地故事、角色卡、世界书和持久记忆。
- Streaming chat with a user-configured OpenAI-compatible provider. / 支持用户配置 OpenAI-compatible 服务商的流式聊天。
- Solo adventures and multiplayer TRPG workflows with dice, turns, and authoritative server rules. / 支持单人冒险和多人 TRPG，包含骰子、回合及服务器权威规则。
- Optional image understanding and voice features. / 可选图像理解和语音功能。
- A responsive web community for JSON sharing, discovery, and cover images. / 响应式 JSON 分享、发现和封面图社区。
- Windows and Android shortcuts to the web community and uploaded creations. / Windows 与安卓端提供社区及作品快捷入口。

## Repository layout / 目录结构

| Directory / 目录 | Purpose / 用途 |
| --- | --- |
| `lib/` | Flutter screens, models, repositories, services, and widgets / Flutter 界面、模型、仓储、服务和组件 |
| `android/` | Android host and native integrations / 安卓宿主与原生集成 |
| `windows/` | Windows runner and CMake integration / Windows runner 与 CMake 集成 |
| `assets/`, `examples/` | Declared runtime artwork and examples / 运行时资源与示例 |
| `test/` | Flutter tests / Flutter 测试 |
| `community/` | TypeScript/Vite community website / TypeScript/Vite 社区网站 |
| `server/` | Cloudflare Worker and Durable Objects backend / Cloudflare Worker 与 Durable Objects 后端 |
| `shared/` | Shared protocol schemas and fixtures / 共享协议与测试夹具 |
| `supabase/` | SQL migrations and access tests / SQL 迁移与访问测试 |
| `tool/` | Build, deployment, and diagnostic helpers / 构建、部署和诊断工具 |

## Build / 构建

Use Flutter with Dart **3.12.2 or newer compatible SDK**, JDK 17, and the Android SDK. Windows builds require Visual Studio C++ desktop build tools and a Windows SDK. / 需要 Dart **3.12.2 或兼容的更高版本**、JDK 17 和 Android SDK；Windows 构建需要 Visual Studio C++ 桌面开发工具与 Windows SDK。

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release --target-platform android-arm64
```

Cloud features require your own backend configuration. Never put an admin/service-role key in an application build. / 云端功能需要自行配置后端；不要把 admin/service-role 密钥放进应用构建产物。

The Android sideload build uses a debug signing configuration. Configure your own signing key before store distribution. / 当前安卓侧载包使用 debug 签名；发布到应用商店前请配置自己的签名。

## Security and publication scope / 安全与发布范围

This repository is a curated source snapshot. Production secrets, signing material, local saves, chat histories, build caches, and development logs are excluded. The app stores API keys locally and diagnostic logs redact keys, prompts, message bodies, and authorization data. / 本仓库是经过筛选的源码快照，已排除生产密钥、签名材料、本地存档、聊天记录、构建缓存和开发日志。应用在本地保存 API Key，诊断日志会隐藏密钥、提示词、消息正文和授权信息。

Review the included Cloudflare/Supabase configuration and test on your own development project before deployment. / 部署前请审查仓库中的 Cloudflare/Supabase 配置，并先在自己的开发项目中测试。

No new license grant is made by this upload. Dependency and asset licenses remain applicable. / 本次上传不代表新增任何许可证授权；依赖和资源仍适用其原有许可。
