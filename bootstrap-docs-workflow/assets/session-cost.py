#!/usr/bin/env python3
"""세션 비용 실측 — Claude Code 세션 기록(~/.claude/projects/<slug>/*.jsonl)의 usage 를 읽는다.

정책: docs/context-budget.md §7. 브리핑·가드는 문서가 *얼마나 읽히는지*를 재지만, 실제로 느려지는
것은 **호출마다 들어가는 입력 토큰**이다. 그 수는 세션 기록에만 있다. 이 스크립트가 재는 것:

  시작   첫 호출의 입력 토큰 = 기본 부하(시스템 프롬프트·도구·스킬·커넥터 + CLAUDE.md·메모리)
  최대   세션 안에서 가장 컸던 호출 = 세션 안 누적(도구 출력·내가 쓴 출력)
  큰 출력 어떤 도구 결과가 대화를 키웠는지

읽기 전용이다. 사용:
  python3 -I scripts/session-cost.py              # 이 저장소의 최근 8개 세션
  python3 -I scripts/session-cost.py -n 3 --top 10
  python3 -I scripts/session-cost.py --dir ~/.claude/projects/<slug>

판단 기준(경험값): 시작이 프로젝트 문서보다 훨씬 크면 커넥터·플러그인(§7 개인 설정),
최대가 시작의 3배를 넘는 세션이 잦으면 출력 습관과 세션 끊기(§7 습관)를 본다.
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


def project_dir(explicit):
    if explicit:
        return os.path.expanduser(explicit)
    try:
        root = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True,
                              text=True, check=True).stdout.strip()
    except Exception:
        root = os.getcwd()
    # Claude Code 는 절대경로의 영숫자 아닌 문자를 '-' 로 바꿔 디렉터리 이름을 만든다.
    slug = re.sub(r'[^A-Za-z0-9]', '-', root)
    return os.path.join(os.path.expanduser('~/.claude/projects'), slug)


def tool_key(block):
    name = block.get('name', '?')
    inp = block.get('input') or {}
    if name == 'Bash':
        words = (inp.get('command') or '').split()
        # `cd x && cmd` 이면 cmd 를 본다.
        while len(words) > 2 and words[0] == 'cd' and words[2] in ('&&', ';'):
            words = words[3:]
        return f"Bash:{words[0] if words else ''}"
    if name in ('Read', 'Write', 'Edit'):
        return f"{name}:{os.path.basename(inp.get('file_path', ''))}"
    return name


def analyze(path):
    calls, seen, names = [], set(), {}
    by_tool = collections.defaultdict(lambda: [0, 0])
    big, out_tokens, start = [], 0, None
    for line in open(path, encoding='utf-8', errors='replace'):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if start is None and d.get('timestamp'):
            start = d['timestamp']
        m = d.get('message') or {}
        if d.get('type') == 'assistant' and m.get('id') not in seen:
            seen.add(m.get('id'))
            u = m.get('usage') or {}
            calls.append(u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0)
                         + u.get('cache_creation_input_tokens', 0))
            out_tokens += u.get('output_tokens', 0)
        content = m.get('content')
        if not isinstance(content, list):
            continue
        for b in content:
            if b.get('type') == 'tool_use':
                names[b.get('id')] = tool_key(b)
            elif b.get('type') == 'tool_result':
                c = b.get('content')
                size = len(c if isinstance(c, str) else json.dumps(c, ensure_ascii=False))
                k = names.get(b.get('tool_use_id'), '?')
                by_tool[k.split(':')[0]][0] += 1
                by_tool[k.split(':')[0]][1] += size
                big.append((size, k))
    return dict(calls=calls, out=out_tokens, by_tool=by_tool, big=sorted(big, reverse=True),
                start=start)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('-n', type=int, default=8, help='최근 세션 수 (기본 8)')
    ap.add_argument('--top', type=int, default=3, help='세션마다 보일 큰 출력 수 (기본 3)')
    ap.add_argument('--dir', help='세션 기록 디렉터리 (기본: 이 저장소)')
    a = ap.parse_args()

    d = project_dir(a.dir)
    files = [f for f in glob.glob(os.path.join(d, '*.jsonl')) if os.path.getsize(f) > 0]
    if not files:
        print(f'세션 기록이 없다: {d}', file=sys.stderr)
        return 1
    files.sort(key=os.path.getmtime, reverse=True)
    starts = []
    print(f'세션 기록: {d}\n')
    print('세션      시각              호출   시작(토큰)   최대(토큰)  배율  출력(토큰)  도구 결과(자)')
    rows = []
    for f in files[:a.n]:
        r = analyze(f)
        if not r['calls']:
            continue
        first, peak = r['calls'][0], max(r['calls'])
        starts.append(first)
        when = datetime.fromtimestamp(os.path.getmtime(f)).strftime('%Y-%m-%d %H:%M')
        tool_chars = sum(v[1] for v in r['by_tool'].values())
        print(f'{os.path.basename(f)[:8]}  {when}  {len(r["calls"]):5}  {first:11,}  {peak:11,}'
              f'  {peak / max(first, 1):4.1f}  {r["out"]:10,}  {tool_chars:12,}')
        rows.append((f, r))
    print()
    for f, r in rows:
        tops = ', '.join(f'{k} {n}회 {s:,}자' for k, (n, s) in
                         sorted(r['by_tool'].items(), key=lambda x: -x[1][1])[:3])
        print(f'{os.path.basename(f)[:8]}  도구별: {tops}')
        for size, k in r['big'][:a.top]:
            print(f'            {size:8,}자  {k[:70]}')
    if starts:
        starts.sort()
        print(f'\n시작 부하 중앙값 {starts[len(starts) // 2]:,} 토큰 — 커넥터·플러그인을 끈 뒤 새 세션과 비교한다.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
