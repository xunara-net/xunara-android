#!/bin/sh
set -eu
directory=$1
core=$2
if [ "$(id -u)" != 0 ] || [ "$(readlink /proc/self/ns/user)" = "$(readlink /proc/1/ns/user)" ]; then
    echo '测试服务只能在独立的 rootless user/net namespace 内运行。' >&2; exit 1;
fi
fixture=$core/target/compat-fixture
pids=''
cleanup() { for process in $pids; do kill "$process" 2>/dev/null || :; done; wait 2>/dev/null || :; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ip link set lo up
ip link add testlan type dummy
ip address add 192.168.90.2/24 dev testlan
ip link set testlan up
ip address add 203.0.113.77/32 dev lo
ip -6 address add 2001:db8::77/128 dev lo
echo 1 > /proc/sys/net/ipv4/ip_forward
"$fixture" -mode fixture -dir "$directory" >"$directory/fixture.log" 2>&1 & pids="$pids $!"
"$fixture" -mode dns -listen 0.0.0.0:5353 >"$directory/dns.log" 2>&1 & pids="$pids $!"
for port in 18080 18081; do
    case "$port" in 18080) target=8080;; 18081) target=8081;; esac
    "$fixture" -mode proxy -listen "127.0.0.1:$port" -target "127.0.0.1:$target" >"$directory/proxy-$port.log" 2>&1 & pids="$pids $!"
done
attempt=0
until [ -s "$directory/auth-key" ]; do attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.1; done
mkdir -m 700 "$directory/router"
cat >"$directory/router.json" <<EOF
{"server":"http://127.0.0.1:18080","state_dir":"$directory/router","hostname":"rust-router","interface":"xunara0","listen":"0.0.0.0:41641","advertise_routes":["192.168.90.0/24"]}
EOF
"$core/target/debug/xunara-client" run --config "$directory/router.json" --auth-key-file "$directory/auth-key" >"$directory/router.log" 2>&1 & pids="$pids $!"
for port in 8088 8089; do
    "$fixture" -mode http -listen "0.0.0.0:$port" >"$directory/http-$port.log" 2>&1 & pids="$pids $!"
done
attempt=0
until curl --noproxy '*' --max-time 2 -fsS -X POST http://127.0.0.1:18080/_test/approve >"$directory/approve.json" 2>/dev/null; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.2
done
router_ipv6=$(curl --noproxy '*' --max-time 3 -fsS 'http://127.0.0.1:18080/_test/node?host=rust-router' | jq -r .ipv6)
attempt=0
until ip -6 address show dev xunara0 2>/dev/null | grep -Fq "$router_ipv6/"; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.2
done
"$fixture" -mode http -listen "[$router_ipv6]:8088" >"$directory/http-ipv6.log" 2>&1 & pids="$pids $!"
"$fixture" -mode http -listen '[2001:db8::77]:8088' >"$directory/http-exit-ipv6.log" 2>&1 & pids="$pids $!"
"$fixture" -mode exit -dir "$directory" >"$directory/exit.log" 2>&1 & pids="$pids $!"
attempt=0
until [ -f "$directory/exit-ready" ] && curl --noproxy '*' --max-time 2 -fsS -X POST http://127.0.0.1:18080/_test/exit >"$directory/exit-approve.json" 2>/dev/null; do
    attempt=$((attempt+1)); [ "$attempt" -lt 150 ] || exit 1; sleep 0.2
done
touch "$directory/namespace-ready"
wait
