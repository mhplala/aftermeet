# 会后秘书 AfterMeet — macOS app

原生 SwiftUI。玻璃拟态视觉（光晕背景 + 磨砂框架 + 纯白工作区），冷墨 + 闭环绿。
交互稿：`claude.ai/code/artifact/505d1ff5-005a-4383-a9b5-b35246aadb3f`（mock 可点）。

## 跑起来

```bash
./build.sh                      # xcodegen generate + xcodebuild
open .build/Build/Products/Debug/AfterMeet.app
```

要求：Xcode 26 / Swift 6.x（语言模式按 Swift 5 编译）、macOS 14+。

## 结构（目录 6 项 + 常驻录制条）

| 入口 | 文件 | 说明 |
|---|---|---|
| 录制条（顶栏常驻） | `RecStrip.swift` | 五态：空闲/检测到会议/录制中/整理中/✓完成（点击才跳详情，不抢页面）；面板含起名、日程建议、实时转写 |
| 概览 | `HomeScreen.swift` | 动态问候（真名 via lark-cli）、指标卡、近期 5 场、今天该跟的、追问横幅（真实 recurringCard） |
| 会议库 | `LibraryScreen.swift` | 所有会议按天分组；tab：纪要 / 原始转写（原转写历史併入） |
| 会议纪要（详情） | `DetailScreen.swift` | 生成式积木 report + 待办确认 + 问答；返回（⌘[）+ ‹› 前后切换（到头禁用） |
| 待办中心 | `TodosScreen.swift` | 跨会议任务、筛选、逾期真实计算（due 过期→逾期） |
| 会前追问 | `FollowupScreen.swift` | 同名会议重复出现 → 上一场待办对比卡，可发群 |
| 每日综述 / 周报 | `DailyScreen/WeeklyScreen` | 按天 digest；周报台账一键复制 Markdown |

导航带历史栈（`AppStore.go/goBack`），面包屑只表达归属，返回永远回来路。

- `Theme.swift` — 新 token（冷墨 #1b1d2a / 闭环绿 #0f9d63 / 玻璃渐变）+ `AmbientBackground` 光晕
- `Models.swift` — `AppStore`：数据、导航栈、录制态、搜索、通知
- `NoteBlocks.swift` — 生成式纪要渲染器（summary/stats/beforeAfter/keyPoints/decisions/disputes/timeline/quote/nextAgenda）
- `Lark.swift` — lark-cli 桥：建任务/搜人/搜群/发消息（用户身份，app 不落凭证）
- `FeishuSync.swift` — 会后自动同步：15 分钟轮询 vc +search → notes → docs +fetch → 豆包提炼 → meetings.json
- 设计禁用：斜体、左侧 accent 竖条、蓝紫渐变

## 真实链路（已接）

- **待办确认/认领 → 真建飞书任务**（`task +create`，姓名精确唯一匹配才指派；task-links.json 防重复建卡）
- **转发到群 / 追问卡发群**：`im +chat-search` 选群 → `im +messages-send --markdown`。**缺 scope**：需一次
  `lark-cli auth login --scope "im:message.send_as_user im:message"`（app 内会提示）
- **飞书同步**：自动轮询 + 侧栏「立即同步」；事件推送 `vc.note.generated_v1` 需在开放平台控制台订阅后才可替代轮询
- **Siku 云**：设备 token（`siku-dev-<uuid>` + X-Siku-App）自动登记，每日 500 万 token 免费额度，用户零配置
- 本地转写链路不变：截系统音频 → Whisper 端上转写 → 豆包生成式提炼（音频不出网）

## 数据真实性原则

有真数据（meetings.json / live-meetings.json 非空）时全部真数据驱动；样例（周三产品评审会）只做零数据演示兜底，
且演示模式下确认待办不建真实任务（toast 注明）。跨周趋势攒够历史才出图，不编造。

## 调试

`open AfterMeet.app --args -screen library`（library/detail/todos/followup/weekly/daily，`-onboarding YES`）

## 已知边界

- im 发送 scope 未授权前，「转发到群」走复制兜底
- 周报趋势图 / 拖延 Top 5 需跨周历史（真数据模式显示诚实空态）
- `sync.sh` 保留作为手动补历史的后备管线（app 内轮询已覆盖日常）
