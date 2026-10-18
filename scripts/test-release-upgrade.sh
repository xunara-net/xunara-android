#!/bin/sh
set -eu
serial=$1
package=$2
directory=$3
router_ip=$4
router_ipv6=$5
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
adb=$sdk/platform-tools/adb
case "$serial" in emulator-*) :;; *) echo '只允许专用模拟器。' >&2; exit 1;; esac
"$sdk/build-tools/36.0.0/apksigner" verify "$package"
if "$sdk/build-tools/36.0.0/aapt" dump badging "$package" | grep -q application-debuggable; then echo '不能用 Debug 冒充 Release 验收。' >&2; exit 1; fi
# 安装升级使用已建立的临时机器身份，正式 APK 不加入测试 IPC、Auth Key 或旁路认证。
touch "$directory/release-installed"
"$adb" -s "$serial" install -r "$package" >/dev/null
installed=$("$adb" -s "$serial" shell pm path net.xunara.android | sed -n 's/^package://p' | tr -d '\r')
expected=$(sha256sum "$package" | awk '{print $1}')
actual=$("$adb" -s "$serial" shell sha256sum "$installed" | awk '{print $1}')
[ "$expected" = "$actual" ] || { echo '已安装 APK 与待发布文件不一致。' >&2; exit 1; }
"$adb" -s "$serial" shell am start -n net.xunara.android/.MainActivity >/dev/null
press() {
    for attempt in $(seq 1 30); do
        "$adb" -s "$serial" shell 'uiautomator dump /data/local/tmp/xunara-release-window.xml >/dev/null 2>&1; cat /data/local/tmp/xunara-release-window.xml' >"$directory/release-window.xml"
        point=$(node - "$directory/release-window.xml" "$1" <<'NODE'
const fs = require('fs');
const nodes = [...fs.readFileSync(process.argv[2], 'utf8').matchAll(/<node\s+[^>]+>/g)];
const matches = nodes.flatMap(([node]) => {
  const attributes = Object.fromEntries([...node.matchAll(/([\w-]+)="([^"]*)"/g)].map(match => [match[1], match[2]]));
  if (attributes.package !== 'net.xunara.android' || attributes.clickable !== 'true' || !`${attributes['content-desc']} ${attributes.text}`.includes(process.argv[3])) return [];
  const bounds = attributes.bounds?.match(/^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$/);
  if (!bounds) return [];
  const [left, top, right, bottom] = bounds.slice(1).map(Number);
  return [{area:(right-left)*(bottom-top), horizontal:Math.floor((left+right)/2), vertical:Math.floor((top+bottom)/2)}];
}).sort((first, second) => first.area-second.area);
if (matches.length) process.stdout.write(`${matches[0].horizontal} ${matches[0].vertical}`);
NODE
)
        if [ -n "$point" ]; then
            horizontal=${point% *}
            vertical=${point#* }
            "$adb" -s "$serial" shell input tap "$horizontal" "$vertical"
            return
        fi
        if [ "$attempt" = 5 ] && [ "$1" = '共享本机网络' ] && grep -q 'package="net.xunara.android"' "$directory/release-window.xml"; then
            dimensions=$("$adb" -s "$serial" shell wm size | sed -n 's/^Physical size: //p' | tr -d '\r')
            width=${dimensions%x*}
            height=${dimensions#*x}
            "$adb" -s "$serial" shell input swipe "$((width / 2))" "$((height * 3 / 4))" "$((width / 2))" "$((height / 4))" 400
        fi
        sleep 0.3
    done
    echo 'Release 页面未出现目标按钮。' >&2
    exit 1
}
press '连接网络'
attempt=0
until "$adb" -s "$serial" shell ping -c 1 -W 1 "$router_ip" >"$directory/release-ping.log"; do
    attempt=$((attempt+1)); [ "$attempt" -lt 30 ] || exit 1; sleep 0.5
done
"$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 8 $router_ip 8088" >"$directory/release-tcp4.log"
grep -q xunara-core-ok "$directory/release-tcp4.log"
"$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -6 -w 8 $router_ipv6 8088" >"$directory/release-tcp6.log"
grep -q xunara-core-ok "$directory/release-tcp6.log"
"$adb" -s "$serial" shell ping -c 1 -W 4 rust-router.core.test >"$directory/release-magicdns.log"
grep -F "$router_ip" "$directory/release-magicdns.log" >/dev/null
"$adb" -s "$serial" exec-out screencap -p >"$directory/release-connected.png"
press '设置'
press '共享本机网络'
sleep 0.5
"$adb" -s "$serial" exec-out screencap -p >"$directory/release-forwarding.png"
"$adb" -s "$serial" shell am force-stop net.xunara.android
attempt=0
while :; do
    "$adb" -s "$serial" shell dumpsys connectivity >"$directory/release-stopped.log"
    if ! grep -q 'ni{VPN.*VPN:net.xunara.android' "$directory/release-stopped.log"; then break; fi
    attempt=$((attempt+1)); [ "$attempt" -lt 30 ] || { echo '停止 Release 后仍残留 VPN。' >&2; exit 1; }
    sleep 0.2
done
printf 'PASS 实际混淆 Release 同签名升级、无密钥连接、双栈 TCP、MagicDNS、网络共享页面及停止清理\n'
