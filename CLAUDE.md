# 월세 관리 앱 (rent-manager)

임대인(집주인)용 월세 관리 Android 앱. WebView 안에서 `assets/index.html` 한 파일(바닐라 JS, 외부 의존성 없음)이 전부 동작하고,
Java 쪽은 얇은 껍데기(`MainActivity.smali`)만 있다. 데이터는 WebView `localStorage`(키 `rentapp.v1`)에 JSON으로 저장.

## 구조
- `assets/index.html` : 앱 전체 (UI, 데이터, 로직). 대부분의 수정은 여기서.
- `smali/com/rentmanager/app/MainActivity.smali` : WebView 생성, 뒤로가기(`window.__back()` 호출), JS 브릿지 `Android.{share,copy,openUri,exit}`
- `AndroidManifest.xml`, `apktool.yml`(minSdk 26 / targetSdk 33 / versionCode·Name), `res/` (아이콘, 테마, 앱 이름)
- 빌드 방식: Gradle이 아니라 **apktool + uber-apk-signer** (제작 환경에서 Android SDK/Maven이 막혀 있어 이렇게 만듦)

## 빌드
`./build.sh` → `out/signed/rent-aligned-signed.apk`
- 필요: Java 11+, `tools/apktool.jar`(2.11.1), `tools/uber-signer.jar`(1.3.0). 없으면 build.sh가 GitHub에서 받음.
- 서명 키: `keys/rent-release.jks` (alias `rent`, 비밀번호 `rent1234`). **업데이트 설치(데이터 유지)를 하려면 반드시 같은 키로 서명.**
- 앱을 고칠 때마다 `apktool.yml`의 versionCode를 올릴 것.

## 데이터 모델 (localStorage `rentapp.v1`)
`{props[], rooms[], tenants[], contracts[], payments[], meta{lastBackup}}`
- props: 건물 (name, addr, account, memo)
- rooms: 호실 (propId, name, kind, notes[]) ← 호실 특이사항은 호실에 붙어 세입자가 바뀌어도 유지
- tenants: 세입자 (name, phone, resident, guardian, guardianRel, guardianPhone, job, car, notes[]) ← 세입자 특이사항
- contracts: (roomId, tenantId, status active|ended|renewed, deposit, rent, fee, start, end, endedOn, payDay, agency, agencyTel, memo, depositReturned)
- payments: (contractId, ym 'YYYY-MM', paidOn, amount, memo) — 월별 여러 건(부분 납부) 가능
- **후불·입주일 기준 (meta.schema=2)**: 청구키 `ym` = 사용기간이 시작되는 달. 기간 = `dayIn(c,ym)` ~ 다음 달 납부일 전날(`periodLabel`), 납부일 = 다음 달 납부일(`dueOf`; 퇴실 계약의 마지막 기간은 퇴실일로 당김). 납부일(payDay)은 기본값이 입주일의 날짜. `allMonths()`가 기간을 만들고 상태는 저장하지 않고 `mstat()`으로 계산(완납/일부/미납/예정). 홈·납부 탭의 '이번 달'은 납부일이 속한 달 기준.
- 스키마 마이그레이션: 선불(v1)의 payments.ym / changes.from을 한 달 앞으로 이동(`migrate()`), 원본은 localStorage `rentapp.v1.bak-v1`에 보관. 복원 시 구버전 백업도 자동 변환.
- contracts.changes[]: 계약 중간 금액 변경 이력 `{from:'YYYY-MM',rent,fee}`. 계약의 rent/fee는 최초 금액이고, `termsAt(c,ym)`이 해당 청구기간에 적용되는 금액을 계산 (`from` 이하 중 가장 최근 값). 과거 청구월은 그대로 유지됨. 금액 표시는 `curTerms`/`lastTerms`/`s.rent` 사용.
- 보증금 분할: contracts.deposit(총액), downPay(계약금), downPaidOn, balPaidOn(잔금 입금일). 잔금 = deposit-downPay (`balanceOf`, downPay>0일 때만 추적). 잔금 입금일이 비면 홈에 '보증금 잔금 미입금' 표시.
- 계좌: props.accBank/accNo/accHolder (→ `account` 문자열 합성, 연체 문자에 사용), tenants.refundAcct(보증금 반환 계좌).
- 기간 표기: `periodLabel` → '11월분 (11/12-12/11)'.
- utils[]: 공과금 `{roomId,kind,ym,prev,cur,unit,amount,paidOn,note}` (더보기 → 공과금, 미수 건 문자 안내).
- files[]: 첨부 사진 메타 `{id,ownerId(계약),kind,date}`. 이미지 본문은 IndexedDB `rentapp-files`(JPEG dataURL, 최대 1600px)에 저장되어 **백업 JSON에는 포함되지 않음**. 파일 선택은 smali `MainActivity$Chrome.onShowFileChooser` → `MainActivity.pickFile/onActivityResult`.
- 내보내기: 탭 구분 텍스트를 복사/공유 (엑셀·구글시트 붙여넣기). 실제 .xlsx 파일 저장은 미구현(네이티브 파일 저장 필요).
- 갱신 = 기존 계약을 `renewed`로 닫고 새 계약 생성 (월세 변경 시 과거 청구액이 바뀌지 않도록).

## 화면 / 기능
홈(이번 달 현황, 미납, 7일 내 예정, 만기 임박, 공실, 백업 알림) · 호실 · 세입자 · 납부(월별) · 더보기(건물 관리, 월별 수입, 백업/복원)
계약 상세의 "금액 변경"으로 선택한 달부터 월세·관리비 변경 가능. 더보기 → 공지 문자: 세입자별 개별 문자 발송.
미납 건에서 전화/문자(연체 안내 문구 자동 작성), 백업은 JSON을 공유/복사, 복원은 붙여넣기.

## 개발 / 테스트
- 브라우저에서 `assets/index.html`을 열어 바로 확인 가능 (`window.Android`가 없으면 브릿지 호출은 무시/대체됨).
- 모바일 폭(390px)에서 확인. 디버깅용 `window.__rent`(db, render, acts) 노출됨.
- `test/assistant.test.mjs` : 비서 연동 계층 테스트 (Node + Playwright)
- `test/flow.py` : Playwright E2E 흐름 테스트 (호실 일괄 추가 → 계약 → 납부 → 메모 → 퇴실 → 백업/복원).

## AI 비서 연동 (rentmanager://assistant)
내 AI 비서 앱(`com.hwetj.assistant`)이 `rentmanager://assistant?cmd=<URL인코딩된 JSON>` 으로 요청을 보내면, 이 앱이 **값이 채워진 기존 폼**을 연다.
- **자동 저장 없음**: 사용자가 폼의 저장 버튼을 눌러야 반영된다. 폼/화면을 여는 요청은 데이터를 돌려주지 않고, 읽기는 `op:'query'` 로만 가능하다 (아래).
- 흐름: 인텐트 → `MainActivity.handleIntent`(smali)가 `pendingCmd` 에 보관 → `window.__assistantPoll()` 호출 → JS 브릿지 `Android.takeCommand()` 로 1회 소비 → `window.__assistant(cmd)`. 콜드 스타트는 JS 초기화 끝에서 poll.
- 요청 JSON: `{v:1, id, ts(ms), op, ...}`. `id` 가 직전 요청과 같거나 `ts` 가 10분 넘게 지나면 무시 (재시작 시 재실행 방지).
- `op:'record_payment'`: `room`(필수, "101"/"101호"), `building`(같은 이름 호실이 여러 건물일 때), `amount`(원, 정수), `paidOn`(YYYY-MM-DD, 생략 시 오늘), `period`(YYYY-MM 청구월, 생략 시 가장 오래된 미납월), `memo`. → `openPay` 폼.
- `op:'register_tenant'`: `name`(필수), `phone`, `guardian`, `guardianPhone`. `room` 이 있으면 입주 계약 폼(`contractForm`)을 열고 `deposit`, `rent`, `fee`, `start`, `end`, `payDay` 도 채운다. 이름+전화가 같은 기존 세입자는 재사용. `room` 이 없으면 세입자 폼만 연다.
- `op:'show'` (조회용 화면 열기, 데이터 변경·응답 없음): `screen` = `income`(월별 수입, `year` 또는 `ym` 으로 연도 지정, `ym` 을 주면 그 달 막대 강조) · `payments`(납부 내역, `ym`, `filter`=all|unpaid|paid) · `home` · `rooms` · `tenants` · `utilities`. 열려 있던 폼은 닫는다.
- `op:'query'` (**읽기 전용 조회**, 폼·화면 이동 없음, 열려 있는 폼도 닫지 않음): `what` = `overview`(이번 달 수금/청구, 호실·공실, 미납 건수·합계, 60일 내 만기) · `income`(`year`, 월별 입금/청구) · `unpaid`(미납·일부납부 건, `overdue`) · `payments`(`ym`, 그 달에 입금된 내역) · `rooms`(호실 현황) · `tenants`(계약 목록: 이름·호실·상태·기간). 결과는 JS 가 `Android.replyAssistant(id, json)` 으로 넘기고, smali 가 `hwetassistant://result?id=<id>&app=leaselog&data=<URL인코딩 JSON>` 인텐트를 **패키지 `com.hwetj.assistant` 로 고정**해 보낸다(요청에서 받은 값으로 대상을 바꾸지 않음, 비서 앱이 없으면 조용히 무시). JSON = `{ok:true,what,data}` 또는 `{ok:false,error}`, 40KB 미만, 목록은 150건까지(`truncated`). **연락처·주민/보호자 정보·계좌·메모/특이사항은 어떤 결과에도 넣지 않는다** (`test/assistant.test.mjs` 의 개인정보 테스트가 검증). 같은 id 재전송·10분 경과 요청은 답하지 않는다.
- 모든 입력은 `aStr/aDate/aMoney/aYm` 으로 검증하고, 화면에는 `esc()` 로만 출력한다. 오류는 `infoBox` 로 안내하고 데이터를 바꾸지 않는다.
- 인텐트 필터는 `VIEW + DEFAULT` 만 (BROWSABLE 없음 → 웹 페이지가 링크로 호출할 수 없음).
- 테스트: `node --test test/assistant.test.mjs` (Playwright, 웹 로직) · `test/emulator.sh` 3~4단계 (실제 인텐트·조회, CI 에뮬레이터).

## 알려진 한계 / 다음에 해볼 것
- 실기기 설치 테스트는 아직 안 함 (환경에 에뮬레이터 없음). 스모크 테스트 필요: 설치, 데이터 유지, 뒤로가기, 전화/문자 연결, 공유.
- 데이터가 앱 내부 저장소에만 있음 → 앱 삭제 시 소멸 (백업 기능으로 보완).
- 아이디어: 납부일 알림(푸시), 공과금/수도 검침, 엑셀 내보내기, 영수증/계약서 사진 첨부.
- Android SDK가 있는 PC라면 Capacitor 등으로 옮겨 Gradle 빌드로 전환하는 것도 선택지.
