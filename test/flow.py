import sys, json, datetime
from playwright.sync_api import sync_playwright

URL = "file:///home/claude/rentapp/assets/index.html"
OUT = "/home/claude/test/"
errors = []

def ymd(d): return d.strftime("%Y-%m-%d")

with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 800}, device_scale_factor=2, locale="ko-KR")
    page = ctx.new_page()
    page.on("console", lambda m: errors.append(("console", m.type, m.text)) if m.type in ("error", "warning") else None)
    page.on("pageerror", lambda e: errors.append(("pageerror", str(e))))
    # fake Android bridge
    page.add_init_script("""
      window.__calls=[];
      window.Android={openUri:function(u){window.__calls.push(['uri',u])},share:function(t){window.__calls.push(['share',t.length])},copy:function(t){window.__calls.push(['copy',t.length])},exit:function(){window.__calls.push(['exit'])}};
    """)
    page.goto(URL)
    page.screenshot(path=OUT + "01_empty_home.png")

    # 호실 추가 (여러 개)
    page.click("[data-act=addRoom]")
    page.fill("#f_name", "101, 102, 201")
    page.fill("#f_kind", "원룸")
    page.screenshot(path=OUT + "02_room_form.png")
    page.click("[data-f=save]")
    page.click("nav.tabs [data-t=rooms]")
    assert page.locator(".rcard").count() == 3, page.locator(".rcard").count()
    page.screenshot(path=OUT + "03_rooms_vacant.png")

    # 계약 등록 101 (새 세입자) - 3개월 전 시작해서 미납 만들기
    page.locator(".rcard", has_text="101").click()
    page.click("[data-act=newContract]")
    page.fill("#f_nName", "김민수")
    page.fill("#f_nPhone", "01012345678")
    page.fill("#f_nGuardian", "김영희")
    page.fill("#f_nGuardianPhone", "01099998888")
    page.fill("#f_deposit", "5000000")
    page.fill("#f_rent", "500000")
    page.fill("#f_fee", "50000")
    start = datetime.date.today().replace(day=1) - datetime.timedelta(days=75)
    page.fill("#f_start", ymd(start))
    page.dispatch_event("#f_start", "change")
    page.select_option("#f_payDay", "5")
    page.fill("#f_agency", "행복공인중개사")
    page.fill("#f_agencyTel", "0212345678")
    page.fill("#f_memo", "반려동물 불가")
    page.screenshot(path=OUT + "04_contract_form.png")
    print("phone fmt:", page.input_value("#f_nPhone"), "| rent fmt:", page.input_value("#f_rent"), "| end auto:", page.input_value("#f_end"))
    page.click("[data-f=save]")
    page.screenshot(path=OUT + "05_room_detail.png", full_page=False)

    # 첫 달 납부 등록
    rows = page.locator("[data-act=pay]")
    n = rows.count()
    print("pay rows:", n)
    rows.nth(n - 1).click()  # oldest month
    page.fill("#f_memo", "계좌이체")
    page.screenshot(path=OUT + "06_pay_form.png")
    page.click("[data-f=save]")

    # 메모 추가: 호실/세입자
    page.fill("#nt_room", "욕실 천장 누수 흔적 있음 (2024 수리)")
    page.click("[data-act=addNote][data-k=room]")
    page.locator("[data-act=tenant]").first.click()
    page.fill("#nt_tenant", "밤늦게 연락 가능, 문자 선호")
    page.click("[data-act=addNote][data-k=tenant]")
    page.screenshot(path=OUT + "07_tenant_detail.png")
    page.evaluate("window.__back()")  # back to room

    # 퇴실 후 새 세입자가 와도 호실 메모 유지되는지: 퇴실 처리
    page.screenshot(path=OUT + "08_room_detail_scrolled.png")
    page.click("[data-act=endC]")
    page.click("[data-f=save]")
    assert page.locator("[data-act=newContract]").count() == 1
    body = page.inner_text("#main")
    assert "누수" in body, "room note should persist after tenant leaves"
    page.screenshot(path=OUT + "09_after_end.png")

    # 홈 / 납부 / 세입자 / 더보기
    page.evaluate("window.__back()") if False else None
    page.evaluate("window.__rent.render(true)")
    # 두번째 계약 (102) 정상 납부 중 + 갱신 테스트
    page.click("nav.tabs [data-t=rooms]")
    page.locator(".rcard", has_text="102").click()
    page.click("[data-act=newContract]")
    page.select_option("#f_tenantId", "new")
    page.fill("#f_nName", "박지은")
    page.fill("#f_nPhone", "01055556666")
    page.fill("#f_rent", "450000")
    page.fill("#f_fee", "40000")
    page.fill("#f_start", ymd(datetime.date.today() - datetime.timedelta(days=20)))
    page.dispatch_event("#f_start", "change")
    page.fill("#f_end", ymd(datetime.date.today() + datetime.timedelta(days=30)))
    page.dispatch_event("#f_end", "change")
    page.click("[data-f=save]")
    page.click("nav.tabs [data-t=home]")
    page.screenshot(path=OUT + "10_home.png", full_page=True)
    page.click("nav.tabs [data-t=pay]")
    page.screenshot(path=OUT + "11_pay_tab.png")
    page.click("nav.tabs [data-t=tenants]")
    page.screenshot(path=OUT + "12_tenants.png")
    page.click("nav.tabs [data-t=more]")
    page.click("[data-act=stats]")
    page.screenshot(path=OUT + "13_stats.png")
    page.evaluate("window.__back()")
    page.click("[data-act=backup]")
    page.click("[data-act=doShare]")
    page.screenshot(path=OUT + "14_backup.png")
    calls = page.evaluate("window.__calls")
    print("bridge calls:", calls)

    # 데이터 영속성: 새로고침 후에도 남아있는지
    page.reload()
    d = page.evaluate("JSON.parse(localStorage.getItem('rentapp.v1'))")
    print("persisted: rooms", len(d["rooms"]), "tenants", len(d["tenants"]), "contracts", len(d["contracts"]), "payments", len(d["payments"]))

    # 복원 테스트
    page.click("nav.tabs [data-t=more]"); page.click("[data-act=backup]")
    backup = page.evaluate("JSON.stringify({data:JSON.parse(localStorage.getItem('rentapp.v1'))})")
    page.click("[data-act=doWipe]"); page.click("[data-f=yes]"); page.click("[data-f=yes]")
    d2 = page.evaluate("JSON.parse(localStorage.getItem('rentapp.v1'))")
    assert len(d2["rooms"]) == 0
    page.click("nav.tabs [data-t=more]"); page.click("[data-act=backup]")
    page.fill("#rest", backup); page.click("[data-act=doRestore]"); page.click("[data-f=yes]")
    d3 = page.evaluate("JSON.parse(localStorage.getItem('rentapp.v1'))")
    assert len(d3["rooms"]) == 3 and len(d3["payments"]) == 1, (len(d3["rooms"]), len(d3["payments"]))
    print("restore OK")

    # 뒤로가기 / 종료 동작
    page.evaluate("window.__back()")
    page.evaluate("window.__back()")
    page.evaluate("window.__back()")
    print("after back x3 calls:", page.evaluate("window.__calls").__len__())
    b.close()

print("ERRORS:", errors)
