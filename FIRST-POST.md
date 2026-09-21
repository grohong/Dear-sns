# 첫 게시물 발행 런북 — Day 1 · QNA-01

> 대상: `~/Developer/Dear/Dear-sns` · 실행: Claude Code 또는 터미널
> 작성: 2026-09-21 · 상태: ✅ **발행 완료 — 2026-09-21 10:35 KST**
>
> | 채널 | post_id | 링크 |
> |---|---|---|
> | Instagram (캐러셀 4장) | `18103037423102990` | https://www.instagram.com/p/Ddh_eBpjgAr/ |
> | Threads (글 + 이미지 1장) | `18144500095573747` | https://www.threads.com/@dear.couple.app/post/Ddh_kkqG0Sz |
>
> **가는 길에 두 번 막혔다** — 둘 다 원인과 대책을 아래에 남겼다.
> 1. `API access blocked`(code 200) = 앱 차단이 아니라 **사용자 ID 오기입** → §3-1
> 2. Threads 워크플로가 **발행은 성공하고 `log.md` 커밋에서 실패** → §7-1
>
> 다음 날(Day 2)부터는 §3 dry-run → §4 발행 순서만 반복하면 된다.

---

## 0. 지금 상태

| 항목 | 상태 |
|---|---|
| 저장소 공개 전환 | ✅ 2026-09-20 |
| 이미지 21장 push | ✅ `raw.githubusercontent.com` HTTP 200 실측 |
| 큐 9건 (9/21~9/30, 9/26 제외) | ✅ |
| 토큰 발급 | ✅ 2026-09-20 → **2026-11-19 만료** |
| GitHub Secrets 등록 | ✅ 2026-09-21 — `IG_USER_ID`·`IG_TOKEN`·`THREADS_USER_ID`·`THREADS_TOKEN` 4개 |
| 미커밋 변경분 | ✅ 2026-09-21 push (`2fbf076`) |
| Actions 파이프라인 | ✅ 큐·이미지·캡션 점검까지 실측 통과 |
| **Meta API 접근** | ✅ 정상. 앱 차단이 아니라 `IG_USER_ID`·`THREADS_USER_ID` 오기입이었다 — §3-1 |
| **Day 1 발행** | ✅ 2026-09-21 Instagram + Threads 둘 다 |
| `log.md` 자동 기록 | 🟡 Threads 분은 충돌로 실패 → 사람이 채움. 재발 방지 = §7-1 |
| 예약(cron) 발행 | ⏸ 꺼짐 — 수동 실행만 |

---

## 1. 미커밋 변경분 push

**Actions 는 GitHub 에 올라간 코드를 돌린다.** push 하지 않으면 아래 변경이 반영되지 않는다:

- `bin/publish.sh` · `bin/publish_threads.sh` — **토큰 생존 확인(`check_token`)** 추가.
  기존 만료일 계산은 "60일 지났나"만 알 뿐, 폐기·비밀번호 변경으로 무효화된 토큰은 못 잡는다.
- `bin/publish_threads.sh` — `.en.threadsImages` 로 `TEXT` / `IMAGE` / `CAROUSEL` 분기.
  **push 안 하면 Threads 는 이미지 없이 글만 나간다.**
- `queue/*.json` 9건 — `threadsImages` 필드 추가.
- `.github/workflows/publish-threads.yml` — 이미지용 `ASSET_BASE_URL` 주입.

```bash
cd ~/Developer/Dear/Dear-sns
git status --short          # 12개 파일이 M 으로 보여야 한다
git add -A
git commit -m "Threads 이미지 지원 + 토큰 생존 확인

- publish_threads.sh: .en.threadsImages 로 TEXT/IMAGE/CAROUSEL 분기
- 캐러셀 날만 2번 카드 1장 (브랜드 가이드 §4.1)
- 두 스크립트에 check_token 추가 — 만료일 계산으론 무효 토큰을 못 잡는다"
git push
```

---

## 2. Secrets 확인

토큰은 **저장소에 없다.** 이 저장소는 공개라서 넣으면 누구나 계정을 쓸 수 있다.
GitHub Actions Secrets 에 암호화돼 있고, 워크플로 실행 시에만 환경변수로 주입된다.

```bash
gh secret list
```

네 줄이 보여야 한다:

```
IG_USER_ID        Updated ...
IG_TOKEN          Updated ...
THREADS_USER_ID   Updated ...
THREADS_TOKEN     Updated ...
```

### 없으면 등록

값을 인자로 넘기지 말 것 — 셸 히스토리에 남는다. 아래처럼 실행하면 물어보고, 입력은 화면에 찍히지 않는다.

```bash
gh secret set IG_USER_ID
gh secret set IG_TOKEN
gh secret set THREADS_USER_ID
gh secret set THREADS_TOKEN
```

- ID 두 개 → `../Marketing/Dear-SNS-Setup.md` §1.1b
- 토큰을 다시 발급했다면 **`state/tokens.json` 의 `issued_at` 도 그날로 고친다.** 안 고치면 만료 계산이 어긋난다.
- `GH_PAT`(선택) 없으면 주간 토큰 갱신이 자동으로 안 되고 만료 임박 시 Issue 만 열린다.

> Secrets 는 한번 넣으면 **아무도 다시 볼 수 없다.** 이름과 갱신 날짜만 보인다.

---

## 3. dry-run — 건너뛰지 말 것

발행하지 않고 토큰·큐·이미지 URL·캡션 한도를 전부 점검한다.

```bash
gh workflow run publish-instagram.yml -f date=2026-09-21 -f dry_run=true
sleep 5 && gh run watch
```

### 통과하면 이렇게 나온다

```
---- 2026-09-21  Day 1  QNA-01  [en]  이미지 4장  캡션 296자 ----
이미지 4장 공개 확인 완료 (HTTP 200)

─── 캡션 미리보기 ───
One question a day, made for the two of you.
...
─────────────────────

토큰 정상 — Instagram @dear.couple.app     ← 이 줄이 핵심이다
DRY RUN — 점검만 하고 발행하지 않았습니다.
```

**`토큰 정상` 줄을 확인하기 전에는 §4 로 넘어가지 않는다.** 이 줄이 이번 실행의 목적이다.

| 멈춘 지점 | 뜻 | 대응 |
|---|---|---|
| `Secret 미설정: ...` | Secrets 없음 | §2 |
| `이미지 접근 불가 (404)` | push 안 됨 / 저장소 비공개 | §1, 또는 `gh repo edit --visibility public` |
| `토큰이 유효하지 않습니다` + `code 190` | 토큰 폐기·오타·만료 | Meta 콘솔 재발급 → §2 → `state/tokens.json` 갱신 |
| `토큰이 유효하지 않습니다` + `code 200 · API access blocked` | **앱 단위 차단** — 토큰은 멀쩡하다 | §3-1 |
| `큐 형식 오류` | `.en` 블록 없음 | `jq . queue/2026-09-21.json` 로 확인 |
| `큐 없음` | 날짜 오타 | `-f date=2026-09-21` |

### 3-1. `API access blocked` (code 200) — 원인: 사용자 ID 오기입 ✅ 2026-09-21 해결

**앱 차단이 아니었다.** 토큰은 처음부터 멀쩡했다.

```
토큰이 말하는 ID :  28310077545285687   ← Instagram Login 체계 (맞는 값)
Secret 에 넣은 ID:  17841433306387861   ← Facebook Login 체계 (틀린 값)
```

같은 계정인데 **인증 방식에 따라 사용자 ID 체계가 다르다.**

| 방식 | 엔드포인트 | ID |
|---|---|---|
| **with Instagram Login** ← 우리가 쓰는 것 | `graph.instagram.com` | `28310077545285687` |
| with Facebook Login | `graph.facebook.com` | `17841433306387861` |

틀린 ID 로 `/{USER_ID}` 를 조회하면 **토큰이 소유하지 않은 객체**를 여는 셈이라 `code 200` 이 난다.
`API access blocked` 라는 문구가 앱 차단처럼 읽히지만 **code 200 의 원래 뜻은 Permissions error** 다.

> **190 과 200 을 구분할 것.** 190 = 토큰이 깨졌다. 200 = 토큰은 멀쩡한데 권한이 없다.

#### 진단 방법 — 토큰 자신에게 묻는다

`/me` 는 "이 토큰의 주인이 누구냐"를 묻는 것이라 ID 를 틀릴 수가 없다.

```bash
set -a; . ~/.dear-sns/credentials.env; set +a
curl -s "https://graph.instagram.com/v21.0/me?fields=id,username&access_token=$IG_TOKEN"   | jq .
curl -s "https://graph.threads.net/v1.0/me?fields=id,username&access_token=$THREADS_TOKEN" | jq .
```

#### 조치

```bash
cd ~/Developer/Dear/Dear-sns
gh secret set IG_USER_ID      --body "28310077545285687"
gh secret set THREADS_USER_ID --body "28219132734445707"
gh secret list                # Updated 날짜가 오늘로 바뀌었는지
```

✅ **2026-09-21 조치 완료** — Secret 2개 교체 + `~/.dear-sns/credentials.env` 의 ID 2줄도 같이 고쳤다.
**Threads 도 같은 함정이었다**: 맞는 값은 `28219132734445707`, 틀린 값이 `17841430517193232` 였다.
로컬 dry-run 에서 양쪽 다 `토큰 정상` 확인.

`bin/publish.sh` · `bin/publish_threads.sh` 의 `check_token` 도 `/me` 로 묻고 ID 를 대조하도록 고쳤다.
이제 같은 실수를 하면 **양쪽 값을 같이 찍어주며** 멈춘다:

```
FAIL  Instagram 사용자 ID 가 토큰 소유자와 다릅니다 (Secret=17841… · 토큰=28310…)
```

### 3-2. 차단이 길어지면 — 오늘 것은 손으로 올린다

**API 차단은 발행을 막지만 게시를 막지는 않는다.** 이미지도 캡션도 이미 완성돼 있다.
Meta 대시보드 해제를 기다리느라 첫 게시물을 미룰 이유가 없다 — 계정이 비어 있는 날이 하루 더 늘 뿐이다.

1. `instagram.com` 에 `@dear.couple.app` 으로 로그인 → **만들기(Create)**
2. `~/Developer/Dear/Dear-sns/images/` 에서 **`en01_1` → `en01_2` → `en01_3` → `en01_4`** 순서로 4장 선택
3. 자르기에서 **세로 4:5** 선택 (정사각형으로 잘리면 페이지 표기 `1/4` 가 잘린다)
4. 캡션은 `queue/2026-09-21.json` 의 `.en.caption` 을 그대로 붙인다:

```bash
jq -r '.en.caption' queue/2026-09-21.json | pbcopy   # 클립보드로
```

5. Threads 는 2시간 뒤 `threads.net` 에서 `.en.threads` 문장 + `images/en01_2.png` 한 장

```bash
jq -r '.en.threads' queue/2026-09-21.json | pbcopy
```

손으로 올렸으면 **큐 파일을 지우지 말고** `log.md` 에 기록만 남긴다 — 나중에 자동 발행이 살아났을 때
같은 날짜를 다시 돌리면 중복 게시가 된다.

```
| 2026-09-21 | 1 | QNA-01 | @dear.couple.app | 수동 게시 | API 차단 우회 · 워크플로 재실행 금지 |
```

---

## 4. 실제 발행

```bash
gh workflow run publish-instagram.yml -f date=2026-09-21 -f dry_run=false
sleep 5 && gh run watch
```

캐러셀은 4장을 각각 컨테이너로 만들고 묶은 뒤 30초 대기했다가 발행한다. **2~3분 걸린다.**

```
컨테이너 생성 18############ — 30초 대기(공식 권장)
Instagram 발행 완료  post_id=18############
완료. Threads 는 2시간 뒤 publish-threads 워크플로가 올립니다.
```

성공하면 워크플로가 `log.md` 에 한 줄을 append 하고 `[skip ci]` 로 커밋·push 한다.

> **중간에 실패하면** 컨테이너만 만들어지고 발행은 안 된 상태다. 컨테이너는 24시간 뒤 자동 만료되니
> 그대로 두고 원인을 고친 뒤 다시 돌린다. 같은 날짜로 두 번 성공하면 **게시물이 2개 올라간다** —
> 재실행 전에 Instagram 을 먼저 확인한다.

---

## 5. 눈으로 확인

`instagram.com/dear.couple.app` 에서 볼 것:

- [ ] 4장이 **순서대로** — 훅 → 홈 화면 → How it works → CTA
- [ ] 우상단 `1/4`~`4/4` 페이지 표기가 잘리지 않았나
- [ ] 세로 4:5 로 나왔나 (정사각형으로 잘렸으면 안 된다)
- [ ] 캡션 첫 줄이 피드에서 온전히 보이나
- [ ] 해시태그 8개가 링크로 잡혔나

**마음에 안 들면 Instagram 앱에서 직접 삭제한다.** Content Publishing API 에는 삭제가 없다.
지우고 이미지·캡션을 고친 뒤 다시 올리면 된다.

---

## 6. Threads — 2시간 뒤

브랜드 가이드 §8.4 기준 인스타 2시간 뒤. 지금은 예약이 꺼져 있으니 손으로 돌린다.

```bash
gh workflow run publish-threads.yml -f date=2026-09-21 -f dry_run=true
sleep 5 && gh run watch
# "이미지 1장: en01_2.png" + "토큰 정상 — Threads @..." 확인 후
gh workflow run publish-threads.yml -f date=2026-09-21 -f dry_run=false
```

올라갈 내용 — **글이 본문이고 이미지는 거드는 역할**이다:

```
We capped it at one question a day on purpose. People ask for more,
but one a day is what people actually keep doing six months later.
```

+ `en01_2.png` (홈 화면 카드) 한 장.

§1 을 건너뛰었다면 여기서 이미지 없이 글만 나간다.

---

## 7. 기록

```bash
git pull                      # 워크플로가 커밋한 log.md 받아오기
tail -5 log.md
```

`../Marketing/log.md` 에 운영 기록 한 줄을 사람이 직접 남긴다 — 첫 발행 시각, 눈으로 본 결과, 고칠 점.

### 7-1. `log.md` 커밋 충돌 — 2026-09-21 Threads 에서 발생 ✅ 대책 반영

Threads 워크플로가 이렇게 끝났다:

```
[main 8404a5b] chore: publish threads 2026-09-21 [skip ci]
 ! [rejected]  HEAD -> main (fetch first)
CONFLICT (content): Merge conflict in log.md
Error: Process completed with exit code 1
```

**게시물은 올라갔다.** 스크립트는 발행에 성공한 뒤에만 `log.md` 에 줄을 붙이므로,
여기서 실패하면 잃는 건 기록 한 줄뿐이다 — 런너는 일회용이라 그 커밋은 사라진다.

원인은 **동시 실행**이었다. 두 워크플로가 같은 `concurrency` 그룹인데도 9초 차이로 같이 돌았고
(IG `01:34:10`~`01:35:20`, Threads `01:34:19` 시작), 둘 다 `log.md` **끝줄에 각자 한 줄**을 붙여 부딪혔다.

대책 두 가지 —

1. **`.gitattributes` 에 `log.md merge=union`** — append 전용 파일이라 양쪽 줄을 모두 남기고 자동 해결한다.
   (빈 저장소에서 rebase 로 재현·검증함: 충돌 0, 두 줄 모두 보존)
2. **push 3회 재시도** — 거절되면 `git pull --rebase` 후 다시 민다. 그래도 안 되면 에러 주석으로
   *"게시물은 이미 올라갔다"* 를 남기고 실패시킨다.

> ⚠️ 이 실패를 보고 **워크플로를 다시 돌리면 같은 게시물이 두 번 올라간다.**
> 먼저 계정을 확인하고, 이미 올라갔으면 기록만 손으로 채운다.

```bash
git pull
# | 2026-09-21 | — | — | Threads @dear.couple.app | 게시 | TH <post_id> · <permalink> |
```

post_id 는 실행 로그에 있다 — `gh run view <run-id> --log | grep "발행 완료"`.

---

## 8. 다음 (이 런북 범위 밖)

- **Day 2 (9/22)** — 같은 방식으로 수동 발행. 며칠 손으로 돌려 보고 감을 잡는다.
- **예약 켜기** — `publish-instagram.yml` / `publish-threads.yml` 의 `on:` 에서 `schedule:` 두 줄 주석 해제.
  **예약 실행은 아무것도 묻지 않고 바로 올린다.**
- **Day 6 (9/26)** — 비어 있다. Before/After 카드의 "after" 는 앱이 실제로 만들어낸 질문이어야 해서 캡처가 필요하다.
  샘플 고민: *"They've been slower to reply lately and I don't know how to bring it up without sounding clingy."*
- **일정 이동** — 큐 날짜는 파일명에 박혀 있다. iOS 1.1.0 출시일에 맞추려면 9개 파일명과 각 JSON 의 `date` 를 같이 바꾼다.
- **토큰 만료 2026-11-19** — 주간 `refresh · tokens` 가 굴려 주지만, `GH_PAT` 가 없으면 Issue 만 열린다.

---

## 9. 하지 말 것

- 토큰 값을 인자·코드·로그·커밋·Issue 에 남기기. `set -x` 를 켠 채 curl 실행하기
- dry-run 없이 바로 `dry_run=false` 로 가기
- 실패한 실행을 Instagram 확인 없이 재시도하기 (중복 게시 위험)
- 큐에 없는 날짜를 억지로 채우기 — 앱이 만든 결과를 지어내는 건 특히 금지
- Meta 앱을 라이브 모드로 전환하기 (본인 계정만 쓰므로 개발 모드로 충분)
