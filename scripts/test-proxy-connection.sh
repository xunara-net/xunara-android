#!/bin/sh
set -eu
exec nsenter -t "$1" -U -n --preserve-credentials socat STDIO "TCP4:127.0.0.1:$2"
