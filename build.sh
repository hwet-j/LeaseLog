#!/usr/bin/env bash
# 월세 관리 앱 APK 빌드 (apktool + uber-apk-signer)
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p tools out keys
[ -f tools/apktool.jar ] || curl -fsSL -o tools/apktool.jar https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar
[ -f tools/uber-signer.jar ] || curl -fsSL -o tools/uber-signer.jar https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar

# 서명 키가 없으면 새로 생성 (주의: 기존 앱 위에 업데이트 설치하려면 원래 키가 필요)
[ -f keys/rent-release.jks ] || keytool -genkeypair -keystore keys/rent-release.jks -storepass rent1234 -keypass rent1234 \
  -alias rent -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Rent Manager, O=Personal, C=KR"

rm -rf build out/rent-unsigned.apk out/signed
java -jar tools/apktool.jar b . -o out/rent-unsigned.apk
java -jar tools/uber-signer.jar -a out/rent-unsigned.apk --ks keys/rent-release.jks --ksAlias rent \
  --ksPass rent1234 --ksKeyPass rent1234 -o out/signed --allowResign

echo "완료: out/signed/rent-aligned-signed.apk"
