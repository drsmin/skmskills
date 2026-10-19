#!/usr/bin/env python3
"""재독 비용 실측 — 한 세션 안에서 **같은 파일을 몇 번 통째로 읽었는지** 센다 (D-094).

정책: docs/context-budget.md. `session-cost.py` 는 호출당 입력 토큰과 「큰 출력」을 재지만,
**같은 파일을 64번 읽는 것**은 한 번에 300자씩이라 그 표에 안 걸린다. 그런데 실측에서 이게
파일 읽기 비용의 92%였다(2,936,377자 중 2,705,706자).

왜 생기나: 긴 세션은 컴팩트로 요약되고, 요약에서 빠진 파일을 다음 호출이 **다시 읽는다**.
`/clear` 없이 230회 컴팩트한 세션에서 current-task 를 64번, todo 를 48번 읽었다.
세션 시작 비용(브리핑)을 18,800자로 깎아도 64번 읽히면 120만 자다 — 그래서 **브리핑 크기를 재는
가드로는 이 비용을 볼 수 없다.** 고침은 문서가 아니라 **세션 수명**이다(마일스톤마다 `/clear`).

읽기 전용이다. 사용:
  python3 -I scripts/session-rereads.py           # 이 저장소의 최근 8개 세션
  python3 -I scripts/session-rereads.py -n 3 --top 15
  python3 -I scripts/session-rereads.py --dir ~/.claude/projects/<slug>

판단 기준: 재독분이 파일 읽기의 절반을 넘거나 한 파일이 10회를 넘으면 세션이 너무 길다.
"""
import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime

# 통째로 읽는 호출만 센다 — 범위를 지정한 것(`sed -n '10,20p'`)은 재독이 아니다.
WHOLE_READ = re.compile(r'(?:^|[;&|]\s*)(?:cat|cat -n|head|bat)\s+(?:-n\s+)?([\w./@-]+\.\w+)')
TARGET = re.compile(r'[\w./@-]+\.(?:ts|tsx|js|jsx|mjs|mts|md|json|ya?ml|sh|py|sql|xml|csv)$')


_ROOT = None


def repo_root():
    """저장소 루트. 한 번만 구해 캐시한다(norm() 이 경로마다 부른다)."""
    global _ROOT
    if _ROOT is None:
        try:
            _ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True,
                                   text=True, check=True).stdout.strip()
        except Exception:
            _ROOT = os.getcwd()
    return _ROOT


def project_dir(explicit):
    if explicit:
        return os.path.expanduser(explicit)
    slug = re.sub(r'[^A-Za-z0-9]', '-', repo_root())
    return os.path.join(os.path.expanduser('~/.claude/projects'), slug)


def norm(p):
    """경로를 저장소 기준으로 줄인다. ⚠️ basename 으로 뭉치지 말 것 — 서로 다른 `route.ts`
    여러 개가 한 줄로 합쳐져 없는 재독이 보인다(실제로 24회로 보였다)."""
    p = p.lstrip('./')
    #     저장소 이름은 박지 않는다 — git root 의 basename 을 쓴다(어느 프로젝트에서나 돈다).
    marker = os.path.basename(repo_root()) + '/'
    i = p.find(marker)
    return p[i + len(marker):] if i >= 0 else p


def targets(block):
    """이 도구 호출이 '통째로 읽은' 파일들. 범위 지정이면 빈 목록."""
    name = block.get('name', '?')
    inp = block.get('input') or {}
    if name == 'Read':
        if inp.get('offset') or inp.get('limit') or inp.get('pages'):
            return []
        p = inp.get('file_path') or ''
        return [norm(p)] if TARGET.search(p) else []
    if name == 'Bash':
        cmd = inp.get('command') or ''
        return [norm(m) for m in WHOLE_READ.findall(cmd) if TARGET.search(m)]
    return []


def analyze(path):
    reads = collections.Counter()
    chars = collections.Counter()
    pending = {}
    compacts = 0
    for line in open(path, encoding='utf-8', errors='replace'):
        if 'isCompactSummary' in line:
            compacts += 1
        try:
            d = json.loads(line)
        except ValueError:
            continue
        content = (d.get('message') or {}).get('content')
        if not isinstance(content, list):
            continue
        for b in content:
            if not isinstance(b, dict):
                continue
            if b.get('type') == 'tool_use':
                t = targets(b)
                if t:
                    pending[b.get('id')] = t
            elif b.get('type') == 'tool_result':
                t = pending.pop(b.get('tool_use_id'), None)
                if not t:
                    continue
                c = b.get('content')
                size = len(c if isinstance(c, str) else json.dumps(c, ensure_ascii=False))
                for f in t:
                    reads[f] += 1
                    chars[f] += size // len(t)
    return reads, chars, compacts


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-n', type=int, default=8, help='최근 세션 수 (기본 8)')
    ap.add_argument('--top', type=int, default=8, help='세션마다 보일 재독 파일 수 (기본 8)')
    ap.add_argument('--dir', help='세션 기록 디렉터리 (기본: 이 저장소)')
    a = ap.parse_args()

    d = project_dir(a.dir)
    files = [f for f in glob.glob(os.path.join(d, '*.jsonl')) if os.path.getsize(f) > 0]
    if not files:
        print(f'세션 기록이 없다: {d}', file=sys.stderr)
        return 1
    files.sort(key=os.path.getmtime, reverse=True)
    print(f'세션 기록: {d}\n')
    worst = 0
    for f in files[:a.n]:
        reads, chars, compacts = analyze(f)
        if not reads:
            continue
        tot = sum(chars.values())
        dup = sum(v for k, v in chars.items() if reads[k] > 1)
        pct = dup * 100 // max(tot, 1)
        worst = max(worst, pct)
        when = datetime.fromtimestamp(os.path.getmtime(f)).strftime('%Y-%m-%d %H:%M')
        print(f'{os.path.basename(f)[:8]}  {when}  통째 읽기 {sum(reads.values()):4}회 '
              f'{tot:9,}자 · 재독분 {dup:9,}자 ({pct:3}%) · 컴팩트 {compacts}회')
        for fn, n in reads.most_common(a.top):
            if n > 1:
                print(f'            {n:3}회 {chars[fn]:9,}자  {fn[-58:]}')
        print()
    if worst:
        print(f'재독분 최대 {worst}% — 절반을 넘으면 세션이 너무 길다. 고침은 문서 축소가 아니라')
        print('**마일스톤마다 `/clear`** 다(컴팩트는 요약에서 빠진 파일을 다시 읽게 만든다 · D-094).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
