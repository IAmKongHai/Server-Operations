#!/usr/bin/env bash
# 在 mac-mini 图形登录后的 Terminal 里跑一次，打通 Expo 的本机 --local 门槛。
# 不要用纯 SSH：iOS 签名可能要弹钥匙串。不要 sudo。不要把 EXPO_TOKEN 写进本文件。
#
#   /Users/konghai/gha/scripts/acquilang-first-local-eas-builds.sh
#
# 默认 preview（APK / ad hoc IPA），不递增商店版本、不 eas submit。
# 两个平台串行：先 Android，再 iOS。全程约 1–2 小时。
set -euo pipefail

if [[ $(id -u) -eq 0 ]]; then
  echo "不要用 root / sudo 跑。用图形登录用户 konghai 的 Terminal。" >&2
  exit 1
fi
if [[ "$(id -un)" != "konghai" ]]; then
  echo "当前用户是 $(id -un)，要用 konghai。" >&2
  exit 1
fi

REPO="/Users/konghai/Code/Project/AcquiLangAI"
APP="$REPO/acquilang-mobile-native"
OUT_DIR="/Users/konghai/Builds/acquilang-native-first-local"
LOG="/Users/konghai/Library/Logs/acquilang-first-local-eas-builds.log"
NODE_BIN="/opt/homebrew/opt/node@22/bin"
JAVA_HOME_VALUE="/opt/homebrew/opt/openjdk@17"
SDK="$HOME/Library/Android/sdk"

export PATH="${NODE_BIN}:${JAVA_HOME_VALUE}/bin:${SDK}/platform-tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export JAVA_HOME="$JAVA_HOME_VALUE"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export EAS_NO_VCS=1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
# 本机交互构建不要带 CI=true，否则 eas login 可能拒绝提示
unset CI || true

mkdir -p "$(dirname "$LOG")" "$OUT_DIR"
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') start pid=$$ ==="
echo "log=$LOG"
echo "out=$OUT_DIR"

if pgrep -lf Runner.Worker >/dev/null; then
  echo "有 GitHub Actions Runner.Worker 在跑。同一台 M4 不要叠 Native 编译，等 job 结束后再跑。" >&2
  pgrep -lf Runner.Worker || true
  exit 1
fi

need() {
  command -v "$1" >/dev/null || {
    echo "找不到命令: $1" >&2
    exit 1
  }
}

need node
need pnpm
need java
need adb
need pod
need xcodebuild
need git

echo "node=$(command -v node) $(node -v)"
echo "pnpm=$(command -v pnpm) $(pnpm -v)"
java -version
adb version | head -1
echo "pod=$(pod --version)"
xcodebuild -version | head -2
if ! xcodebuild -checkFirstLaunchStatus; then
  echo "Xcode first launch 未完成（exit != 0）。先在本机跑 sudo xcodebuild -runFirstLaunch。" >&2
  exit 1
fi
if [[ ! -d "$SDK" ]]; then
  echo "没有 Android SDK: $SDK" >&2
  exit 1
fi
if ! java -version 2>&1 | grep -q 'version "17\.'; then
  echo "JAVA_HOME 不是 JDK 17: $JAVA_HOME" >&2
  exit 1
fi

cd "$REPO"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "$REPO 有未提交改动，先处理后再跑。git status:" >&2
  git status --short >&2
  exit 1
fi
git fetch origin master
git merge --ff-only origin/master
echo "HEAD=$(git log -1 --oneline)"

cd "$APP"
corepack enable
corepack prepare pnpm@9.15.1 --activate
hash -r
echo "pnpm now $(command -v pnpm) $(pnpm -v)"
pnpm install --frozen-lockfile

eas() {
  npx --yes eas-cli@latest "$@"
}

if ! eas whoami; then
  echo "未登录 Expo。接下来会交互登录（浏览器或账号密码）。"
  eas login
  eas whoami
fi

build_one() {
  local platform="$1"
  local ext="$2"
  local out="$OUT_DIR/${platform}-preview.${ext}"
  echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') build $platform -> $out ==="
  rm -f "$out"
  eas build \
    --platform "$platform" \
    --profile preview \
    --local \
    --output "$out"
  ls -lh "$out"
}

build_one android apk
build_one ios ipa

echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') done ==="
echo "Android: $OUT_DIR/android-preview.apk"
echo "iOS:     $OUT_DIR/ios-preview.ipa"
echo "未执行 eas submit。CI 门槛已打通后，再到 GitHub Actions 跑 production。"
echo "完整日志: $LOG"
