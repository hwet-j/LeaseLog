// AI 비서 연동 계층 테스트 (Playwright, Node). 실행: node --test test/assistant.test.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const URL = 'file://' + path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../assets/index.html');

const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const addDays = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d; };
const TODAY = ymd(new Date());
const START = ymd(addDays(-70));

let browser;
before(async () => { browser = await chromium.launch(); });
after(async () => { await browser.close(); });

/** 호실 101(입주중), 102(공실), 201(입주중), 다른 건물의 101 도 있는 상태의 앱을 연다. */
async function openApp({ twoBuildings = false } = {}) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 800 }, locale: 'ko-KR' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(() => {
    window.__cmd = null;
    window.Android = {
      takeCommand() { const c = window.__cmd; window.__cmd = null; return c || ''; },
      openUri() {}, share() {}, copy() {}, exit() {},
    };
  });
  await page.goto(URL);
  await page.evaluate(({ START, twoBuildings }) => {
    const props = [{ id: 'p1', name: '행복빌라', addr: '', account: '', memo: '' }];
    const rooms = [
      { id: 'r101', propId: 'p1', name: '101', kind: '', notes: [] },
      { id: 'r102', propId: 'p1', name: '102', kind: '', notes: [] },
      { id: 'r201', propId: 'p1', name: '201', kind: '', notes: [] },
    ];
    if (twoBuildings) {
      props.push({ id: 'p2', name: '푸른빌라', addr: '', account: '', memo: '' });
      rooms.push({ id: 'r101b', propId: 'p2', name: '101', kind: '', notes: [] });
    }
    const end = new Date(START + 'T00:00:00'); end.setFullYear(end.getFullYear() + 1);
    const mk = (id, roomId, tenantId) => ({
      id, roomId, tenantId, status: 'active', endedOn: null, depositReturned: false, deposit: 5000000, downPay: 0,
      rent: 450000, fee: 50000, start: START, end: end.toISOString().slice(0, 10), payDay: Number(START.slice(8)),
    });
    window.__rent.db = {
      props, rooms, utils: [], files: [], payments: [],
      tenants: [{ id: 't1', name: '김민수', phone: '010-1234-5678', notes: [] }, { id: 't2', name: '이영희', phone: '010-2222-3333', notes: [] }],
      contracts: [mk('c101', 'r101', 't1'), mk('c201', 'r201', 't2')],
      meta: { lastBackup: null, created: new Date().toISOString(), schema: 2 },
    };
  }, { START, twoBuildings });
  return { page, errors, ctx };
}
const cmd = (o) => ({ v: 1, id: 'id-' + Math.random().toString(36).slice(2), ts: Date.now(), ...o });
const send = (page, c) => page.evaluate((c) => window.__assistant(c), c);
const title = (page) => page.locator('.sheet h3').first().innerText();
const db = (page) => page.evaluate(() => JSON.parse(JSON.stringify(window.__rent.db)));
const sheets = (page) => page.locator('.sheet').count();

test('납부: 값이 채워진 납부 폼이 열리고, 저장해야만 반영된다', async () => {
  const { page, errors, ctx } = await openApp();
  await send(page, cmd({ op: 'record_payment', room: '101호', paidOn: TODAY, amount: 450000, memo: '계좌이체' }));
  assert.match(await title(page), /101.*납부 등록/);
  assert.equal(await page.inputValue('#f_amount'), '450,000');
  assert.equal(await page.inputValue('#f_paidOn'), TODAY);
  assert.equal(await page.inputValue('#f_memo'), '계좌이체');
  assert.match(await page.locator('.sheet').innerText(), /비서가 전달한 요청/);
  assert.equal((await db(page)).payments.length, 0, '저장 전에는 기록되지 않아야 함');
  await page.click('[data-f=save]');
  const d = await db(page);
  assert.equal(d.payments.length, 1);
  assert.deepEqual(
    { c: d.payments[0].contractId, ym: d.payments[0].ym, amt: d.payments[0].amount, on: d.payments[0].paidOn },
    { c: 'c101', ym: START.slice(0, 7), amt: 450000, on: TODAY },
    '가장 오래된 미납 월분에 연결',
  );
  assert.deepEqual(errors, []);
  await ctx.close();
});

test('납부: 취소하면 아무것도 기록되지 않는다', async () => {
  const { page, ctx } = await openApp();
  await send(page, cmd({ op: 'record_payment', room: '201', amount: 500000 }));
  assert.equal(await page.inputValue('#f_paidOn'), TODAY, '날짜 생략 시 오늘');
  await page.click('[data-f=cancel]');
  assert.equal((await db(page)).payments.length, 0);
  await ctx.close();
});

test('납부: 월분을 지정하면 그 월분에 연결, 범위 밖이면 거부', async () => {
  const { page, ctx } = await openApp();
  const second = (() => { const [y, m] = START.slice(0, 7).split('-').map(Number); const d = new Date(y, m, 1); return ymd(d).slice(0, 7); })();
  await send(page, cmd({ op: 'record_payment', room: '101', amount: 500000, period: second }));
  await page.click('[data-f=save]');
  assert.equal((await db(page)).payments[0].ym, second);
  await send(page, cmd({ op: 'record_payment', room: '101', amount: 1, period: '2000-01' }));
  assert.match(await title(page), /등록할 수 없어요/);
  assert.match(await page.locator('.sheet').innerText(), /청구 기간이 아니에요/);
  await ctx.close();
});

test('납부: 없는 호실·공실·잘못된 금액/날짜는 안내만 하고 기록하지 않는다', async () => {
  const { page, ctx } = await openApp();
  for (const [c, re] of [
    [{ room: '999호', amount: 1000 }, /찾을 수 없어요[\s\S]*101/],
    [{ room: '102', amount: 1000 }, /입주 중인 계약이 없어요/],
    [{ room: '101', amount: -5 }, /금액이 올바르지 않아요/],
    [{ room: '101', amount: '12abc' }, /금액이 올바르지 않아요/],
    [{ room: '101', amount: 1000, paidOn: '2026-02-30' }, /날짜 형식/],
    [{ room: '101', amount: 1000, paidOn: '11/26' }, /날짜 형식/],
  ]) {
    await send(page, cmd({ op: 'record_payment', ...c }));
    assert.match(await page.locator('.sheet').innerText(), re, JSON.stringify(c));
    await page.click('[data-f=ok]');
    assert.equal(await sheets(page), 0);
  }
  assert.equal((await db(page)).payments.length, 0);
  await ctx.close();
});

test('납부: 같은 이름 호실이 두 건물에 있으면 건물을 요구하고, 지정하면 진행', async () => {
  const { page, ctx } = await openApp({ twoBuildings: true });
  await send(page, cmd({ op: 'record_payment', room: '101', amount: 1000 }));
  assert.match(await page.locator('.sheet').innerText(), /여러 건물에 있어요/);
  await page.click('[data-f=ok]');
  await send(page, cmd({ op: 'record_payment', room: '101', building: '행복빌라', amount: 1000 }));
  assert.match(await title(page), /납부 등록/);
  await ctx.close();
});

test('요청 검증: 재전송(같은 id)·만료·형식 오류·알 수 없는 작업', async () => {
  const { page, ctx } = await openApp();
  const c = cmd({ op: 'record_payment', room: '101', amount: 1000 });
  await send(page, c);
  assert.equal(await sheets(page), 1);
  await page.click('[data-f=cancel]');
  await send(page, c); // 같은 id 재전송 → 무시
  assert.equal(await sheets(page), 0, '같은 id 는 다시 열리지 않아야 함');

  await send(page, cmd({ op: 'record_payment', room: '101', amount: 1000, ts: Date.now() - 11 * 60_000 }));
  assert.match(await title(page), /만료/);
  await page.click('[data-f=ok]');
  await send(page, { v: 2, id: 'x', ts: Date.now(), op: 'record_payment' });
  assert.match(await page.locator('.sheet').innerText(), /지원하지 않는 요청 형식/);
  await page.click('[data-f=ok]');
  await send(page, cmd({ op: 'delete_everything' }));
  assert.match(await page.locator('.sheet').innerText(), /지원하지 않는 작업/);
  assert.equal((await db(page)).payments.length, 0);
  await ctx.close();
});

test('새 요청은 열려 있던 폼을 닫고 대체한다', async () => {
  const { page, ctx } = await openApp();
  await send(page, cmd({ op: 'record_payment', room: '101', amount: 1000 }));
  await send(page, cmd({ op: 'record_payment', room: '201', amount: 2000 }));
  assert.equal(await sheets(page), 1);
  assert.match(await title(page), /201/);
  await ctx.close();
});

test('세입자+계약 등록: 새 세입자, 값이 채워진 계약 폼 → 저장', async () => {
  const { page, errors, ctx } = await openApp();
  await send(page, cmd({
    op: 'register_tenant', room: '102호', name: '박지후', phone: '01055556666', guardian: '박철수',
    deposit: 3000000, rent: 400000, fee: 30000, start: '2026-12-01', payDay: 5,
  }));
  assert.match(await page.locator('.sheet').innerText(), /102.*호실/);
  assert.equal(await page.inputValue('#f_nName'), '박지후');
  assert.equal(await page.inputValue('#f_nPhone'), '010-5555-6666');
  assert.equal(await page.inputValue('#f_deposit'), '3,000,000');
  assert.equal(await page.inputValue('#f_rent'), '400,000');
  assert.equal(await page.inputValue('#f_start'), '2026-12-01');
  assert.equal(await page.inputValue('#f_end'), '2027-11-30', '만기는 시작일 +1년-1일');
  assert.equal(await page.inputValue('#f_payDay'), '5', '납부일 지정값 유지');
  let d = await db(page);
  assert.equal(d.tenants.length, 2, '저장 전에는 등록되지 않아야 함');
  await page.click('[data-f=save]');
  d = await db(page);
  assert.equal(d.tenants.length, 3);
  const t = d.tenants.find((x) => x.name === '박지후');
  const c = d.contracts.find((x) => x.tenantId === t.id);
  assert.deepEqual(
    { room: c.roomId, dep: c.deposit, rent: c.rent, fee: c.fee, start: c.start, end: c.end, payDay: c.payDay, st: c.status },
    { room: 'r102', dep: 3000000, rent: 400000, fee: 30000, start: '2026-12-01', end: '2027-11-30', payDay: 5, st: 'active' },
  );
  assert.deepEqual(errors, []);
  await ctx.close();
});

test('세입자+계약: 시작일만 주면 납부일은 시작일의 일자, 기존 세입자는 재사용', async () => {
  const { page, ctx } = await openApp();
  await send(page, cmd({ op: 'register_tenant', room: '102', name: '김민수', phone: '010-1234-5678', rent: 300000, start: '2026-12-17' }));
  assert.equal(await page.inputValue('#f_tenantId'), 't1', '이름+전화가 같은 기존 세입자 선택');
  assert.equal(await page.inputValue('#f_payDay'), '17');
  assert.match(await page.locator('.sheet').innerText(), /기존 세입자와 연결/);
  await page.click('[data-f=save]');
  const d = await db(page);
  assert.equal(d.tenants.length, 2, '세입자가 중복 생성되면 안 됨');
  assert.equal(d.contracts.filter((c) => c.tenantId === 't1').length, 2);
  await ctx.close();
});

test('세입자 등록: 입주 중인 호실·잘못된 값은 거부', async () => {
  const { page, ctx } = await openApp();
  for (const [c, re] of [
    [{ room: '101', name: '새사람' }, /이미 입주 중인 계약/],
    [{ room: '999', name: '새사람' }, /찾을 수 없어요/],
    [{ room: '102', name: '' }, /이름이 필요/],
    [{ room: '102', name: '새사람', rent: 'abc' }, /rent/],
    [{ room: '102', name: '새사람', start: '2026-12-01', end: '2026-11-01' }, /만기일이 계약일보다 빨라요/],
    [{ room: '102', name: '새사람', payDay: 40 }, /payDay/],
  ]) {
    await send(page, cmd({ op: 'register_tenant', ...c }));
    assert.match(await page.locator('.sheet').innerText(), re, JSON.stringify(c));
    await page.click('[data-f=ok]');
  }
  const d = await db(page);
  assert.equal(d.tenants.length, 2);
  assert.equal(d.contracts.length, 2);
  await ctx.close();
});

test('세입자만 등록(호실 없음): 값이 채워진 세입자 폼, 이미 있으면 안내', async () => {
  const { page, ctx } = await openApp();
  await send(page, cmd({ op: 'register_tenant', name: '최도윤', phone: '01077778888', guardian: '최영수' }));
  assert.match(await title(page), /세입자 추가/);
  assert.equal(await page.inputValue('#f_name'), '최도윤');
  assert.equal(await page.inputValue('#f_phone'), '010-7777-8888');
  await page.click('[data-f=save]');
  assert.ok((await db(page)).tenants.some((t) => t.name === '최도윤' && t.guardian === '최영수'));
  await send(page, cmd({ op: 'register_tenant', name: '김민수' }));
  assert.match(await title(page), /이미 등록된 세입자/);
  await ctx.close();
});

test('HTML 주입 방지: 이름·메모에 태그가 있어도 실행/렌더되지 않는다', async () => {
  const { page, errors, ctx } = await openApp();
  await send(page, cmd({ op: 'record_payment', room: '101', amount: 1000, memo: '<img src=x onerror=window.__pwn=1>' }));
  assert.equal(await page.evaluate(() => window.__pwn), undefined);
  await page.click('[data-f=cancel]');
  await send(page, cmd({ op: 'register_tenant', room: '<b>102</b>', name: '<script>window.__pwn=2</script>' }));
  assert.equal(await page.evaluate(() => window.__pwn), undefined);
  assert.equal(await page.locator('.sheet b').count(), 0);
  assert.deepEqual(errors, []);
  await ctx.close();
});

test('Android 브리지: takeCommand 로 전달된 요청을 폴링해 처리하고 한 번만 소비한다', async () => {
  const { page, ctx } = await openApp();
  await page.evaluate((c) => { window.__cmd = JSON.stringify(c); window.__assistantPoll(); }, cmd({ op: 'record_payment', room: '101', amount: 450000 }));
  assert.match(await title(page), /101.*납부 등록/);
  await page.click('[data-f=cancel]');
  await page.evaluate(() => window.__assistantPoll()); // 이미 소비됨 → 아무 일도 없어야 함
  assert.equal(await sheets(page), 0);
  await page.evaluate(() => { window.__cmd = '{not json'; window.__assistantPoll(); });
  assert.match(await page.locator('.sheet').innerText(), /형식이 올바르지 않아요/);
  await page.click('[data-f=ok]');
  await page.evaluate(() => { window.__cmd = 'x'.repeat(9000); window.__assistantPoll(); });
  assert.match(await page.locator('.sheet').innerText(), /너무 커요/);
  await ctx.close();
});

test('기존 동작 회귀: 화면의 납부 버튼(acts.pay)은 예전처럼 동작한다', async () => {
  const { page, errors, ctx } = await openApp();
  await page.evaluate(({ ym }) => window.__rent.acts.pay({ c: 'c101', ym }), { ym: START.slice(0, 7) });
  assert.match(await title(page), /101.*납부 등록/);
  assert.equal(await page.inputValue('#f_paidOn'), TODAY);
  assert.equal(await page.inputValue('#f_amount'), '500,000', '기본값은 남은 금액(월세+관리비)');
  assert.equal(await page.inputValue('#f_memo'), '');
  assert.doesNotMatch(await page.locator('.sheet').innerText(), /비서가 전달/);
  await page.click('[data-f=save]');
  assert.equal((await db(page)).payments.length, 1);
  assert.deepEqual(errors, []);
  await ctx.close();
});

test('앱 시작 시 대기 중인 요청이 있으면 바로 처리한다 (콜드 스타트)', async () => {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 800 } });
  const page = await ctx.newPage();
  const c = cmd({ op: 'register_tenant', name: '정하늘' });
  await page.addInitScript((raw) => {
    let cmd = raw;
    window.Android = { takeCommand() { const r = cmd; cmd = ''; return r; }, openUri() {}, share() {}, copy() {}, exit() {} };
  }, JSON.stringify(c));
  await page.goto(URL);
  assert.match(await title(page), /세입자 추가/);
  assert.equal(await page.inputValue('#f_name'), '정하늘');
  await ctx.close();
});
