#!/usr/bin/env bash
# 把现行 Apple WWDR G3/G4 + Root CA G3 装进 System.keychain。
# mac-mini LaunchDaemon 读不了登录钥匙串；System 里旧 WWDR 已于 2023-02-07 过期，
# 导致 eas build --local 在 [CP] Embed Pods Frameworks 签 React.framework 时
# codesign: unable to build chain / errSecInternalComponent。
#
# 用法（在 mac-mini 上，需要本机 sudo 密码）：
#   bash ~/bin/install-apple-wwdr-system.sh
set -euo pipefail

DIR="${TMPDIR:-/tmp}/apple-wwdr-$$"
mkdir -p "$DIR"
cleanup() { rm -rf "$DIR"; }
trap cleanup EXIT

cd "$DIR"
curl -fsSL -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
curl -fsSL -O https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer
curl -fsSL -O https://www.apple.com/certificateauthority/AppleRootCA-G3.cer

for f in AppleWWDRCAG3.cer AppleWWDRCAG4.cer AppleRootCA-G3.cer; do
  echo "==> add $f to System.keychain"
  sudo security add-certificates -k /Library/Keychains/System.keychain "$DIR/$f" \
    || echo "    (already present or add returned non-zero; continuing)"
done

echo "==> System WWDR / Root after install:"
security find-certificate -a -c "Apple Worldwide Developer Relations" -p \
  /Library/Keychains/System.keychain \
  | openssl crl2pkcs7 -nocrl -certfile /dev/stdin \
  | openssl pkcs7 -print_certs -text -noout \
  | grep -E "Subject:|Not After"

echo "done. 不需要重启 runner；下一枪 platform=ios 即可。"
