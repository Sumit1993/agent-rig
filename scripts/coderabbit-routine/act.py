#!/usr/bin/env python3
"""The routine's one write: act.py <owner/repo> <number> '<comment body>'. It adds the summoned-by marker."""
import sys

from digest import MARKER, request


def main():
    repo, number, body = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    res, _ = request(f"https://api.github.com/repos/{repo}/issues/{number}/comments", {"body": f"{body}\n\n{MARKER}"})
    print(res["html_url"])


if __name__ == "__main__":
    main()
