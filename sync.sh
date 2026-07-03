#!/usr/bin/env bash
# AfterMeet 数据同步 —— 读真实飞书会议 → 豆包提炼 → 写 meetings.json（app 读它）。
# 这是"后端"的本地替身；将来 ECS 常驻 daemon 写同一份 store，app 不用改。
#
#   SIKU_TOKEN=<siku-proxy access token> ./sync.sh [meeting_count]
#
set -euo pipefail
: "${SIKU_TOKEN:?需要设置 SIKU_TOKEN（siku-proxy 的 access token）}"
# zhiwenai.cc 的 TLS 在国内会被 SNI reset；直连 IP + Host 头绕过（根治是 Clash 给该域名/IP 加 DIRECT 规则）
SIKU_IP="${SIKU_IP:-14.103.38.223}"
SIKU_HOST="${SIKU_HOST:-zhiwenai.cc}"
SIKU_MODEL="${SIKU_MODEL:-doubao-seed-2-0-mini-260428}"
START="${START:-2026-06-01}"
END="${END:-2026-06-15}"
LIMIT="${1:-3}"

OUT_DIR="$HOME/Library/Application Support/AfterMeet"
OUT="$OUT_DIR/meetings.json"
mkdir -p "$OUT_DIR"

SYS='你是会议纪要提炼助手。基于会议逐字稿(含说话人 user-name 与时间戳)独立分析，输出严格 JSON(不要 markdown 代码块、不要多余文字)。Schema:
{
 "title":"会议标题",
 "dateLabel":"如 6月12日 周五（从逐字稿头部会议时间提取）",
 "durationLabel":"如 17:30–18:24",
 "participants":整数(逐字稿里出现的不同说话人数量),
 "organizer":"组织者姓名或null",
 "summary":"一段话客观摘要，中文，不超过120字",
 "decisions":[{"no":"01","text":"明确达成的结论/决策"}],
 "todos":[{"text":"行动项","owner":"姓名或null","due":"M/D或Q3等或null","confidence":"high或low"}],
 "disputes":[{"title":"分歧/未决项","body":"说明"}],
 "nextAgenda":["建议下次议题"],
 "excerpts":[{"time":"HH:MM","who":"说话人","text":"代表性原话"}]
}
规则:负责人只有逐字稿明确指派时才填 owner，否则 owner=null 且 confidence=low(宁可多问不可派错)。decisions/disputes 没有就空数组。excerpts 选 4-6 条能体现讨论的关键原话。红线:基于逐字稿本身分析，不要照搬已有 AI 纪要。只输出 JSON。'

echo "▸ 搜索会议 $START..$END"
ids=$(lark-cli vc +search --start "$START" --end "$END" --format json 2>/dev/null \
        | jq -r '.data.items[]?.id')

tmp="$(mktemp -d)"
n=0
for mid in $ids; do
  if [ "$n" -ge "$LIMIT" ]; then break; fi
  vt=$(lark-cli vc +notes --meeting-ids "$mid" --format json 2>/dev/null \
         | jq -r '.data.notes[0].verbatim_doc_token // empty' || true)
  if [ -z "$vt" ]; then continue; fi
  content=$(lark-cli docs +fetch --api-version v2 --doc "$vt" --doc-format markdown 2>/dev/null \
              | jq -r '.data.document.content // empty' || true)
  if [ "${#content}" -lt 400 ]; then continue; fi

  echo "  ▸ 提炼 $mid（${#content} 字）…"
  payload=$(jq -n --arg m "$SIKU_MODEL" --arg sys "$SYS" --arg txt "$content" \
    '{model:$m,messages:[{role:"system",content:$sys},{role:"user",content:("会议逐字稿如下:\n\n"+$txt)}],temperature:0.2,max_tokens:3000}')
  refined=$(curl -sk --max-time 180 "https://$SIKU_IP/v1/chat/completions" \
              -H "Host: $SIKU_HOST" \
              -H "Authorization: Bearer $SIKU_TOKEN" -H "Content-Type: application/json" \
              -d "$payload" | jq -r '.choices[0].message.content // empty' \
              | sed 's/^```json//; s/^```//; s/```$//' || true)
  if ! echo "$refined" | jq -e . >/dev/null 2>&1; then
    echo "    ✗ 返回非合法 JSON，跳过"; continue
  fi
  echo "$refined" | jq --arg id "$mid" '. + {meeting_id:$id}' > "$tmp/$n.json"
  n=$((n + 1))
done

if [ "$n" -gt 0 ]; then
  jq -s '{generated_at:(now|todate), meetings:.}' "$tmp"/*.json > "$OUT"
else
  echo '{"generated_at":null,"meetings":[]}' > "$OUT"
fi
rm -rf "$tmp"
echo "▸ 写入 $n 场会议 → $OUT"
