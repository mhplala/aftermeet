# 会后秘书 AfterMeet — macOS app

原生 SwiftUI 实现，从 Claude Design 的 `会后秘书 AfterMeet.dc.html` 落地。桌面端效率工具观（Linear/Notion 风），绿色为「闭环 / 完成」语义主色。

## 跑起来

```bash
./build.sh                      # xcodegen generate + xcodebuild
open .build/Build/Products/Debug/AfterMeet.app
```

或直接在 Xcode 打开：`xcodegen generate && open AfterMeet.xcodeproj`。

要求：Xcode 26 / Swift 6.x（语言模式按 Swift 5 编译）、macOS 14+。

## 六个页面

| 页面 | 文件 | 说明 |
|---|---|---|
| 概览 | `HomeScreen.swift` | 问候、4 张指标卡、近期纪要 / 今天该跟的、追问横幅 |
| 会议纪要 | `DetailScreen.swift` | 折叠区块（决策/待办/分歧/逐字稿）+ 底部固定操作条 |
| 待办中心 | `TodosScreen.swift` | 跨会议任务、筛选、勾选改闭环率 |
| 会前追问 | `FollowupScreen.swift` | 进度对比卡、完成/未动、发到群 |
| 周报 | `WeeklyScreen.swift` | 指标卡 + 闭环率走势折线图（SwiftUI Path）+ 拖延 Top 5 |
| 接入引导 | `OnboardingView.swift` | 4 步授权引导（关键步：开启智能纪要） |

## 结构

- `Theme.swift` — 设计 token（颜色 / 圆角 / 字体 / 阴影），从 `.dc.html` 的 `:root` 1:1 移植
- `Models.swift` — 数据类型、样例数据、`AppStore`（状态与交互逻辑）
- `Components.swift` — Card / StatCard / Pill / Avatar / Overline 等共享件
- 交互全部是真状态：确认/认领待办、勾选、筛选、折叠、Toast、Onboarding 步进

## 接真实数据

数据走"文件接缝":`sync.sh`(后端替身)把真实飞书会议提炼成 JSON,app 读它。app 不直接调 lark-cli(避开 GUI 的 PATH 问题),将来 ECS 常驻 daemon 写同一份 store 即可平滑替换。

```bash
SIKU_TOKEN=<siku-proxy access token> ./sync.sh 3
# 管线：vc +search（会议）→ vc +notes（逐字稿 token）→ docs +fetch（逐字稿）
#      → 豆包/siku-proxy 按固定 schema 提炼 → 写 ~/Library/Application Support/AfterMeet/meetings.json
```

- app 启动时 `RealData.load()` 读该文件;有真数据就渲染真会议(详情页 + 概览近期列表带「真实数据」标),否则回退到样例的「周三产品评审会」。
- 提炼结构 1:1 对应 `Decision`/`DetailTodo`/`Dispute`;`confidence:low` 或无 owner 的待办自动落「待认领」(宁可多问不可派错)。
- **逐字稿前提**:会议须是飞书 VC 且开了智能纪要/录制,且你是参会者(否则 121005)。实测最近 15 场只有 1 场拿得到——覆盖率是真实瓶颈,对应 onboarding「默认开启智能纪要」那步。

### 网络注意

`zhiwenai.cc` 的 TLS 在国内会被 SNI reset。`sync.sh` 直连 IP `14.103.38.223` + `Host` 头绕过。根治:Clash 给该域名/IP 加 DIRECT 规则(走 profile 合并文件)。

## 字体说明

设计稿用 Inter Tight + JetBrains Mono；当前用系统 SF Pro / SF Mono（设计稿自身的 fallback）。
要 1:1 还原，把字体文件丢进 bundle，改 `Theme.ui/display/mono` 三个 helper 即可。

## 数据真实性原则

有真数据(meetings.json 存在)时,**全部由真数据驱动,不留假数字**：

- 详情页、概览近期列表、概览指标卡、今天该跟的、待办中心 → 从真会议算
- 周报趋势 / 拖延 Top 5、会前追问 → 依赖跨会历史,显诚实空状态(「攒数据中」),不编造
- 样例数据(周三产品评审会等)**只在一条真数据都没同步时**作为演示兜底

判断开关:`store.usingRealData`(= meetings.json 非空)。

## 会后链路的触发

- **现在**:手动跑 `sync.sh`(全量扫,适合补历史)
- **设计**:常驻 daemon 跑 `lark-cli event consume vc.note.generated_v1` —— 飞书在纪要生成时**推送**(NDJSON 长连接,非轮询),daemon 收到 → 抽 meeting_id → 跑提炼 → 写 JSON → app 自动刷新 = 会后 5 分钟自动送达

## 已知边界（当前）

- 待办「确认/认领」目前只改本地状态,尚未回写飞书任务(`task` create 待接,需补 task/im 写权限)
- daemon 未接(现在手动 sync);跨会议历史聚合(周报趋势/会前追问)等 daemon 累积后才有数据
- 搜索框、铃铛为视觉占位
- 启动参数调试：`open AfterMeet.app --args -screen detail`（或 todos/followup/weekly，`-onboarding YES`）
