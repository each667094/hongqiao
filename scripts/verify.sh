#!/bin/zsh
set -eu
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
if [[ ! -x work/build/release/HongqiaoChecks || ! -x outputs/鸿桥.app/Contents/MacOS/Hongqiao ]]; then
  ./scripts/build.sh
fi
work/build/release/HongqiaoChecks > outputs/核心检查.json
outputs/鸿桥.app/Contents/MacOS/Hongqiao --verify > outputs/验证结果.json
cat outputs/核心检查.json
cat outputs/验证结果.json
