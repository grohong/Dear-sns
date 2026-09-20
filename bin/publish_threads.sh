#!/usr/bin/env bash
# Dear SNS — Threads 발행 (Instagram 2시간 뒤, 23:00 KST)
#
# 같은 큐 파일의 .en.threads 문장을 쓴다(QUEUE_LANG 으로 바꿀 수 있다).
# 글이 본문이고 이미지는 선택이다 — 브랜드 가이드 §4.1: Threads 는 인스타 캡션을
# 복사하는 곳이 아니라 "왜 이렇게 만들었는지"를 만든 사람의 목소리로 쓰는 곳이다.
#
#   .en.threadsImages 없음 → TEXT (글만)
#   1장                    → IMAGE
#   2장 이상               → CAROUSEL (API 한도 20장)
#
# 4장짜리 인스타 캐러셀을 그대로 옮기지 말 것. 두 피드가 같아지면 둘 다 팔로우할 이유가 없다.
#
# 입력: 환경변수 THREADS_USER_ID · THREADS_TOKEN (워크플로가 Secrets 에서 주입)
#       ASSET_BASE_URL — 이미지를 쓸 때만 필요(공개 URL. Meta 가 cURL 로 가져간다)
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

# 토큰이 살아 있는지 실제로 물어본다.
# state/tokens.json 의 발급일 계산은 "60일 지났나"만 알려줄 뿐,
# 폐기·권한 변경·비밀번호 변경으로 무효화된 토큰은 잡지 못한다.
check_token() {
  local resp name
  resp="$(curl -sS --max-time 20 -G "$TH_API/$THREADS_USER_ID" \
          --data-urlencode "fields=username" -d "access_token=$THREADS_TOKEN" 2>/dev/null || true)"
  name="$(jq -r '.username // empty' <<<"$resp" 2>/dev/null || true)"
  [ -n "$name" ] || die "토큰이 유효하지 않습니다 — $(redact "$resp")"
  say "토큰 정상 — Threads @$name"
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

# ── 3b. 이미지(선택) ──────────────────────────────────────────
# Meta 는 이미지를 업로드받지 않고 URL 을 cURL 로 가져간다. 200 을 미리 확인하지 않으면
# 컨테이너가 조용히 실패한다 — publish.sh 와 같은 이유, 같은 방식.
IMAGES=()
while IFS= read -r line; do
  [ -n "$line" ] && IMAGES+=("$line")
done < <(jq -r --arg L "$QUEUE_LANG" '.[$L].threadsImages // [] | .[]' "$Q")

URLS=()
if [ "${#IMAGES[@]}" -gt 0 ]; then
  : "${ASSET_BASE_URL:?ASSET_BASE_URL 없음 — 이미지를 쓰려면 워크플로가 주입해야 합니다}"
  [ "${#IMAGES[@]}" -le 20 ] || die "Threads 캐러셀은 최대 20장입니다 (현재 ${#IMAGES[@]}장)."
  for img in "${IMAGES[@]}"; do
    name="$(basename "$img")"
    [ -f "$REPO_ROOT/images/$name" ] || die "이미지 파일 없음: images/$name"
    # Threads 는 8MB 를 넘기면 거부한다
    bytes="$(wc -c < "$REPO_ROOT/images/$name" | tr -d ' ')"
    [ "$bytes" -le 8388608 ] || die "images/$name 이 ${bytes}바이트입니다 (Threads 한도 8MB)."
    url="$ASSET_BASE_URL/$name"
    code="$(curl -s -o /dev/null -w '%{http_code}' -I --max-time 20 "$url" || true)"
    [ "$code" = "200" ] \
      || die "이미지 접근 불가 ($code): $url — 저장소가 공개인지, push 됐는지 확인하세요."
    URLS+=("$url")
  done
  say "이미지 ${#URLS[@]}장 공개 확인 완료 (HTTP 200)"
fi

if [ "$DRY_RUN" = "1" ]; then
  printf '\n─── Threads 문장 미리보기 ───\n%s\n─────────────────────────────\n' "$TEXT"
  if [ "${#URLS[@]}" -gt 0 ]; then
    printf '이미지 %s장: %s\n' "${#URLS[@]}" "$(IFS=', '; echo "${IMAGES[*]}")"
  else
    printf '이미지 없음 — TEXT 로 올라갑니다.\n'
  fi
  printf '\n'
  check_token
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

check_token

th_post() {  # th_post <edge> <curl args...>
  local edge="$1"; shift
  curl -sS --max-time 60 -X POST "$TH_API/$THREADS_USER_ID/$edge" "$@" \
    -d "access_token=$THREADS_TOKEN"
}

if [ "${#URLS[@]}" -eq 0 ]; then
  resp="$(th_post threads -d "media_type=TEXT" --data-urlencode "text=$TEXT")"
  check_response "$resp" "컨테이너 생성 실패"
elif [ "${#URLS[@]}" -eq 1 ]; then
  resp="$(th_post threads -d "media_type=IMAGE" \
                          --data-urlencode "image_url=${URLS[0]}" \
                          --data-urlencode "text=$TEXT")"
  check_response "$resp" "IMAGE 컨테이너 생성 실패"
else
  # 캐러셀 — 각 장을 is_carousel_item 으로 만든 뒤 하나로 묶는다. 본문은 묶는 쪽에만 싣는다.
  CHILDREN=()
  for url in "${URLS[@]}"; do
    r="$(th_post threads -d "media_type=IMAGE" -d "is_carousel_item=true" \
                         --data-urlencode "image_url=$url")"
    check_response "$r" "캐러셀 항목 생성 실패"
    CHILDREN+=("$(jq -r '.id' <<<"$r")")
    sleep 2
  done
  kids="$(IFS=,; echo "${CHILDREN[*]}")"
  resp="$(th_post threads -d "media_type=CAROUSEL" -d "children=$kids" \
                          --data-urlencode "text=$TEXT")"
  check_response "$resp" "캐러셀 컨테이너 생성 실패"
fi
CREATION="$(jq -r '.id' <<<"$resp")"

say "컨테이너 $CREATION — 30초 대기(공식 권장)"
sleep 30

resp="$(th_post threads_publish -d "creation_id=$CREATION")"
check_response "$resp" "발행 실패"
TH_POST_ID="$(jq -r '.id' <<<"$resp")"
say "Threads 발행 완료  post_id=$TH_POST_ID"

# ── 5. 기록 ───────────────────────────────────────────────────
printf '| %s | — | — | Threads %s | 게시 | TH %s |\n' \
  "$DATE" "$ACCOUNT" "$TH_POST_ID" >> "$LOG_FILE"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### Threads 발행 완료\n\n- 날짜: %s\n- post_id: `%s`\n' "$DATE" "$TH_POST_ID" >> "$GITHUB_STEP_SUMMARY"
fi
