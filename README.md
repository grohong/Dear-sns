# Dear SNS — 자동 발행

Instagram [@dear.couple.app](https://instagram.com/dear.couple.app) 과 Threads @dear.couple.app 에
**매일 영어 게시물 하나를 자동으로 올리는** 저장소. 콘텐츠(이미지·캡션)를 여기에 두고, 저장소가 이미지 호스팅도 겸한다.

**1차 시장은 영어권(미국·영국·호주)이고 계정은 영어 단독이다.** 한국어 자산은 `Marketing/sns/` 에 보존돼 있고 발행하지 않는다.

원본 문서는 앱 저장소 옆 `Dear/Marketing/` 에 있다 — 무엇을 올릴지는 `Dear-Features.md`,
어떻게 말할지는 `Dear-Brand-Guide.md`(영어 보이스 §5.3), 계정·API 기록은 `Dear-SNS-Setup.md`.

---

## 매일 일어나는 일

| 시각 | 워크플로 | 예약 | 하는 일 |
|---|---|---|---|
| 21:00 ET | `publish · instagram` | ⏸ **꺼짐** | `queue/오늘.json` → 이미지 URL 200 확인 → Instagram 발행 → `log.md` 커밋 |
| 23:00 ET | `publish · threads` | ⏸ **꺼짐** | 같은 큐의 `.en.threads` 한 문장을 텍스트로 발행 |
| 월 12:00 KST | `refresh · tokens` | ✅ 켜짐 | 토큰을 굴려 만료일을 60일 뒤로 밀어 둠 |

> **발행 예약은 꺼 둔 상태다**(2026-09-20). 지금 발행은 Actions 탭에서 **수동 실행할 때만** 일어난다.
> 손으로 몇 건 올려 보고 괜찮으면 §예약 켜기 로 넘어간다.
> 토큰 갱신만 예약대로 돈다 — 게시물을 올리지 않고, 토큰이 조용히 만료되는 걸 막아야 해서 켜 뒀다.

그날 큐 파일이 없으면 **올릴 게 없는 정상 상황**으로 보고 성공으로 끝낸다. 억지로 채우지 않는다.

주의할 것 두 가지.

- **cron 은 정시에 돌지 않는다.** 부하가 몰리면 수십 분에서 수 시간까지 밀린다. 정확한 시각이 필요하면 수동 실행을 쓴다.
- **cron 은 UTC 고정이라 서머타임을 따라가지 않는다.** 11월 초 미국이 EST(UTC-5)로 바뀌면 한 시간 당겨진다
  (21:00 → 20:00 ET). 그때 `0 1` → `0 2`, `0 3` → `0 4` 로 바꾸면 원래 시각으로 돌아온다.
- 주말은 11:00 ET 슬롯을 쓰기로 했지만(`captions_en.md`) **자동화는 매일 같은 시각**이다. 필요하면 주말 cron 을 따로 추가한다.

---

## 폴더

```
.github/workflows/   publish-instagram.yml · publish-threads.yml · refresh-tokens.yml
bin/                 publish.sh · publish_threads.sh · refresh_tokens.sh
images/              1080×1350 PNG — raw.githubusercontent.com 으로 공개 서빙
queue/               YYYY-MM-DD.json — 하루치 게시물 정의
state/tokens.json    토큰 발급일·만료 예정일 (토큰 값은 없다)
log.md               발행 기록
```

### 큐 형식

```json
{
  "date": "2026-09-21",
  "day": 1,
  "featureId": "QNA-01",
  "format": "A",
  "lang": "en",
  "en": {
    "images": ["en01_1.png", "en01_2.png"],
    "caption": "One question a day, made for the two of you.\n\n…\n\n#couples #couplegoals #DearApp",
    "threads": "We capped it at one question a day on purpose. …"
  }
}
```

- `en.images` — `images/` 안의 파일 이름. 1장이면 단일 게시물, 2~10장이면 캐러셀
- `en.caption` — Instagram 캡션. 2,200자 · 해시태그 30개 이내
- `en.threads` — Threads 문장(500자 이내). 없으면 Threads 는 그날을 건너뛴다
- 스크립트는 기본으로 `.en` 을 읽는다. 한국어 큐를 돌리려면 `QUEUE_LANG=ko` 를 준다

### 새 게시물 추가

이미지·캡션은 `Dear/Marketing/sns/` 에서 만들고(파이프라인과 캡션 원본이 거기 있다), **완성된 것만** 이 저장소로 옮긴다.

```bash
M=~/Developer/Dear/Marketing/sns
R=~/Developer/Dear/Dear-sns
cp "$M"/images_en/*.png "$R/images/"
cp "$M"/queue/*.json    "$R/queue/"
cd "$R" && git add images queue && git commit -m "content: 큐 추가" && git push
```

**push 가 끝나야** Meta 가 이미지를 가져갈 수 있다. push 전에는 dry run 이 404 로 실패한다.
올리기 전 점검:

```bash
for f in queue/*.json; do
  jq -e '.date and .day and .en.caption and (.en.images|length>0)' "$f" >/dev/null || echo "FAIL $f"
done
jq -r '.en.images[]' queue/*.json | sort -u | while read -r i; do
  [ -f "images/$i" ] || echo "MISSING images/$i"
done
```

---

## 최초 설정 (한 번만)

### 1. 저장소를 공개로

Meta 는 이미지를 업로드받지 않고 **URL 을 cURL 로 가져간다.** 공개 저장소여야
`https://raw.githubusercontent.com/<owner>/Dear-sns/main/images/en01_1.png` 가 인증 없이 열린다.
비공개면 이미지 확인 단계에서 404 로 실패한다. (2026-09-20 공개 전환 완료)

```bash
gh repo edit <owner>/Dear-sns --visibility public --accept-visibility-change-consequences
```

대가는 **올릴 예정인 게시물이 미리 공개된다**는 것이다. 토큰은 저장소가 아니라 Secrets 에 있으므로 노출되지 않는다.

### 2. Secrets 등록

Settings → Secrets and variables → **Actions** → New repository secret.

| 이름 | 필수 | 내용 |
|---|---|---|
| `IG_USER_ID` | ✅ | Instagram 계정 ID (숫자 `17841…`) |
| `IG_TOKEN` | ✅ | Instagram 장기 액세스 토큰 (60일) |
| `THREADS_USER_ID` | ✅ | Threads 프로필 ID — 없으면 Threads 발행만 건너뛴다 |
| `THREADS_TOKEN` | ✅ | Threads 장기 액세스 토큰 (60일) |
| `GH_PAT` | 권장 | 토큰 자동 갱신용 PAT. 없으면 만료 임박 시 Issue 만 열린다 |

사용자 ID 두 개는 `Marketing/Dear-SNS-Setup.md` §1.1b 에 적혀 있다. 직접 확인하려면:

```bash
curl -s "https://graph.instagram.com/v21.0/me?fields=id,username&access_token=$IG_TOKEN"
curl -s "https://graph.threads.net/v1.0/me?fields=id,username&access_token=$THREADS_TOKEN"
```

`GH_PAT` 는 **fine-grained PAT**, 이 저장소만, 권한은 **Secrets: Read and write** 하나면 된다.
(토큰 갱신 워크플로가 새 토큰을 Secret 에 덮어쓰는 데 쓴다.)

### 3. 첫 실행은 반드시 dry run

Actions → `publish · instagram` → Run workflow → `dry_run` **true** → Run.

토큰·큐·이미지 URL 을 전부 점검하고 캡션을 출력하되 **올리지는 않는다.**
통과하면 같은 방법으로 `dry_run` **false** 로 한 건만 올린다.
`date` 를 비워 두면 오늘 큐를, 날짜를 넣으면 그날 큐를 올린다.

### 4. 예약 켜기 (손으로 몇 건 올려 본 뒤)

`publish-instagram.yml` · `publish-threads.yml` 의 `on:` 에서 두 줄의 주석을 푼다.

```yaml
on:
  schedule:
    - cron: '0 1 * * *' # instagram · 21:00 ET   (threads 는 '0 3 * * *')
  workflow_dispatch:
```

커밋·push 하면 그날부터 예약이 돈다. **예약 실행은 아무것도 묻지 않고 바로 올린다** — 큐가 비어 있는 날은 그냥 건너뛴다.
잠시 멈추고 싶으면 다시 주석 처리하거나, Actions 탭에서 해당 워크플로를 Disable 한다(수동 실행 버튼도 같이 사라진다).

---

## 수동 조작

```bash
# 로컬에서 점검만 (발행 안 함)
IG_USER_ID=… IG_TOKEN=… \
ASSET_BASE_URL=https://raw.githubusercontent.com/<owner>/Dear-sns/main/images \
bin/publish.sh 2026-09-21 --dry-run
```

로컬 실행에도 `jq` 가 필요하다. 토큰을 셸 히스토리에 남기지 않으려면 `HISTCONTROL=ignorespace` 로 앞에 공백을 두고 실행한다.

---

## 토큰

60일이면 만료되고 **만료된 뒤에는 갱신할 수 없다.** 그래서 주 1회 굴린다.

| 채널 | 갱신 |
|---|---|
| Instagram | `GET https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=…` |
| Threads | `GET https://graph.threads.net/refresh_access_token?grant_type=th_refresh_token&access_token=…` |

조건은 둘 다 같다 — 토큰이 유효하고, 발급 후 24시간이 지났을 것.
발급일은 `state/tokens.json` 에 기록되고 갱신될 때마다 워크플로가 커밋한다(둘 다 2026-09-20 발급 → 11-19 만료).
새 토큰을 손으로 발급했다면 Secret 을 바꾼 뒤 이 파일의 `issued_at` 도 그날로 고친다.

---

## 문제 해결

| 증상 | 원인 · 대응 |
|---|---|
| `이미지 접근 불가 (404)` | 저장소가 비공개거나 이미지가 push 안 됐다. 공개 전환 후 다시 실행 |
| `컨테이너 상태 ERROR` | Meta 가 이미지를 가져오지 못했다. URL 을 브라우저에서 직접 열어 확인 |
| `발행 실패: … code=190` | 토큰 만료·무효. Meta 콘솔에서 재발급 후 Secret 교체 |
| `큐 형식 오류` | 큐에 `.en` 블록이 없다. 한국어 큐라면 `QUEUE_LANG=ko` |
| 예약 시각에 안 돎 | 예약은 꺼 둔 상태다(§예약 켜기). 켰다면 cron 지연을 먼저 의심한다 |
| 예약 워크플로가 꺼짐 | 저장소가 60일간 활동이 없으면 GitHub 가 자동 비활성화한다. 큐를 주기적으로 커밋하므로 보통 걸리지 않는다 |
| Threads 만 안 올라감 | `THREADS_*` Secret 미설정 — 경고만 남기고 건너뛴다 |

---

## 콘텐츠 규칙 (캡션을 고칠 때)

`Dear-Brand-Guide.md` §9 체크리스트 7개를 전부 통과해야 한다.

1. 금칙어 없음 — AI · algorithm · analyze · therapy · counselor · relationship advice · "ad-free" · "unlimited" · Heart Post Office · premium
2. 없는 기능을 말하지 않음 (아이폰 ⏳ 기능은 iOS 1.1.0 출시 전까지 금지)
3. Android 전용 기능에는 `(Android)` 표기
4. 실제 사용자의 대화·일기·후기 금지 — 샘플만
5. 한쪽 성별을 문제로 만들지 않음
6. 운세·궁합은 "just for fun" 으로 명시
7. 느낌표 1개 이하 · 이모지 2개 이하

영어 보이스(§5.3): 인칭은 **the two of you / you both**, 축약형 사용, Oxford comma,
기능명은 Daily Couple Question · Shared Diary · Couple Calendar · Appreciation Cards · Taste Match.

**앱이 만들어주는 결과(추천 질문·고민 변환·리포트)를 지어내지 않는다.** 실제 앱에서 캡처한 것만 쓴다.

---

## 하지 말 것

- 토큰 값을 코드·로그·Issue·커밋에 남기기. `set -x` 를 켠 채 curl 실행하기
- Meta 앱을 라이브 모드로 전환하기 (본인 계정만 쓰므로 개발 모드로 충분하다)
- Facebook 페이지 만들기 (Instagram Login 경로라 필요 없다)
- 큐에 없는 날짜를 억지로 채우기
- 승인 없이 실제 발행하기 — 수동 실행 기본값은 `dry_run=true` 다
