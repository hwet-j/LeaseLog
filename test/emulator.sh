#!/usr/bin/env bash
# 에뮬레이터 검증: (1) 릴리스 APK 설치·실행·dex 검증, (2) 테스트 APK로 파일 선택창 → 선택 → JS 수신까지
set -u
PKG=com.rentmanager.app
OUT=emu-out; mkdir -p $OUT
fail=0
note(){ echo "== $*"; }
ui(){
  rm -f $OUT/ui.xml
  for i in 1 2 3 4 5 6; do
    adb shell uiautomator dump /sdcard/ui.xml > $OUT/dump-log.txt 2>&1
    adb pull /sdcard/ui.xml $OUT/ui.xml >/dev/null 2>&1
    [ -s $OUT/ui.xml ] && return 0
    cat $OUT/dump-log.txt | head -3; sleep 3
  done
  return 1
}
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
# 텍스트(부분 일치)가 있는 노드의 중심 좌표로 탭. 성공 0
tap_text(){
  ui
  xy=$(python3 - "$1" <<'PY'
import sys,re,xml.etree.ElementTree as ET
t=sys.argv[1]
try: root=ET.parse('emu-out/ui.xml').getroot()
except Exception: sys.exit(1)
for n in root.iter('node'):
    if t in (n.get('text') or '') or t in (n.get('content-desc') or ''):
        m=re.findall(r'\d+',n.get('bounds'))
        x1,y1,x2,y2=map(int,m); print((x1+x2)//2,(y1+y2)//2); sys.exit(0)
sys.exit(1)
PY
  ) || return 1
  note "tap '$1' at $xy"; adb shell input tap $xy; return 0
}
has_text(){ ui; grep -q "$1" $OUT/ui.xml; }
# 소프트웨어 렌더링 에뮬레이터는 첫 실행이 느리므로 고정 sleep 대신 최대 $2 초까지 기다린다.
wait_text(){ local t=0; while [ $t -lt ${2:-60} ]; do ui && grep -q "$1" $OUT/ui.xml && return 0; sleep 3; t=$((t+3)); done; return 1; }
wait_top(){ local t=0; while [ $t -lt ${1:-60} ]; do top | grep -q "$PKG" && return 0; sleep 3; t=$((t+3)); done; return 1; }
dump_texts(){ python3 - <<'PY'
import xml.etree.ElementTree as ET
try:
    for n in ET.parse('emu-out/ui.xml').getroot().iter('node'):
        v=(n.get('text') or '')+'|'+(n.get('content-desc') or '')
        if v.strip('|'): print('   screen:',v[:120])
except Exception as e: print('   parse fail',e)
PY
}
top(){ adb shell dumpsys activity activities | grep -E "topResumedActivity|mResumedActivity" | head -2; }

note "1) release APK"
adb install -r out/signed/rent-aligned-signed.apk || fail=1
adb logcat -c
adb shell am start -n $PKG/.MainActivity
sleep 10
adb shell pidof $PKG >/dev/null || { echo "FAIL: app not running"; fail=1; }
adb logcat -d > $OUT/logcat-release.txt
if grep -E "FATAL EXCEPTION|VerifyError|NoClassDefFoundError|Rejecting class" $OUT/logcat-release.txt; then echo "FAIL: crash/verify error"; fail=1; fi
note "dex verify"; adb shell cmd package compile -m verify -f $PKG | tee $OUT/verify.txt
grep -qi "success" $OUT/verify.txt || { echo "FAIL: dex verify"; fail=1; }
shot release

note "2) file chooser (test APK)"
python3 - <<'PY'
import zlib,struct
w=h=64; raw=b''.join(b'\x00'+bytes([30,120,200])*w for _ in range(h))
def ch(t,d): c=struct.pack('>I',len(d))+t+d; return c+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open('emu-out/test.png','wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+ch(b'IDAT',zlib.compress(raw))+ch(b'IEND',b''))
PY
adb push $OUT/test.png /sdcard/Download/test.png >/dev/null
adb push $OUT/test.png /sdcard/Pictures/test.png >/dev/null
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/test.png >/dev/null
adb shell content call --uri content://media/external_primary --method scan_volume --arg external_primary 2>&1 | head -2
adb shell content call --uri content://media --method scan_volume --arg external_primary 2>&1 | head -2
sleep 5
adb shell content query --uri content://media/external/images/media --projection _display_name 2>&1 | head -5
adb install -r out-test/signed/rent-aligned-signed.apk || fail=1
adb logcat -c
adb shell am force-stop $PKG
adb shell am start -n $PKG/.MainActivity
wait_top 60 || echo "WARN: app not on top after 60s"
sleep 3
read W H <<< "$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1 | tr x ' ')"
note "screen ${W}x${H}; tapping WebView test bar"
adb shell input tap $((W/2)) $((H/4))
sleep 4; shot picker; top | tee $OUT/top.txt
if grep -q "rentmanager" $OUT/top.txt; then echo "FAIL: picker did not open"; fail=1; fi
ui; cp $OUT/ui.xml $OUT/ui-picker.xml
note "picker texts"; python3 - <<'PY'
import xml.etree.ElementTree as ET
try:
    for n in ET.parse('emu-out/ui.xml').getroot().iter('node'):
        v=(n.get('text') or '')+'|'+(n.get('content-desc') or '')+'|'+(n.get('resource-id') or '')
        if v.strip('|'): print('  ',v)
except Exception as e: print('parse fail',e)
PY
# 파일 선택 시도 (이름이 안 보이면 Downloads 로 이동 후 재시도)
pick_tile(){  # test.png 타일의 지정 비율 위치를 탭. $1=x비율(%) $2=y비율(%)
  ui
  xy=$(python3 - "$1" "$2" <<'PY'
import sys,re,xml.etree.ElementTree as ET
fx,fy=int(sys.argv[1])/100,int(sys.argv[2])/100
try: root=ET.parse('emu-out/ui.xml').getroot()
except Exception: sys.exit(1)
for n in root.iter('node'):
    if (n.get('content-desc') or '').startswith('test.png') or (n.get('text') or '').startswith('test.png'):
        x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
        print(x1+int((x2-x1)*fx),y1+int((y2-y1)*fy)); sys.exit(0)
sys.exit(1)
PY
  ) || return 1
  note "tap tile at $xy (${1}%,${2}%)"; adb shell input tap $xy
}
for pos in "20 20" "80 80" "80 20" "20 80" "50 90"; do
  top | grep -q documentsui || break
  pick_tile $pos || { echo "WARN: tile not found"; break; }
  sleep 4
  if top | grep -q photos; then note "preview opened, going back"; adb shell input keyevent KEYCODE_BACK; sleep 3; fi
done
sleep 4; shot after
top | tee $OUT/top-final.txt
if grep -Eqi "chooser|resolver|intentresolver" $OUT/top-final.txt; then echo "PASS: file delivered to WebView (JS called Android.share with test.png)"; else echo "FAIL: file not delivered"; fail=1; fi
shot final

note "3) AI 비서 인텐트 (rentmanager://assistant) — 콜드 스타트 / 웜 스타트"
# 데이터가 없는 앱이므로 "없는 호실" 안내 화면이 뜨면 인텐트→네이티브→JS 브릿지→처리→렌더 전체 경로가 동작한 것이다.
mkcmd(){ python3 - "$1" "$2" <<'PY'
import sys,json,time,urllib.parse
c={"v":1,"id":sys.argv[1],"ts":int(time.time()*1000),"op":"record_payment","room":sys.argv[2],"amount":450000}
print('rentmanager://assistant?cmd='+urllib.parse.quote(json.dumps(c,separators=(',',':')),safe=''))
PY
}
adb install -r out/signed/rent-aligned-signed.apk || fail=1
adb shell am force-stop $PKG
adb logcat -c
adb shell am start -a android.intent.action.VIEW -c android.intent.category.DEFAULT -d "$(mkcmd cold-1 777)" -p $PKG
wait_text "찾을 수 없어요" 90; shot assistant-cold
if grep -q "777" $OUT/ui.xml && grep -q "찾을 수 없어요" $OUT/ui.xml; then echo "PASS: cold-start assistant intent handled"; else echo "FAIL: cold-start assistant intent not handled"; top; dump_texts; fail=1; fi
adb shell am start -a android.intent.action.VIEW -c android.intent.category.DEFAULT -d "$(mkcmd warm-2 888)" -p $PKG
wait_text "888" 30; shot assistant-warm
if grep -q "888" $OUT/ui.xml && ! grep -q "777" $OUT/ui.xml; then echo "PASS: warm-start assistant intent handled (replaced previous)"; else echo "FAIL: warm-start assistant intent not handled"; dump_texts; fail=1; fi
# 같은 id 재전송은 무시되어야 한다 (재시작 시 재실행 방지)
adb shell am start -a android.intent.action.VIEW -c android.intent.category.DEFAULT -d "$(mkcmd warm-2 999)" -p $PKG
sleep 3; ui
if grep -q "999" $OUT/ui.xml; then echo "FAIL: duplicate id was processed"; fail=1; else echo "PASS: duplicate id ignored"; fi
# 잘못된 URI(불투명 URI)로도 앱이 죽지 않아야 한다
adb shell am start -n $PKG/.MainActivity -a android.intent.action.VIEW -d "rentmanager:opaque"
sleep 3
adb shell pidof $PKG >/dev/null || { echo "FAIL: app died on malformed intent"; fail=1; }
adb logcat -d > $OUT/logcat-assistant.txt
if grep -E "FATAL EXCEPTION|VerifyError" $OUT/logcat-assistant.txt; then echo "FAIL: crash during assistant intents"; fail=1; fi
adb logcat -d > $OUT/logcat-test.txt
grep -E "FATAL EXCEPTION|VerifyError" $OUT/logcat-test.txt && fail=1
echo "RESULT fail=$fail"; exit $fail
