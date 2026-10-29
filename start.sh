#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
command -v python3 >/dev/null || { echo '需要 Python 3.9+（用于读取本地 JSON 报告），请先从 python.org 安装。'; exit 2; }
python3 -c 'import sys; assert sys.version_info >= (3,9), "需要 Python 3.9+"'
case "$(uname -s)/$(uname -m)" in
 Darwin/arm64) asset=macOS-ARM64; expected=11a9b6cd2752011b54f01ea4bd0dbfa9f0c41dc6538d5a3f9d23955f471bf4e5 ;;
 Darwin/x86_64) asset=macOS-64bit; expected=7aa762eacd582052d053b62dcf972a1ab058abe39a57ccae234ed8894945b6b7 ;;
 Linux/x86_64) asset=Linux-64bit; expected=c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0 ;;
 Linux/aarch64|Linux/arm64) asset=Linux-ARM64; expected=e174dff2a6dba5e3ae41f8d0537a6324405bd08132497340304c6b20e0f16a1f ;;
 *) echo '此入口未整理当前系统/架构，请查看官方安装文档。'; exit 2 ;;
esac
mkdir -p .runtime/downloads .runtime/bin .runtime/reports
archive=".runtime/downloads/trivy_0.76.1_${asset}.tar.gz"
if [ ! -f "$archive" ]; then
 command -v curl >/dev/null || { echo '需要 curl 下载官方发行包'; exit 2; }
 echo '首次运行：下载固定官方 v0.76.1 发行包，不需要管理员权限。'
 curl --fail --location --retry 2 --connect-timeout 20 --max-time 300 "https://github.com/aquasecurity/trivy/releases/download/v0.76.1/trivy_0.76.1_${asset}.tar.gz" -o "$archive.part"
 mv -- "$archive.part" "$archive"
fi
# 每次重新校验压缩包，再仅提取指定程序，不信任缓存的可执行文件。
python3 - "$archive" "$expected" <<'PY'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
if hashlib.sha256(p.read_bytes()).hexdigest() != sys.argv[2]:
    raise SystemExit('下载包校验不一致，已停止。请将该文件移出缓存后重试，不要跳过校验。')
PY
tar -xzf "$archive" -O trivy > .runtime/bin/trivy.tmp
chmod 700 .runtime/bin/trivy.tmp
mv .runtime/bin/trivy.tmp .runtime/bin/trivy
.runtime/bin/trivy --version
python3 - <<'PY'
import json, os, pathlib, shutil, subprocess
root = pathlib.Path.cwd()
work = root / '.runtime'
env = os.environ.copy()
env['TRIVY_CONFIG'] = str(work / 'no-default-config.yaml')
env['TRIVY_DISABLE_TELEMETRY'] = 'true'
reports = []
for stage, expected in [('before',1),('after',0)]:
    # 只扫附带的原创假样例，绝不自动扩展到用户目录。
    target = work / ('practice-' + stage)
    target.mkdir(exist_ok=True)
    shutil.copyfile(root / 'samples' / (stage + '.txt'), target / 'demo.txt')
    report = work / 'reports' / (stage + '.json')
    cmd = [str(work/'bin/trivy'), '--cache-dir',str(work/'cache'), 'fs',
           '--scanners','secret','--skip-version-check','--disable-telemetry','--offline-scan',
           '--secret-config',str(root/'practice-secret.yaml'),'--format','json',
           '--exit-code','1','--output',str(report),str(target)]
    result = subprocess.run(cmd,env=env)
    if not report.is_file(): raise SystemExit('没有生成报告；请阅读前面的真实错误。')
    data = json.loads(report.read_text(encoding='utf-8'))
    findings = [s for r in data.get('Results',[]) for s in r.get('Secrets',[])]
    if result.returncode != expected or len(findings) != expected:
        raise SystemExit(f'{stage} 未符合练习预期：退出码 {result.returncode}，发现 {len(findings)}')
    if stage=='before' and findings[0].get('RuleID') != 'repogo-demo-only':
        raise SystemExit('命中规则与练习不一致，请检查报告。')
    row = dict(stage=stage, exit_code=result.returncode, findings=len(findings))
    reports.append(row)
    print(f'{stage}: 发现 {len(findings)} 项 / 退出码 {result.returncode}',flush=True)
(work/'reports/summary.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf-8')
print('练习通过：命中 1 → 修改假样例后 0。这里只验证自定义规则流程，不代表真实项目无泄漏。')
print('报告位置：.runtime/reports/；本次没有启动常驻服务。')
PY
