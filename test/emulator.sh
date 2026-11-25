#!/usr/bin/env bash
# 에뮬레이터 검증: (1) 릴리스 APK 설치·실행·dex 검증, (2) 테스트 APK로 파일 선택창 → 선택 → JS 수신까지
set -u
PKG=com.rentmanager.app
OUT=emu-out; mkdir -p $OUT
fail=0
note(){ echo "== $*"; }
ui(){ adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml $OUT/ui.xml >/dev/null 2>&1; }
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
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/test.png >/dev/null
adb install -r out-test/signed/rent-aligned-signed.apk || fail=1
adb logcat -c
adb shell am force-stop $PKG
adb shell am start -n $PKG/.MainActivity
sleep 8
read W H <<< "$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1 | tr x ' ')"
note "screen ${W}x${H}; tapping WebView test bar"
adb shell input tap $((W/2)) $((H/4))
sleep 4; shot picker; top | tee $OUT/top.txt
if grep -q "rentmanager" $OUT/top.txt; then echo "FAIL: picker did not open"; fail=1; fi
ui; cp $OUT/ui.xml $OUT/ui-picker.xml
# 파일 선택 시도 (이름이 안 보이면 Downloads 로 이동 후 재시도)
tap_text test.png || { tap_text Downloads; sleep 3; tap_text test.png; } || echo "WARN: test.png not found in picker"
sleep 4; shot after
top | tee $OUT/top-final.txt
if grep -Eqi "chooser|resolver|intentresolver" $OUT/top-final.txt; then echo "PASS: file delivered to WebView (JS called Android.share with test.png)"; else echo "FAIL: file not delivered"; fail=1; fi
shot final
adb logcat -d > $OUT/logcat-test.txt
grep -E "FATAL EXCEPTION|VerifyError" $OUT/logcat-test.txt && fail=1
echo "RESULT fail=$fail"; exit $fail
