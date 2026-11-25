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
- 갱신 = 기존 계약을 `renewed`로 닫고 새 계약 생성 (월세 변경 시 과거 청구액이 바뀌지 않도록).

## 화면 / 기능
홈(이번 달 현황, 미납, 7일 내 예정, 만기 임박, 공실, 백업 알림) · 호실 · 세입자 · 납부(월별) · 더보기(건물 관리, 월별 수입, 백업/복원)
계약 상세의 "금액 변경"으로 선택한 달부터 월세·관리비 변경 가능. 더보기 → 공지 문자: 세입자별 개별 문자 발송.
미납 건에서 전화/문자(연체 안내 문구 자동 작성), 백업은 JSON을 공유/복사, 복원은 붙여넣기.

## 개발 / 테스트
- 브라우저에서 `assets/index.html`을 열어 바로 확인 가능 (`window.Android`가 없으면 브릿지 호출은 무시/대체됨).
- 모바일 폭(390px)에서 확인. 디버깅용 `window.__rent`(db, render, acts) 노출됨.
- `test/flow.py` : Playwright E2E 흐름 테스트 (호실 일괄 추가 → 계약 → 납부 → 메모 → 퇴실 → 백업/복원).

## 알려진 한계 / 다음에 해볼 것
- 실기기 설치 테스트는 아직 안 함 (환경에 에뮬레이터 없음). 스모크 테스트 필요: 설치, 데이터 유지, 뒤로가기, 전화/문자 연결, 공유.
- 데이터가 앱 내부 저장소에만 있음 → 앱 삭제 시 소멸 (백업 기능으로 보완).
- 아이디어: 납부일 알림(푸시), 공과금/수도 검침, 엑셀 내보내기, 영수증/계약서 사진 첨부.
- Android SDK가 있는 PC라면 Capacitor 등으로 옮겨 Gradle 빌드로 전환하는 것도 선택지.
