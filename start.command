#!/usr/bin/env bash
cd -- "$(dirname -- "$0")"
bash ./start.sh
result=$?
read -r -p '按回车关闭窗口…' _
exit "$result"
