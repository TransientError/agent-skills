#!/usr/bin/env python3
"""Look up PR status for branches or PR ids. Provider auto-detected from origin URL.

Linux/mac equivalent of Get-PrStatus.ps1.
  Azure DevOps (visualstudio.com / dev.azure.com) -> uses `az repos pr`
  GitHub (github.com)                             -> uses `gh pr`

Status normalised to: completed | active | abandoned | none | unknown.
Safe to delete when completed or abandoned.

Usage:
  get-pr-status.py [-C repo] [--branch B ...] [--pr-id N ...]
"""
import argparse, json, re, shutil, subprocess, sys
from urllib.parse import unquote


def git(repo, *a):
    return subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True).stdout.strip()


def run_json(*a):
    exe = shutil.which(a[0])
    if not exe:
        return None
    p = subprocess.run([exe, *a[1:]], capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return None


def detect(url):
    m = re.match(r"https?://([^./]+)\.visualstudio\.com/(?:DefaultCollection/)?([^/]+)/_git/([^/]+?)(?:\.git)?/?$", url)
    if m:
        return "ado", {"org": f"https://{m.group(1)}.visualstudio.com", "project": unquote(m.group(2)), "repo": unquote(m.group(3))}
    m = re.match(r"https?://dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+?)(?:\.git)?/?$", url)
    if m:
        return "ado", {"org": f"https://dev.azure.com/{m.group(1)}", "project": unquote(m.group(2)), "repo": unquote(m.group(3))}
    if "github.com" in url:
        return "github", {}
    raise SystemExit(f"Unrecognised origin host: {url}")


def norm_ado(s):
    return s if s in ("completed", "active", "abandoned") else "unknown"


def norm_gh(state, merged):
    if merged:
        return "completed"
    return {"OPEN": "active", "CLOSED": "abandoned"}.get(state, "unknown")


def ado_query(a, branch=None, prid=None):
    if prid:
        j = run_json("az", "repos", "pr", "show", "--id", str(prid), "--org", a["org"], "-o", "json")
        if not j:
            return (prid, "unknown", "")
        return (j["pullRequestId"], norm_ado(j["status"]), j["title"])
    j = run_json("az", "repos", "pr", "list", "--source-branch", f"refs/heads/{branch}",
                 "--status", "all", "--org", a["org"], "--project", a["project"], "--repository", a["repo"], "-o", "json")
    if not j:
        return (None, "none", "")
    p = max(j, key=lambda x: x["pullRequestId"])
    return (p["pullRequestId"], norm_ado(p["status"]), p["title"])


def gh_query(branch=None, prid=None):
    if prid:
        j = run_json("gh", "pr", "view", str(prid), "--json", "number,state,isMerged,title")
        if not j:
            return (prid, "unknown", "")
        return (j["number"], norm_gh(j["state"], j["isMerged"]), j["title"])
    j = run_json("gh", "pr", "list", "--head", branch, "--state", "all", "--json", "number,state,isMerged,title")
    if not j:
        return (None, "none", "")
    p = max(j, key=lambda x: x["number"])
    return (p["number"], norm_gh(p["state"], p["isMerged"]), p["title"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-C", dest="repo", default=".")
    ap.add_argument("--branch", action="append", default=[])
    ap.add_argument("--pr-id", type=int, action="append", default=[])
    args = ap.parse_args()

    url = git(args.repo, "remote", "get-url", "origin")
    if not url:
        raise SystemExit(f"No origin remote at {args.repo}")
    provider, a = detect(url)

    rows = []
    for pid in args.pr_id:
        r = ado_query(a, prid=pid) if provider == "ado" else gh_query(prid=pid)
        rows.append((f"pr:{pid}", *r))
    for b in args.branch:
        r = ado_query(a, branch=b) if provider == "ado" else gh_query(branch=b)
        rows.append((b, *r))

    print(f"{'QUERY':<32} {'PRID':<9} {'STATUS':<10} TITLE")
    for q, prid, status, title in rows:
        print(f"{q:<32} {str(prid or ''):<9} {status:<10} {title}")


if __name__ == "__main__":
    main()
