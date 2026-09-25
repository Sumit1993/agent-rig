#!/usr/bin/env python3
"""The routine's two writes: act.py merge|comment <owner/repo> <number> <head sha | comment body>."""
import sys

from digest import MARKER, request


def main():
    verb, repo, number, arg = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    if verb == "merge":
        res, _ = request(f"https://api.github.com/repos/{repo}/pulls/{number}/merge", {"merge_method": "squash", "sha": arg}, "PUT")
    elif verb == "comment":
        res, _ = request(f"https://api.github.com/repos/{repo}/issues/{number}/comments", {"body": f"{arg}\n\n{MARKER}"})
    else:
        sys.exit(f"unknown verb {verb}")
    if isinstance(res, dict) and res.get("errors"):
        sys.exit(f"failed: {res['errors']}")
    print(res)


if __name__ == "__main__":
    main()
