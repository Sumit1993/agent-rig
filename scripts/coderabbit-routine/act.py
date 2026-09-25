#!/usr/bin/env python3
"""The routine's three writes: act.py merge|enqueue|comment <owner/repo> <number> <head sha | comment body>."""
import sys

from digest import gh, request


def main():
    verb, repo, number, arg = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    if verb == "merge":
        res, _ = request(f"https://api.github.com/repos/{repo}/pulls/{number}/merge", {"merge_method": "squash", "sha": arg}, "PUT")
    elif verb == "enqueue":
        node = gh(f"repos/{repo}/pulls/{number}")["node_id"]
        res, _ = request("https://api.github.com/graphql", {
            "query": "mutation($p:ID!,$h:GitObjectID!){enqueuePullRequest(input:{pullRequestId:$p,expectedHeadOid:$h}){mergeQueueEntry{state}}}",
            "variables": {"p": node, "h": arg},
        })
    elif verb == "comment":
        res, _ = request(f"https://api.github.com/repos/{repo}/issues/{number}/comments", {"body": arg})
    else:
        sys.exit(f"unknown verb {verb}")
    if isinstance(res, dict) and res.get("errors"):
        sys.exit(f"failed: {res['errors']}")
    print(res)


if __name__ == "__main__":
    main()
