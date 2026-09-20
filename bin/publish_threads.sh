#!/usr/bin/env bash
# Dear SNS — Threads 발행 (Instagram 2시간 뒤, 23:00 KST)
#
# 같은 큐 파일의 .ko.threads 문장을 쓴다. 이미지 없이 텍스트만 올린다.
# 이유: 브랜드 가이드 §4.1 — Threads 는 인스타 캡션을 복사하는 곳이 아니라
#       "왜 이렇게 만들었는지"를 만든 사람의 목소리로 한 문장 쓰는 곳이다.
#
# 입력: 환경변수 THREADS_USER_ID · THREADS_TOKEN (워크플로가 Secrets 에서 주입)
# 기록: log.md 에 한 줄 append (커밋은 워크플로가 한다)
#
# 수동 실행:
#   bin/publish_threads.sh                오늘(Asia/Seoul) 큐 발행
#   bin/publish_threads.sh --dry-run      발행하지 않고 점검만
#   bin/publish_threads.sh 2026-09-22     특정 날짜

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${LOG_FILE:-$REPO_ROOT/log.md}"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/state/tokens.json}"
TH_API="https://graph.threads.net/v1.0"
QUEUE_LANG="${QUEUE_LANG:-en}"               # 큐 JSON 안에서 읽을 언어 키 (.en / .ko)
ACCOUNT="${ACCOUNT:-@dear.couple.app}"       # log.md 에 남길 계정 표기

DRY_RUN=0
DATE="$(TZ=Asia/Seoul date +%F)"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) DATE="$arg" ;;
    *) printf '알 수 없는 인자: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s  %s\n' "$(TZ=Asia/Seoul date '+%F %T')" "$*"; }
die() { say "FAIL  threads: $*"; exit 1; }

redact() {
  local s="${1:-}"
  if [ -n "${THREADS_TOKEN:-}" ]; then s="${s//$THREADS_TOKEN/***}"; fi
  printf '%s' "$s"
}

epoch_of_date() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$1" +%s
}

# ── 1. 자격증명 ────────────────────────────────────────────────
: "${THREADS_USER_ID:?THREADS_USER_ID 없음 — 저장소 Secret 을 확인하세요}"
: "${THREADS_TOKEN:?THREADS_TOKEN 없음 — 저장소 Secret 을 확인하세요}"

# ── 2. 토큰 만료 점검 ──────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
  issued="$(jq -r '.threads.issued_at // empty' "$STATE_FILE")"
  if [ -n "$issued" ]; then
    days_left=$(( ( $(epoch_of_date "$issued") + 60 * 86400 - $(date -u +%s) ) / 86400 ))
    if [ "$days_left" -lt 0 ]; then
      die "Threads 토큰이 ${days_left#-}일 전에 만료됐습니다. 재발급이 필요합니다."
    elif [ "$days_left" -le 14 ]; then
      say "경고  Threads 토큰 만료까지 ${days_left}일 — refresh-tokens 워크플로를 확인하세요."
    fi
  fi
fi

# ── 3. 오늘 큐 ────────────────────────────────────────────────
Q="$REPO_ROOT/queue/$DATE.json"
if [ ! -f "$Q" ]; then
  say "큐 없음: $DATE — 오늘은 올릴 게 없습니다."
  exit 0
fi

TEXT="$(jq -r --arg L "$QUEUE_LANG" '.[$L].threads // empty' "$Q")"
if [ -z "$TEXT" ]; then
  say "$DATE 큐에 Threads 문장이 없습니다 — 건너뜁니다."
  exit 0
fi

# Threads 텍스트 한도 500자
txt_len=${#TEXT}
[ "$txt_len" -le 500 ] || die "문장이 ${txt_len}자입니다 (한도 500자)."

say "---- threads $DATE  [$QUEUE_LANG]  ${txt_len}자 ----"

if [ "$DRY_RUN" = "1" ]; then
  printf '\n─── Threads 문장 미리보기 ───\n%s\n─────────────────────────────\n\n' "$TEXT"
  say "DRY RUN — 점검만 하고 발행하지 않았습니다."
  exit 0
fi

# ── 4. 발행 ───────────────────────────────────────────────────
check_response() {  # check_response <response> <context>
  local resp="$1" ctx="$2" msg
  msg="$(jq -r 'if .error then ((.error.message // "unknown")
                 + " [type=" + (.error.type // "?")
                 + " code=" + ((.error.code // 0) | tostring) + "]") else empty end' <<<"$resp" 2>/dev/null || true)"
  [ -z "$msg" ] || die "$ctx: $msg"
  jq -e 'has("id")' <<<"$resp" >/dev/null 2>&1 || die "$ctx: 예상치 못한 응답 — $(redact "$resp")"
}

resp="$(curl -sS --max-time 60 -X POST "$TH_API/$THREADS_USER_ID/threads" \
  -d "media_type=TEXT" \
  --data-urlencode "text=$TEXT" \
  -d "access_token=$THREADS_TOKEN")"
check_response "$resp" "컨테이너 생성 실패"
CREATION="$(jq -r '.id' <<<"$resp")"

say "컨테이너 $CREATION — 30초 대기(공식 권장)"
sleep 30

resp="$(curl -sS --max-time 60 -X POST "$TH_API/$THREADS_USER_ID/threads_publish" \
  -d "creation_id=$CREATION" \
  -d "access_token=$THREADS_TOKEN")"
check_response "$resp" "발행 실패"
TH_POST_ID="$(jq -r '.id' <<<"$resp")"
say "Threads 발행 완료  post_id=$TH_POST_ID"

# ── 5. 기록 ───────────────────────────────────────────────────
printf '| %s | — | — | Threads %s | 게시 | TH %s |\n' \
  "$DATE" "$ACCOUNT" "$TH_POST_ID" >> "$LOG_FILE"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### Threads 발행 완료\n\n- 날짜: %s\n- post_id: `%s`\n' "$DATE" "$TH_POST_ID" >> "$GITHUB_STEP_SUMMARY"
fi
