# aftermeet-asr-proxy

Cloudflare Worker：把 AfterMeet 的会中音频转发给火山引擎「豆包语音识别大模型 2.0」双向流式接口
（`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`），真实的 `X-Api-Key` 只存在 Worker
Secrets 里，永远不会打包进公开发布的 AfterMeet.app。

客户端沿用 `SikuCloud` 设备令牌格式（见 `Sources/Refine.swift`）：`X-Siku-App` 只是随应用公开的
客户端标识，**不是鉴权密钥**；`Authorization: Bearer siku-dev-<uuid>` 也只用于设备维度的公平限流。
Worker 同时按设备 token、Cloudflare 边缘看到的客户端 IP、以及全局固定 key 做三层限流，避免调用方
只轮换 token 就绕过保护。它仍不是完整的用户鉴权/按量计费系统；真要精细计费，应接入有身份的账号
或服务端签发令牌，并参考 `siku-reader/server/siku-proxy` 的 SQLite 额度 + 管理后台。

## 部署

```bash
cd server/aftermeet-asr-proxy
npm install

# 密钥：复用 Clicky 项目（/Users/steve/Dev/clicky-agent/worker）里已经开通的火山 App Key，
# 即 wrangler.jsonc 里 VOLCENGINE_TTS_API_KEY 对应的那个值。自己粘贴，不要经手第三方。
npx wrangler secret put VOLCENGINE_API_KEY --env staging
npx wrangler secret put VOLCENGINE_API_KEY --env production

npm run deploy:staging
npm run deploy:production
```

部署成功后 wrangler 会打印 workers.dev 地址（形如
`https://aftermeet-asr-proxy-production.<your-subdomain>.workers.dev`），把它填进
AfterMeet「设置 → 转写引擎 → 代理地址」即可。地址留空会使用 AfterMeet 内置的公共代理；要完全走
本地 whisper.cpp，请在设置里关闭「云端转写」。

## 验证

```bash
curl -s https://aftermeet-asr-proxy-production.<your-subdomain>.workers.dev/health
```

应返回 `{"service":"aftermeet-asr-proxy","environment":"production","status":"ok"}`。
真正的转写链路要在 AfterMeet 里实际录一段会议来验证（设置页配好地址后开始录制，看状态栏是否显示
「录制中 · 云端转写 · 实时」）。

## 如果要换成更完整的按量配额

当前只有设备/IP/全局三层 60 秒连接数限流，不区分「今天用了多少分钟音频」。如果用量起来了想加日额度 +
管理后台，可以参考 `VOLCENGINE_ASR_RESOURCE_ID` 换成按量的 `volc.seedasr.sauc.concurrent`，再加一层
KV/D1 记录每个 device token 当天的连接时长，模式可以照抄 `siku-proxy` 的 `/v1/usage` + admin 密码
那一套。
