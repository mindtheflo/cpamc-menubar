#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$task_root/.build/plugin" "$task_root/dist/plugin"
python3 - "$task_root" <<'PY'
import base64,json,sys
from pathlib import Path
root=Path(sys.argv[1])
response={'ok':True,'result':{'StatusCode':200,'Headers':{
    'Content-Type':['text/html; charset=utf-8'],
    'Cache-Control':['no-store'], 'X-Content-Type-Options':['nosniff'],
},'Body':base64.b64encode((root/'plugin/menubar.html').read_bytes()).decode()}}
literal=json.dumps(json.dumps(response,separators=(',',':')),ensure_ascii=True)
(root/'.build/plugin/resource.h').write_text('#define CPAMC_RESOURCE_RESPONSE '+literal+'\n')
PY
cc -std=c11 -Wall -Wextra -Werror -fvisibility=hidden -dynamiclib \
  -I "$task_root/.build/plugin" "$task_root/plugin/plugin.c" \
  -o "$task_root/dist/plugin/cpamc-menubar.dylib"
codesign --force --sign - "$task_root/dist/plugin/cpamc-menubar.dylib"
printf 'Built CPAMC plugin: %s\n' "$task_root/dist/plugin/cpamc-menubar.dylib"
