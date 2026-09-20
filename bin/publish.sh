#!/usr/bin/env bash
# Dear SNS — Instagram 발행
#
# 실행: .github/workflows/publish-instagram.yml 이 매일 12:00 UTC(21:00 KST)에 호출한다.
# 입력: 환경변수 IG_USER_ID · IG_TOKEN · ASSET_BASE_URL (워크플로가 Secrets 에서 주입)
# 큐:   queue/YYYY-MM-DD.json  (없으면 올릴 게 없는 정상 상황 → 성공 종료)
# 기록: log.md 에 한 줄 append (커밋은 워크플로가 한다)
#
# 수동 실행:
#   bin/publish.sh                  오늘(Asia/Seoul) 큐 발행
#   bin/publish.sh --dry-run        발행하지 않고 점검만
#   bin/publish.sh 2026-09-22       특정 날짜
#
# 주의: 토큰이 로그에 남지 않게 한다. set -x 를 켠 채로 실행하지 말 것.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${LOG_FILE:-$REPO_ROOT/log.md}"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/state/tokens.json}"
IG_API="https://graph.instagram.com/v21.0"   # Instagram Login 경로. graph.facebook.com 아님
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
die() { say "FAIL  $*"; exit 1; }

# 토큰이 에러 본문에 섞여 나가지 않게 가린다
redact() {
  local s="${1:-}"
  if [ -n "${IG_TOKEN:-}" ]; then s="${s//$IG_TOKEN/***}"; fi
  printf '%s' "$s"
}

# YYYY-MM-DD → epoch (GNU date 우선, macOS 로컬 테스트용 BSD date 폴백)
epoch_of_date() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$1" +%s
}

# 토큰이 살아 있는지 실제로 물어본다.
# 아래 만료일 계산은 "60일 지났나"만 알려줄 뿐,
# 폐기·권한 변경·비밀번호 변경으로 무효화된 토큰은 잡지 못한다.
check_token() {
  local resp name
  resp="$(curl -sS --max-time 20 -G "$IG_API/$IG_USER_ID" \
          --data-urlencode "fields=username" -d "access_token=$IG_TOKEN" 2>/dev/null || true)"
  name="$(jq -r '.username // empty' <<<"$resp" 2>/dev/null || true)"
  [ -n "$name" ] || die "토큰이 유효하지 않습니다 — $(redact "$resp")"
  say "토큰 정상 — Instagram @$name"
}

# ── 1. 자격증명 ────────────────────────────────────────────────
: "${IG_USER_ID:?IG_USER_ID 없음 — 저장소 Secret 을 확인하세요}"
: "${IG_TOKEN:?IG_TOKEN 없음 — 저장소 Secret 을 확인하세요}"
: "${ASSET_BASE_URL:?ASSET_BASE_URL 없음 — 워크플로가 주입합니다}"

# ── 2. 토큰 만료 점검 (state/tokens.json 의 발급일 기준) ───────
if [ -f "$STATE_FILE" ]; then
  issued="$(jq -r '.instagram.issued_at // empty' "$STATE_FILE")"
  if [ -n "$issued" ]; then
    days_left=$(( ( $(epoch_of_date "$issued") + 60 * 86400 - $(date -u +%s) ) / 86400 ))
    if [ "$days_left" -lt 0 ]; then
      die "IG 토큰이 ${days_left#-}일 전에 만료됐습니다. 만료된 토큰은 갱신할 수 없어 재발급이 필요합니다."
    elif [ "$days_left" -le 14 ]; then
      say "경고  IG 토큰 만료까지 ${days_left}일 — refresh-tokens 워크플로를 확인하세요."
    fi
  fi
fi

# ── 3. 오늘 큐 ────────────────────────────────────────────────
Q="$REPO_ROOT/queue/$DATE.json"
if [ ! -f "$Q" ]; then
  say "큐 없음: $DATE — 오늘은 올릴 게 없습니다."
  exit 0
fi

jq -e --arg L "$QUEUE_LANG" '.[$L].caption and (.[$L].images | type == "array" and length > 0)' "$Q" >/dev/null \
  || die "큐 형식 오류: queue/$DATE.json (.$QUEUE_LANG.caption / .$QUEUE_LANG.images 필요)"

FEATURE="$(jq -r '.featureId // "—"' "$Q")"
DAY="$(jq -r '.day // "—"' "$Q")"
CAPTION="$(jq -r --arg L "$QUEUE_LANG" '.[$L].caption' "$Q")"

IMAGES=()
while IFS= read -r line; do
  [ -n "$line" ] && IMAGES+=("$line")
done < <(jq -r --arg L "$QUEUE_LANG" '.[$L].images[]' "$Q")   # mapfile 대신 — macOS bash 3.2 에서도 돈다

[ "${#IMAGES[@]}" -gt 0 ] || die "$DATE 큐에 이미지가 없습니다."
[ "${#IMAGES[@]}" -le 10 ] || die "캐러셀은 최대 10장입니다 (현재 ${#IMAGES[@]}장)."

# 캡션 한도 — Instagram 은 2,200자 / 해시태그 30개
cap_len=${#CAPTION}
[ "$cap_len" -le 2200 ] || die "캡션이 ${cap_len}자입니다 (한도 2,200자)."
tag_count="$(grep -o '#' <<<"$CAPTION" | wc -l | tr -d ' ')"
[ "$tag_count" -le 30 ] || die "해시태그가 ${tag_count}개입니다 (한도 30개)."

say "---- $DATE  Day $DAY  $FEATURE  [$QUEUE_LANG]  이미지 ${#IMAGES[@]}장  캡션 ${cap_len}자 ----"

# ── 4. 이미지 공개 URL 확인 ────────────────────────────────────
# Meta 는 이미지를 업로드받지 않고 URL 을 cURL 로 가져간다.
# 여기서 200 을 확인하지 않으면 빈 게시물이 올라가거나 컨테이너가 조용히 실패한다.
URLS=()
for img in "${IMAGES[@]}"; do
  name="$(basename "$img")"
  [ -f "$REPO_ROOT/images/$name" ] || die "이미지 파일 없음: images/$name"
  url="$ASSET_BASE_URL/$name"
  code="$(curl -s -o /dev/null -w '%{http_code}' -I --max-time 20 "$url" || true)"
  [ "$code" = "200" ] \
    || die "이미지 접근 불가 ($code): $url — 저장소가 공개인지, 이미지가 push 됐는지 확인하세요."
  URLS+=("$url")
done
say "이미지 ${#URLS[@]}장 공개 확인 완료 (HTTP 200)"

if [ "$DRY_RUN" = "1" ]; then
  printf '\n─── 캡션 미리보기 ───\n%s\n─────────────────────\n\n' "$CAPTION"
  check_token
  say "DRY RUN — 점검만 하고 발행하지 않았습니다."
  exit 0
fi

# ── 5. Instagram 발행 ──────────────────────────────────────────
check_token

ig_post() {  # ig_post <edge> <curl args...>
  local edge="$1"; shift
  curl -sS --max-time 60 -X POST "$IG_API/$IG_USER_ID/$edge" "$@" -d "access_token=$IG_TOKEN"
}

# Meta 는 실패해도 HTTP 200 에 에러 바디를 담아 보내는 경우가 있다. 본문을 항상 확인한다.
check_response() {  # check_response <response> <context>
  local resp="$1" ctx="$2" msg
  msg="$(jq -r 'if .error then ((.error.message // "unknown")
                 + " [type=" + (.error.type // "?")
                 + " code=" + ((.error.code // 0) | tostring) + "]") else empty end' <<<"$resp" 2>/dev/null || true)"
  [ -z "$msg" ] || die "$ctx: $msg"
  jq -e 'has("id")' <<<"$resp" >/dev/null 2>&1 || die "$ctx: 예상치 못한 응답 — $(redact "$resp")"
}

if [ "${#URLS[@]}" -eq 1 ]; then
  resp="$(ig_post media --data-urlencode "image_url=${URLS[0]}" \
                        --data-urlencode "caption=$CAPTION")"
  check_response "$resp" "컨테이너 생성 실패"
  CREATION="$(jq -r '.id' <<<"$resp")"
else
  # 캐러셀 — 각 장을 is_carousel_item 으로 만든 뒤 하나로 묶는다
  CHILDREN=()
  for url in "${URLS[@]}"; do
    r="$(ig_post media --data-urlencode "image_url=$url" -d "is_carousel_item=true")"
    check_response "$r" "캐러셀 항목 생성 실패"
    CHILDREN+=("$(jq -r '.id' <<<"$r")")
    sleep 2
  done
  kids="$(IFS=,; echo "${CHILDREN[*]}")"
  r="$(ig_post media -d "media_type=CAROUSEL" -d "children=$kids" \
                     --data-urlencode "caption=$CAPTION")"
  check_response "$r" "캐러셀 컨테이너 생성 실패"
  CREATION="$(jq -r '.id' <<<"$r")"
fi

say "컨테이너 생성 $CREATION — 30초 대기(공식 권장)"
sleep 30

# 컨테이너 상태 확인: 공식 권장은 1분 간격 · 최대 5분
ready=0
for attempt in 1 2 3 4 5; do
  st="$(curl -sS --max-time 30 -G "$IG_API/$CREATION" \
        --data-urlencode "fields=status_code" -d "access_token=$IG_TOKEN" || true)"
  code="$(jq -r '.status_code // empty' <<<"$st" 2>/dev/null || true)"
  case "$code" in
    FINISHED|PUBLISHED) ready=1; break ;;
    ERROR|EXPIRED)      die "컨테이너 상태 $code — 이미지 URL 과 큐를 확인하세요." ;;
    IN_PROGRESS)        say "처리 중… ($attempt/5)"; sleep 60 ;;
    *)                  say "상태 조회 불가 — 대기 후 발행을 시도합니다."; ready=1; break ;;
  esac
done
[ "$ready" = "1" ] || die "컨테이너가 5분 안에 준비되지 않았습니다 ($CREATION)."

resp="$(ig_post media_publish -d "creation_id=$CREATION")"
check_response "$resp" "발행 실패"
IG_POST_ID="$(jq -r '.id' <<<"$resp")"
say "Instagram 발행 완료  post_id=$IG_POST_ID"

# ── 6. 기록 ───────────────────────────────────────────────────
printf '| %s | %s | %s | %s | 게시 | IG %s |\n' \
  "$DATE" "$DAY" "$FEATURE" "$ACCOUNT" "$IG_POST_ID" >> "$LOG_FILE"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '### Instagram 발행 완료\n\n- 날짜: %s (Day %s · %s)\n- 이미지: %s장\n- post_id: `%s`\n' \
    "$DATE" "$DAY" "$FEATURE" "${#URLS[@]}" "$IG_POST_ID" >> "$GITHUB_STEP_SUMMARY"
fi

say "완료. Threads 는 2시간 뒤 publish-threads 워크플로가 올립니다."
