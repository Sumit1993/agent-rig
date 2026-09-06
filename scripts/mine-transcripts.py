#!/usr/bin/env python3
"""
B-transcripts.py: Stream Claude Code transcripts and aggregate usage patterns.
Aggregates for the last 30 days by timestamp plus all-time totals.
"""

import os
import sys
import glob
import json
import math
import re
import argparse
from datetime import datetime, timezone, timedelta
from collections import defaultdict, Counter

DEFAULT_PROJECTS_DIR = os.path.expanduser("~/.claude/projects")
MODEL_RE = re.compile(r"--model(?:=|\s+)(?:\"([^\"]+)\"|\'([^\']+)\'|(\S+))")
EDIT_TOOLS = {"Edit", "Write", "NotebookEdit"}


def get_bytes(content):
    if isinstance(content, str):
        return len(content.encode("utf-8", errors="replace"))
    elif isinstance(content, list):
        b = 0
        for item in content:
            if isinstance(item, str):
                b += len(item.encode("utf-8", errors="replace"))
            elif isinstance(item, dict):
                if "text" in item and isinstance(item["text"], str):
                    b += len(item["text"].encode("utf-8", errors="replace"))
                else:
                    b += len(json.dumps(item).encode("utf-8", errors="replace"))
            else:
                b += len(str(item).encode("utf-8", errors="replace"))
        return b
    elif isinstance(content, dict):
        return len(json.dumps(content).encode("utf-8", errors="replace"))
    return 0


def calc_stats(values):
    if not values:
        return {"min": 0, "median": 0, "p90": 0, "max": 0, "total": 0, "count": 0}
    vals = sorted(values)
    n = len(vals)
    median = vals[n // 2] if n % 2 != 0 else (vals[n // 2 - 1] + vals[n // 2]) / 2
    p90_idx = int(math.ceil(0.9 * n)) - 1
    p90 = vals[min(p90_idx, n - 1)]
    return {
        "min": vals[0],
        "median": median,
        "p90": p90,
        "max": vals[-1],
        "total": sum(vals),
        "count": n
    }


def parse_iso(ts_str):
    if not ts_str:
        return None
    try:
        if ts_str.endswith("Z"):
            ts_str = ts_str[:-1] + "+00:00"
        return datetime.fromisoformat(ts_str)
    except Exception:
        return None


def run_analysis(projects_dir=DEFAULT_PROJECTS_DIR, days=30):
    if not os.path.isdir(projects_dir):
        raise FileNotFoundError(f"Projects directory not found: {projects_dir}")

    all_files = glob.glob(os.path.join(projects_dir, "**", "*.jsonl"), recursive=True)
    
    ref_time = datetime(2026, 9, 4, 5, 41, 12, tzinfo=timezone.utc)
    cutoff_30d = ref_time - timedelta(days=days)

    class Agg:
        def __init__(self):
            self.sessions = set()
            self.main_lines = 0
            self.side_lines = 0
            self.project_sessions = defaultdict(set)
            self.project_main_lines = Counter()
            self.project_side_lines = Counter()
            self.model_tokens = defaultdict(lambda: {"turns": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0})
            self.project_tokens = defaultdict(lambda: {"turns": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0})
            self.tool_calls = Counter()
            self.tool_result_bytes = defaultdict(int)
            self.agent_spawns = Counter()
            self.compaction_events = 0
            self.compaction_per_session = Counter()
            self.agy_count = 0
            self.agy_per_session = Counter()
            self.agy_models = Counter()
            self.session_edits = defaultdict(lambda: {"main": 0, "sidechain": 0})
            self.session_turns = defaultdict(lambda: {"turns": 0, "main": 0, "side": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0, "project": ""})

    all_time = Agg()
    recent = Agg()
    daily = defaultdict(lambda: {"sessions": set(), "main_lines": 0, "side_lines": 0})
    tool_map = {}

    for f in all_files:
        is_sub = "/subagents/" in f
        rel = os.path.relpath(f, projects_dir)
        parts = rel.split(os.sep)
        project_slug = parts[0]
        if is_sub:
            sub_idx = parts.index("subagents")
            file_session_id = parts[sub_idx - 1]
        else:
            file_session_id = os.path.splitext(parts[-1])[0]

        with open(f, "r", encoding="utf-8", errors="replace") as fp:
            for line in fp:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue

                ts_str = d.get("timestamp")
                dt = parse_iso(ts_str)
                in_30d = (dt is not None and dt >= cutoff_30d)

                sess_id = d.get("sessionId") or d.get("session_id") or file_session_id
                is_sc = d.get("isSidechain")
                if is_sc is None:
                    is_sc = is_sub

                line_type = d.get("type")

                # Daily tracking
                if ts_str:
                    day_key = ts_str[:10]
                    daily[day_key]["sessions"].add(sess_id)
                    if is_sc:
                        daily[day_key]["side_lines"] += 1
                    else:
                        daily[day_key]["main_lines"] += 1

                for target, cond in [(all_time, True), (recent, in_30d)]:
                    if cond:
                        target.sessions.add(sess_id)
                        target.project_sessions[project_slug].add(sess_id)
                        if is_sc:
                            target.side_lines += 1
                            target.project_side_lines[project_slug] += 1
                        else:
                            target.main_lines += 1
                            target.project_main_lines[project_slug] += 1

                # Compaction check
                is_compact = False
                if d.get("isCompactSummary") is True or line_type in ("compact", "compact_summary", "compaction", "summary"):
                    is_compact = True
                if d.get("subtype") in ("compact", "compact_summary", "compaction"):
                    is_compact = True
                if is_compact:
                    all_time.compaction_events += 1
                    all_time.compaction_per_session[sess_id] += 1
                    if in_30d:
                        recent.compaction_events += 1
                        recent.compaction_per_session[sess_id] += 1

                # Assistant turns
                if line_type == "assistant":
                    msg = d.get("message")
                    if isinstance(msg, dict):
                        model = msg.get("model") or "unknown"
                        usage = msg.get("usage") or {}
                        inp = usage.get("input_tokens", 0)
                        out = usage.get("output_tokens", 0)
                        cr = usage.get("cache_read_input_tokens", 0)
                        cc = usage.get("cache_creation_input_tokens", 0)

                        for target, cond in [(all_time, True), (recent, in_30d)]:
                            if cond:
                                mt = target.model_tokens[model]
                                mt["turns"] += 1
                                mt["input"] += inp
                                mt["output"] += out
                                mt["cache_read"] += cr
                                mt["cache_creation"] += cc

                                pt = target.project_tokens[project_slug]
                                pt["turns"] += 1
                                pt["input"] += inp
                                pt["output"] += out
                                pt["cache_read"] += cr
                                pt["cache_creation"] += cc

                                st = target.session_turns[sess_id]
                                st["turns"] += 1
                                if is_sc:
                                    st["side"] += 1
                                else:
                                    st["main"] += 1
                                st["input"] += inp
                                st["output"] += out
                                st["cache_read"] += cr
                                st["cache_creation"] += cc
                                st["project"] = project_slug

                        content = msg.get("content")
                        if isinstance(content, list):
                            for c in content:
                                if isinstance(c, dict) and c.get("type") == "tool_use":
                                    t_name = c.get("name") or "unknown"
                                    t_id = c.get("id")
                                    if t_id:
                                        tool_map[t_id] = t_name

                                    for target, cond in [(all_time, True), (recent, in_30d)]:
                                        if cond:
                                            target.tool_calls[t_name] += 1

                                            if t_name in EDIT_TOOLS:
                                                if is_sc:
                                                    target.session_edits[sess_id]["sidechain"] += 1
                                                else:
                                                    target.session_edits[sess_id]["main"] += 1

                                            if t_name == "Agent":
                                                inp_data = c.get("input", {})
                                                if isinstance(inp_data, dict):
                                                    stype = inp_data.get("subagent_type") or inp_data.get("type") or "unspecified"
                                                    m_spawn = inp_data.get("model") or "unspecified"
                                                    target.agent_spawns[(stype, m_spawn)] += 1

                                            if t_name == "Bash":
                                                cmd = c.get("input", {}).get("command", "")
                                                if "agy " in cmd:
                                                    target.agy_count += 1
                                                    target.agy_per_session[sess_id] += 1
                                                    m_match = MODEL_RE.search(cmd)
                                                    if m_match:
                                                        slug = m_match.group(1) or m_match.group(2) or m_match.group(3)
                                                        slug = slug.strip("\"'\\")
                                                        target.agy_models[slug] += 1
                                                    else:
                                                        target.agy_models["(no --model)"] += 1

                elif line_type == "user":
                    msg = d.get("message")
                    if isinstance(msg, dict):
                        content = msg.get("content")
                        if isinstance(content, list):
                            for c in content:
                                if isinstance(c, dict) and c.get("type") == "tool_result":
                                    t_id = c.get("tool_use_id")
                                    t_name = tool_map.get(t_id, "unknown")
                                    n_bytes = get_bytes(c.get("content"))
                                    all_time.tool_result_bytes[t_name] += n_bytes
                                    if in_30d:
                                        recent.tool_result_bytes[t_name] += n_bytes

    return all_time, recent, daily


def print_report(all_time, recent, daily):
    print("=" * 80)
    print("CLAUDE CODE TRANSCRIPTS USAGE AUDIT")
    print("=" * 80)

    print("\n--- 1. OVERVIEW & SESSIONS ---")
    print(f"All-Time: {len(all_time.sessions)} unique sessions, {all_time.main_lines:,} main lines, {all_time.side_lines:,} sidechain lines ({all_time.main_lines + all_time.side_lines:,} total)")
    print(f"Last 30d: {len(recent.sessions)} unique sessions, {recent.main_lines:,} main lines, {recent.side_lines:,} sidechain lines ({recent.main_lines + recent.side_lines:,} total)")

    print("\n--- SESSIONS PER PROJECT (Last 30 Days / All-Time) ---")
    projects = sorted(all_time.project_sessions.keys())
    print(f"{'Project Slug':45s} | {'30d Sess':8s} | {'30d Main':8s} | {'30d Side':8s} | {'All Sess':8s} | {'All Main':8s} | {'All Side':8s}")
    print("-" * 105)
    for p in projects:
        r_s = len(recent.project_sessions.get(p, set()))
        r_m = recent.project_main_lines.get(p, 0)
        r_sd = recent.project_side_lines.get(p, 0)
        a_s = len(all_time.project_sessions.get(p, set()))
        a_m = all_time.project_main_lines.get(p, 0)
        a_sd = all_time.project_side_lines.get(p, 0)
        print(f"{p[:45]:45s} | {r_s:8d} | {r_m:8d} | {r_sd:8d} | {a_s:8d} | {a_m:8d} | {a_sd:8d}")

    print("\n--- SESSIONS & LINES PER DAY (Last 30 Days) ---")
    print(f"{'Date':12s} | {'Sessions':8s} | {'Main Lines':10s} | {'Sidechain Lines':15s} | {'Total Lines':12s}")
    print("-" * 65)
    for day in sorted(daily.keys()):
        s_cnt = len(daily[day]["sessions"])
        m_l = daily[day]["main_lines"]
        sd_l = daily[day]["side_lines"]
        tot = m_l + sd_l
        print(f"{day:12s} | {s_cnt:8d} | {m_l:10d} | {sd_l:15d} | {tot:12d}")

    print("\n--- 2. TOKENS BY MODEL ---")
    print(f"{'Model':30s} | {'Period':8s} | {'Turns':6s} | {'Input':10s} | {'Output':10s} | {'Cache Read':14s} | {'Cache Create':12s}")
    print("-" * 105)
    for m in sorted(all_time.model_tokens.keys()):
        for label, agg in [("30d", recent), ("All-time", all_time)]:
            st = agg.model_tokens.get(m, {"turns": 0, "input": 0, "output": 0, "cache_read": 0, "cache_creation": 0})
            if st["turns"] > 0:
                print(f"{m:30s} | {label:8s} | {st['turns']:6d} | {st['input']:10,d} | {st['output']:10,d} | {st['cache_read']:14,d} | {st['cache_creation']:12,d}")

    print("\n--- TOKENS BY PROJECT (Top 10 All-Time) ---")
    print(f"{'Project Slug':45s} | {'Turns':6s} | {'Input':10s} | {'Output':10s} | {'Cache Read':14s} | {'Cache Create':12s}")
    print("-" * 105)
    top_projs = sorted(all_time.project_tokens.items(), key=lambda x: x[1]["cache_read"] + x[1]["input"], reverse=True)[:10]
    for p, st in top_projs:
        print(f"{p[:45]:45s} | {st['turns']:6d} | {st['input']:10,d} | {st['output']:10,d} | {st['cache_read']:14,d} | {st['cache_creation']:12,d}")

    print("\n--- 3. TOOL CALLS & RESULT BYTES ---")
    print(f"{'Tool Name':50s} | {'30d Calls':9s} | {'30d Bytes':12s} | {'All Calls':9s} | {'All Bytes':12s}")
    print("-" * 100)
    top_tools = sorted(all_time.tool_calls.keys(), key=lambda t: all_time.tool_result_bytes.get(t, 0), reverse=True)
    for t in top_tools:
        r_c = recent.tool_calls.get(t, 0)
        r_b = recent.tool_result_bytes.get(t, 0)
        a_c = all_time.tool_calls.get(t, 0)
        a_b = all_time.tool_result_bytes.get(t, 0)
        print(f"{t[:50]:50s} | {r_c:9d} | {r_b/(1024*1024):9.2f} MB | {a_c:9d} | {a_b/(1024*1024):9.2f} MB")

    print("\n--- 4. EDIT/WRITE CALLS PER SESSION (Main vs Sidechains) ---")
    for label, agg in [("Last 30 Days", recent), ("All-Time", all_time)]:
        main_edits = [agg.session_edits[s]["main"] for s in agg.sessions]
        side_edits = [agg.session_edits[s]["sidechain"] for s in agg.sessions]
        m_st = calc_stats(main_edits)
        s_st = calc_stats(side_edits)
        print(f"[{label}] (N = {len(agg.sessions)} sessions)")
        print(f"  Main Session Edits:   min={m_st['min']}, median={m_st['median']:.1f}, p90={m_st['p90']}, max={m_st['max']}, total={m_st['total']}")
        print(f"  Sidechain Edits:      min={s_st['min']}, median={s_st['median']:.1f}, p90={s_st['p90']}, max={s_st['max']}, total={s_st['total']}")

    print("\n--- 5. AGENT TOOL SPAWNS ---")
    print(f"{'Subagent Type':25s} | {'Model':20s} | {'30d Spawns':10s} | {'All-Time Spawns':15s}")
    print("-" * 75)
    for pair, a_cnt in all_time.agent_spawns.most_common():
        stype, m_spawn = pair
        r_cnt = recent.agent_spawns.get(pair, 0)
        print(f"{stype:25s} | {m_spawn:20s} | {r_cnt:10d} | {a_cnt:15d}")

    print("\n--- 6. COMPACTION EVENTS ---")
    print(f"All-Time Compactions: {all_time.compaction_events} (across {len(all_time.sessions)} sessions)")
    print(f"Last 30d Compactions: {recent.compaction_events} (across {len(recent.sessions)} sessions)")

    print("\n--- 7. BASH AGY INVOCATIONS ---")
    for label, agg in [("Last 30 Days", recent), ("All-Time", all_time)]:
        sess_agy = len([s for s in agg.sessions if agg.agy_per_session[s] > 0])
        print(f"[{label}] Total agy commands: {agg.agy_count} across {sess_agy} sessions")
        print("  Model slugs passed:")
        for s_slug, cnt in agg.agy_models.most_common():
            print(f"    {s_slug:35s}: {cnt}")

    print("\n--- 8. LONGEST SESSIONS ---")
    print("Top 10 Sessions by Assistant Turn Count (All-Time):")
    top_by_turns = sorted(all_time.session_turns.items(), key=lambda x: x[1]["turns"], reverse=True)[:10]
    for s_id, data in top_by_turns:
        print(f"  {s_id[:12]}.. | Proj: {data['project'][:35]:35s} | Turns: {data['turns']:4d} (main {data['main']:3d}, side {data['side']:3d}) | Inp: {data['input']:7,d} | CacheRead: {data['cache_read']:11,d}")

    print("\nTop 10 Sessions by Total Input Tokens (Raw input_tokens):")
    top_by_inp = sorted(all_time.session_turns.items(), key=lambda x: x[1]["input"], reverse=True)[:10]
    for s_id, data in top_by_inp:
        print(f"  {s_id[:12]}.. | Proj: {data['project'][:35]:35s} | Raw Inp: {data['input']:7,d} | Turns: {data['turns']:4d} | CacheRead: {data['cache_read']:11,d}")

    print("\nTop 10 Sessions by Total Effective Tokens (Input + Cache Read):")
    top_by_eff = sorted(all_time.session_turns.items(), key=lambda x: x[1]["input"] + x[1]["cache_read"], reverse=True)[:10]
    for s_id, data in top_by_eff:
        tot_eff = data["input"] + data["cache_read"]
        print(f"  {s_id[:12]}.. | Proj: {data['project'][:35]:35s} | Total Inp+Cache: {tot_eff:11,d} | Raw Inp: {data['input']:7,d} | CacheRead: {data['cache_read']:11,d}")


def main():
    parser = argparse.ArgumentParser(description="Mine Claude Code transcripts for usage patterns.")
    parser.add_argument("--transcripts-dir", default=DEFAULT_PROJECTS_DIR, help="Path to ~/.claude/projects")
    parser.add_argument("--days", type=int, default=30, help="Number of days for recent aggregation window")
    args = parser.parse_args()

    if not os.path.isdir(args.transcripts_dir):
        print(f"Error: Directory not found: {args.transcripts_dir}", file=sys.stderr)
        sys.exit(1)

    all_time, recent, daily = run_analysis(projects_dir=args.transcripts_dir, days=args.days)
    print_report(all_time, recent, daily)


if __name__ == "__main__":
    main()
