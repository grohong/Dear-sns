#!/usr/bin/env bash
# Dear SNS — 토큰 갱신 / 만료 감시
#
# 실행: .github/workflows/refresh-tokens.yml 이 매주 월요일 03:00 UTC(12:00 KST)에 호출한다.
#
# 토큰은 60일이면 만료되고, **만료된 뒤에는 갱신할 수 없다.** 이 시스템에서 가장 흔한 고장이라
# 주 1회 굴려서 만료일을 늘 60일 뒤로 밀어 둔다.
#
# 두 가지 모드 — GH_PAT(=GH_TOKEN) 유무로 자동 결정한다.
#   A. 자동 갱신: 새 토큰을 받아 `gh secret set` 으로 저장소 Secret 에 덮어쓴다.
#   B. 경고만:   남은 기간이 14일 미만이면 GitHub Issue 를 연다. 토큰 값은 절대 Issue 에 쓰지 않는다.
#
# 갱신 조건(양쪽 공통): 토큰이 유효하고, 발급 후 24시간이 지났을 것.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/state/tokens.json}"
WARN_DAYS="${WARN_DAYS:-14}"
TODAY="$(TZ=Asia/Seoul date +%F)"

say() { printf '%s  %s\n' "$(TZ=Asia/Seoul date '+%F %T')" "$*"; }
die() { say "FAIL  $*"; exit 1; }

epoch_of_date() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$1" +%s
}
date_plus_days() {  # date_plus_days <YYYY-MM-DD> <days>
  date -u -d "$1 +$2 days" +%F 2>/dev/null || date -u -j -v"+$2"d -f '%Y-%m-%d' "$1" +%F
}

[ -f "$STATE_FILE" ] || die "상태 파일 없음: $STATE_FILE"

AUTO=0
if [ -n "${GH_TOKEN:-}" ] && [ "${REFRESH_MODE:-auto}" != "warn" ]; then AUTO=1; fi
if [ "$AUTO" = "1" ]; then say "모드 A — 자동 갱신 (GH_PAT 있음)"; else say "모드 B — 경고만 (GH_PAT 없음)"; fi

FAILED=0
WARNINGS=()

open_issue() {  # open_issue <title> <body>
  local title="$1" body="$2" existing
  if ! command -v gh >/dev/null 2>&1; then say "gh 없음 — Issue 를 만들지 못했습니다: $title"; return 0; fi
  existing="$(gh issue list --state open --search "in:title $title" --json title --jq 'length' 2>/dev/null || echo 0)"
  if [ "${existing:-0}" != "0" ]; then say "이미 열린 Issue 가 있습니다 — 새로 만들지 않습니다: $title"; return 0; fi
  gh issue create --title "$title" --body "$body" >/dev/null && say "Issue 생성: $title"
}

# refresh_one <channel> <secret_name> <token_value> <refresh_url> <grant_type>
refresh_one() {
  local ch="$1" secret_name="$2" token="${3:-}" url="$4" grant="$5"
  local issued days_left resp new_token expires_in new_expiry

  if [ -z "$token" ]; then
    say "[$ch] 토큰 Secret 이 비어 있습니다 — 건너뜁니다 (아직 발급 전이면 정상)."
    return 0
  fi

  issued="$(jq -r --arg c "$ch" '.[$c].issued_at // empty' "$STATE_FILE")"
  if [ -z "$issued" ]; then
    WARNINGS+=("[$ch] state/tokens.json 에 발급일이 없어 남은 기간을 계산할 수 없습니다.")
    issued="$TODAY"
  fi

  days_left=$(( ( $(epoch_of_date "$issued") + 60 * 86400 - $(date -u +%s) ) / 86400 ))
  local age_days=$(( ( $(date -u +%s) - $(epoch_of_date "$issued") ) / 86400 ))
  say "[$ch] 발급 $issued · 남은 기간 ${days_left}일"

  if [ "$days_left" -lt 0 ]; then
    WARNINGS+=("[$ch] 토큰이 만료됐습니다. 갱신이 불가능하니 Meta 콘솔에서 재발급해야 합니다.")
    FAILED=1
    return 0
  fi

  if [ "$AUTO" != "1" ]; then
    if [ "$days_left" -lt "$WARN_DAYS" ]; then
      WARNINGS+=("[$ch] 만료까지 ${days_left}일 — 수동 갱신이 필요합니다.")
    fi
    return 0
  fi

  if [ "$age_days" -lt 1 ]; then
    say "[$ch] 발급 후 24시간이 지나지 않아 갱신을 건너뜁니다."
    return 0
  fi

  resp="$(curl -sS --max-time 30 -G "$url" \
          --data-urlencode "grant_type=$grant" \
          --data-urlencode "access_token=$token" || true)"

  local err
  err="$(jq -r 'if .error then ((.error.message // .error // "unknown")|tostring) else empty end' <<<"$resp" 2>/dev/null || true)"
  if [ -n "$err" ]; then
    WARNINGS+=("[$ch] 갱신 실패: $err")
    FAILED=1
    return 0
  fi

  new_token="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null || true)"
  if [ -z "$new_token" ]; then
    WARNINGS+=("[$ch] 갱신 응답에 access_token 이 없습니다.")
    FAILED=1
    return 0
  fi
  expires_in="$(jq -r '.expires_in // 5184000' <<<"$resp")"

  printf '%s' "$new_token" | gh secret set "$secret_name" --repo "$GITHUB_REPOSITORY" \
    || { WARNINGS+=("[$ch] gh secret set 실패 — PAT 권한(Secrets: Read and write)을 확인하세요."); FAILED=1; return 0; }

  new_expiry="$(date_plus_days "$TODAY" "$(( expires_in / 86400 ))")"
  tmp="$(mktemp)"
  jq --arg c "$ch" --arg d "$TODAY" --arg e "$new_expiry" --argjson s "$expires_in" \
     '.[$c].issued_at = $d | .[$c].expires_at = $e | .[$c].expires_in_seconds = $s | .updated_at = $d' \
     "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  say "[$ch] 갱신 완료 — Secret $secret_name 덮어씀 · 새 만료일 $new_expiry"
}

refresh_one instagram IG_TOKEN      "${IG_TOKEN:-}" \
  "https://graph.instagram.com/refresh_access_token" ig_refresh_token
refresh_one threads   THREADS_TOKEN "${THREADS_TOKEN:-}" \
  "https://graph.threads.net/refresh_access_token" th_refresh_token

# ── 결과 ──────────────────────────────────────────────────────
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  say "경고 ${#WARNINGS[@]}건"
  for w in "${WARNINGS[@]}"; do say "  - $w"; done

  body="$(printf 'Dear SNS 토큰 점검 결과입니다. (%s)\n\n' "$TODAY")"
  for w in "${WARNINGS[@]}"; do body+="$(printf -- '- %s\n' "$w")"$'\n'; done
  body+=$'\n'"발급·갱신 절차는 저장소 README 의 '토큰' 절을 보세요. **토큰 값을 이 Issue 에 붙여넣지 마세요.**"
  open_issue "Dear SNS 토큰 갱신 필요" "$body"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '### 토큰 점검 (%s)\n\n| 채널 | 발급일 | 만료 예정 |\n|---|---|---|\n' "$TODAY"
    jq -r '["instagram","threads"][] as $c | "| \($c) | \(.[$c].issued_at // "—") | \(.[$c].expires_at // "—") |"' "$STATE_FILE"
  } >> "$GITHUB_STEP_SUMMARY"
fi

[ "$FAILED" = "0" ] || die "토큰 점검에서 문제가 있습니다 (위 경고 참고)."
say "토큰 점검 완료."
