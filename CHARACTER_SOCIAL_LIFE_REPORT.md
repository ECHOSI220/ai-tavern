# Summary

后续修复：1.1.1 已修正社交流式回复皮肤不一致及等待记忆后才刷新的问题，详见 `SOCIAL_CHAT_DISPLAY_FIX_1.1.1.md`。下文保留 1.1.0 阶段的功能验收记录。

版本 / Version: 1.1.0+2026092322（Phase 10 功能预览版）。

已在原 Flutter 应用中实现可持久化的角色社交核心，不是独立 Demo；首页第四模式包含消息、联系人、朋友圈、我的。它使用现有角色卡和已配置的 AI Provider 进行真实流式请求。自动测试的模型响应由测试替身提供，并不等同于用户 API 或两台真机验收。

**本报告不代表附件全部 251 项要求完成。** 核心链路已落地；完整通知、游戏时钟、进阶关系图等剩余项见文末。安装前保留原有存档备份，建议先使用测试角色体验。

English: This is an integrated, persistent Phase 10 feature preview, not a separate demo. It reuses character cards and the existing AI provider. Automated provider tests use a fake transport; real-provider and two-device acceptance remain outstanding. Not all 251 specification items are complete.

# Existing Systems Reused

- Character / CharacterCardRepository：唯一人格来源、角色卡编辑和原存储。
- StorageService：现有 SQLite 数据库内新增表，不另建应用数据体系。
- ApiRepository / SettingsRepository / AiService：原 API 配置、密钥读取与流式请求。
- AccountClientService：已有登录、令牌刷新及 Supabase REST 通路。
- SaveRepository / TRPGSessionRepository / StoryCardRepository：已有角色、已知 NPC、经确认的公开世界资料。
- 原主题、头像、TrpgVoiceButton、Sherpa TTS 和角色语音设置。
- 不修改原多人结算协议；原单人、多人与主题回归测试继续运行。

# Architecture

`Character → SocialProfileInferencer → CharacterSocialService → CharacterSocialRepository → SocialSyncService`

核心文件位于 `lib/models/character_social.dart`、`lib/services/character_social/`、`lib/repositories/character_social_repository.dart`、`lib/screens/character_social/`。SocialRecord 是带种类、所属账号、世界、角色、父记录、版本及删除标记的记录信封；不是第二套人格模型。

# Character Card Integration

角色卡库提供“添加到角色社交”。同一世界重复导入使用稳定 ID 去重。联系人只引用角色 ID；编辑原卡会影响后续社交提示词。独立私有 card 记录用于跨设备还原或删除时保留快照。引用中的原卡删除必须确认保留快照，不静默切断人格来源。

# Social Identity

联系人按账号、世界、角色区分。备注名只影响显示，不改人格。群聊和私聊引用同一个 Character。游客数据不在登录后自动上传或混入账号数据。

# Social Profile

从人格、描述与说话风格推断发帖频率、主动性、社交精力、隐私倾向、回复延迟和夜间习惯；原卡可带可选 socialProfile。寡言角色受更低主动性和发帖上限约束。部分扩展字段仅保留兼容数据，尚未全部接入行为或可视化编辑器。

# Private Chat

复用现有 API 配置真实流式生成，显示进行中回复，失败保留用户消息并可重试。稳定回合／回复 ID 防止本地重复回复。不同社交请求串行访问同一个 AiService，避免后台动态和前台聊天互相取消。退出聊天页仍允许完成并保存该回复；退出整个社交模式会取消请求。每段流等待上限 120 秒，累计输出限制 16,000 字符。

# Memory

只有带原文证据且达到重要性阈值的事实被提取，单次最多三条。长期记忆按内容相关性、重要性和时间衰减检索，默认最多八条，不把全部历史放入提示词。支持编辑／删除记忆；清理聊天可选择是否同时清除相关记忆，不重置关系。尚无向量索引、跨模式统一编辑器或完整生命周期治理。

# Relationship

九维关系数值受边界约束；仅证据成立的互动可带来小幅变化。模型建议增量限定 ±3，最终数值限定 0–100。显示柔性关系标签，不自动升级恋爱关系。

# Mood

保存主要／次要情绪、情绪值、压力、精力、唤醒度、孤独感、自信等状态。支持性和冲突事件温和影响情绪；休息逐步回归平稳。部分维度当前是基础状态，不是完整心理模拟。

# Schedule

根据职业线索、时间与夜间习惯推断休息、用餐、学习、训练或自由活动。可读取角色卡 socialProfile.schedule 自定义小时区间，包含跨午夜区间。在线／忙碌／勿扰来自日程，不假装角色一直在线。没有新增系统后台常驻任务。

# Offline Simulation

启动／恢复应用时惰性推进；先显示缓存页面，不让 AI 推演阻挡整个页面。每位角色最少一小时推进间隔；最多回顾 72 小时，每次每角色最多一条事件，最多处理 200 位联系人。

低成本：规则事件，不调用模型生成离线生活。平衡：规则事件和受频率限制的动态。丰富：额外推演有限的日常事件；预算耗尽后回退规则。网络失败不伪造成功回复。当前加速模式仅改变推演时长权重，不是完整独立世界时钟。

# Life Events

持久化日程事件、用户指定的公开世界事件与丰富模式生成事件。限制不可逆重大剧情。世界事件只进入同世界公开上下文，和更新后的角色状态一起本地事务保存。

# Moments

动态来源于已生成的公开生活事件。支持角色动态、用户动态、删除、详情和分批加载。事件来源 ID 保留。新增动态会尝试触发已相识角色的有限互动，不让角色给自己刚发的动态自动评论。当前为文字动态，未实现完整社交图片动态上传与媒体审核流程。

# Likes

用户可切换点赞，同一角色／动态稳定 ID 避免重复点赞。AI 决策可点赞或不点赞。用户累计多次点赞可形成汇总记忆，不逐次扩张长期记忆。

# Comments

用户评论本地保存后触发最多两位符合条件角色的回应。详情页显示评论与点赞；角色聊天可检索可见动态下的近期评论。作者允许回应用户评论，但不主动消耗预算给自己评论。重要评论互动可提取带证据的记忆。

# User Posts

用户可在当前世界发帖，选择所有角色或指定角色可见。只有同世界且满足 audience 的角色收到提示。编辑既有帖子内容和完整媒体发布尚未实现。

# Proactive Messages

默认关闭。开启后仍受主动性、至少 24 小时冷却、安静时段和自动调用预算约束；模型可以返回 SKIP。消息持久化并计入未读。应用完全关闭时不会在服务端代用户运行模型。

# Group Chat

同世界 2–8 位角色。导演模型可选择 0–2 位发言者，允许沉默，不轮流强制回应。已完成回复重试时不重复。只有群成员共同已知记忆进入群提示词。尚未实现完整群成员管理、提及解析和跨设备单一 AI 执行租约。

# Character Relationships

显式组群建立相识边；陌生角色不参与其他角色动态互动。当前是基础相识图，不是完整九维角色间关系自动演化、关系网络可视化或手工编辑器。

# Social Worlds

世界区分联系人、聊天、事件、动态和记忆。可创建世界、录入公开资料，并显式选择原世界书公开内容。默认不读取隐藏条目。真实世界时钟可用；加速时长为简化实现，gameTime 未完成。

# Cross Mode Memory

默认隔离。设置中显式开启并选择有知识证据的 TRPG 记忆，形成 globalCharacter 范围共享记录。关闭共享后不注入此类记录。酒馆存档可以导入角色，但 Tavern Chat 长期记忆双向共享尚未接好。NPC 导入目前只包含已知名称和相识描述，完整安全人格映射待补。

# Knowledge Isolation

社交记忆限定 knownBy；群聊要求所有参与者都已知。TRPG 导入同时检查现有 MemoryPrivacyFilter、confirmed 状态和角色 knows/witnessed 关系，排除 GM、伏笔、秘密及私有记忆。角色互动提示词不加入其他角色私聊。

# Cloud Sync

同账号私有记录通过现有 REST 客户端上传／下载。前台每 30 秒轮询，恢复时同步；不是 Supabase Realtime。服务端提交批次检查版本，冲突时拒绝整个提交，客户端提供明确选择，避免无提示覆盖。相同请求重试被识别；删除通过 tombstone 同步。下载按 ID keyset 分页，不依赖可能漏掉延迟提交的序列游标。

头像编码成私有小缩略图，再在设备还原；拒绝把云端任意本地路径当作头像。当前没有完整不可变 outbox 历史；跨设备同时运行同一回合也没有分布式执行锁，不能承诺完全没有重复模型计费。

# Supabase Schema

两份 migration 已应用到原项目 `ai-tavern`：

- `20260912092221_character_social_life.sql`：character_social_records 和 social_apply_batch。
- `20260912093727_character_social_ai_budget.sql`：character_social_ai_budget 和 social_reserve_ai_call。

第一张表限制记录种类、对象 payload 大小，索引覆盖账号／父记录／角色／世界和时间。第二张表以账号和 UTC 日期约束自动调用预算。自动预算按模型调用次数而非精确 Token 或费用统计，失败请求保守计入额度。

# RLS

按 auth.uid() 限定记录所属账号；匿名不可读写；RPC 使用 security invoker。真实事务测试（回滚测试用户和数据）已验证账号隔离、幂等、版本冲突、整批拒绝，以及预算两次可用第三次被拒绝。

遵循 Supabase 技能的迁移与 RLS 工作流，没有通过公开桶存储私聊／头像。安全检查未给新表或新 RPC 报告问题；发现原有 is_campaign_member 的 SECURITY DEFINER 执行权限警告与密码泄露保护关闭，未擅自更改原多人权限：

- https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

# Android UI

390×844 测试视口验证真实页面、四个底部标签及主题，无溢出。输入提供已有语音转文字组件，消息朗读复用原 TTS。截图 `build/social_ui/social-390.png`。这是 widget 渲染验证，不是安卓设备实测。

# PC UI

1280×850 测试视口采用左侧导航，无溢出。截图 `build/social_ui/social-1280.png`。暂未实现完整聊天三栏布局。语音模型和麦克风仍需要设备侧授权及原模型文件。

# Theme Integration

继承现有 SkinTheme 与 Material 主题，未引入另一个全局主题。自动截图使用已有骑士主题；原主题、跑团时间线及壁纸回归保留。

# AI Token Optimization

历史最多 20 条、约 6,000 字符上下文预算；相关记忆最多八条；限制公开世界资料和动态上下文；自动调用默认每日 12 次，最大 50。默认低成本模式且主动消息关闭。已登录时服务端原子预算跨设备执行；游客仅本机计数。开启丰富模式或记忆提取会消耗已配置模型额度。

# Tests

- 核心社交：人格频率、可见性、群知识、证据、关系边界、日程、账号隔离、事务、云冲突与确认。
- 服务测试：导入、流式回复、失败重试、记忆、关系、20 角色三天离线预算、低成本零调用、丰富模式回退、动态互动、清理聊天、卡编辑／删除快照、GM 隔离、请求串行与关闭后拒绝调用。
- UI：两种宽度的真实 SQLite 与页面交互测试，不用假页面替代。
- 社区网页：构建成功，8 项测试通过；没有部署网页改动。
- 最终完整回归与构建结果记录于下节；真实模型／双真机尚未执行。
- 最终 `flutter test --no-pub --reporter compact`：367 项全部通过。新增社交源码与三组测试的静态分析：No issues found。

# Build Results

- Windows Release 构建成功，版本 1.1.0+2026092322。Dart AOT 产物 `data/app.so` 生成时间晚于最后一次源码修改；压缩包校验 53 个条目，包含 exe、运行库与资源。
- Windows：`dist/windows/ai-tavern-v1.1.0-social-preview-windows-x64.zip`，57,209,355 字节。
- SHA256：`A24CB44D4E184A3AD692ECAB13FAD9238E6F6A018C3CEA28E09AA3550E6D77D6`。
- Android Release 编译成功（160.7 秒），39 个 Flutter 资源条目校验通过；`dist/android/ai-tavern-v1.1.0-social-preview-arm64.apk`，85,730,206 字节。
- APK：versionName 1.1.0、versionCode 2026092322、包名 com.imaginary.tavern.ai_tavern、ARM64、minSdk 24；SHA256 `FB044CBA00C05FEB4CC5A1DC609E2CC55472E70A350DFE2898AA934FE7DE0064`。
- APK v2 签名验证通过，证书与已交付 v1.0.40 一致。沿用原项目 Android Debug 证书，不是商店发行签名；没有擅自更换密钥。构建存在原插件 Kotlin 迁移及 SDK XML 版本警告，不影响本次成功，但正式上架前应处理。
- 社区网页 `npm run build` 与 `npm test` 成功（8 项），未部署线上。
- 当前 ADB devices 无已连接手机，未执行真机安装或声称双端验收通过。

安装：Windows 完整解压到新目录后运行 ai_tavern.exe，不要只复制 exe；Android 保留旧数据进行覆盖安装，升级前先通过原存档功能备份。进入首页“角色社交”→添加联系人；沿用应用设置中的默认 API。建议先用低成本模式体验聊天，再按需要开启自动动态／主动消息。游客模式不自动迁入账号，想跨设备同步应先登录同一账号再添加联系人。

# Remaining Issues

以下是明确未完成的验收项，不应在发布文案里称为已支持：

1. Windows+Android 同账号真实双端测试、真实用户 API 联调、麦克风／TTS 真机测试。
2. 系统推送通知、通知级别和后台常驻任务；当前只做前台状态与未读。
3. 完整游戏时间／加速世界时钟、生日节庆纪念日、全部社交档案参数编辑及行为接入。
4. Tavern Chat 长期记忆共享、完整 NPC 安全人格映射、完整跨模式记忆 UI。
5. 角色间关系自动演化、关系图编辑／可视化、群成员管理和跨设备 AI 执行租约。
6. 全历史全文搜索、无限滚动（当前联系人／聊天列表有上限，消息读取最多 500 条）、同步增量优化和不可变 outbox。
7. 图片朋友圈、完整媒体存储与权限流程；完整帖子编辑／隐私等级选择。
8. 本地工作目录无 git 元数据；未自动推送 GitHub，也未替换线上下载文件。

English: Remaining work includes real-provider and physical-device acceptance, system notifications, complete world clocks and calendar events, full cross-mode memory sharing, advanced relationship graphs and group management, distributed AI execution leases, unlimited history/search, media moments, and release publication. This preview must not be described as the complete 251-item implementation.
