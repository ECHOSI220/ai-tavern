# 1.1.1 — 社交聊天显示修复 / Social chat rendering fix

修复范围：原角色社交模块的私聊与群聊，Windows / Android 共用实现。

## 原因

流式回复原先在列表外使用普通 Text 显示；保存后的消息才使用 Card，因此皮肤、宽度和位置会改变。send() 还等待额外模型记忆提取，导致文本输出结束后输入区继续禁用数秒。

## 修改

- 流式、等待中、正式消息使用同一个气泡构建器，统一皮肤、边距和最大宽度，并进入同一聊天列表。
- 使用稳定消息 Key，保存时原子替换流式状态，避免重复文本和跳换布局。
- 用户消息保存后立即显示并清空已发送内容，模型回复保存后立即显示；不等待三秒轮询。
- 输入框生成过程中保持可编辑及一致外观，新输入草稿不被回复完成事件清掉。
- UI 采用后台记忆提取，模型／数据库异常不撤回成功回复。后台提取完成前检查原回复仍存在，避免清理后再提取已删除对话。
- 保留服务端调用入口的默认等待语义，已有测试和其他调用者无需改变。模型请求仍串行，后台提取可能影响下一次模型调用排队，但不会阻挡已经生成的回复展示。
- 版本：1.1.1+2026092323。未改 API 密钥、云端表结构或多人结算协议。

## 测试

新增窄屏和宽屏 widget 测试：使用受控模型流，先暂停在半句回复，再完成回复但阻塞记忆提取，验证气泡、立即显示、发送按钮恢复与草稿保留。使用真实本地 SQLite；模型是测试替身，不代表真实设备或提供商端到端验收。

## English

Streaming and saved replies now share one themed bubble inside the conversation list. Messages appear immediately after persistence; optional memory extraction no longer delays the completed reply or the send button. The composer stays visually consistent and preserves newly typed drafts. Both private and group social chats use the fix.

完整回归：369 项测试全部通过。变更源码及新增测试静态分析无问题。Existing Phase 10 preview limitations remain unchanged.

## 安装包 / Artifacts

- Windows Release：构建成功（52.2 秒），1.1.1+2026092323，完整压缩包 53 个条目校验通过。`dist/windows/ai-tavern-v1.1.1-chat-display-fix-windows-x64.zip`。
- Windows SHA256：`3DBFA47F33D6A9ABF9AB6F8B1F2A07DFAC9CC979BA7168CBB927DB985A7A322F`。
- Android Release：构建成功（63.4 秒），ARM64，versionCode 2026092323，39 个 Flutter 资源条目校验通过。`dist/android/ai-tavern-v1.1.1-chat-display-fix-arm64.apk`。
- APK SHA256：`676BFEDEF9D503CC75D44A8E8B0E1ADB37BA9DAAF5FB86F3205D7CB16D0FF1DB`。
- APK 签名校验通过，沿用原有 Android Debug 签名，与 1.1.0 一致；不是商店签名。
- 没有自动安装到用户设备，也未替换 GitHub 或网盘下载。Windows 完整解压后运行；安卓升级前备份存档，无需卸载旧应用。
