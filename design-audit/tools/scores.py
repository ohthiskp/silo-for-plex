"""Astra UI/UX audit scores (design-audit/). Run: python3 design-audit/tools/scores.py
Recomputes every weighted, UX and UI score from the 0-10 dimension scores, so the
numbers in the scorecards can be checked and re-run after a redesign."""
W = dict(ia=20, vis=20, task=20, plat=15, cons=10, a11y=10, perf=5)
UX = ["ia", "task", "plat", "a11y", "perf"]   # experience dimensions (70 pts)
UI = ["vis", "cons"]                          # interface dimensions (30 pts)

def total(s): return round(sum(s[k] / 10 * W[k] for k in W))
def ux(s): return round(sum(s[k] * W[k] for k in UX) / sum(W[k] for k in UX) * 10)
def ui(s): return round(sum(s[k] * W[k] for k in UI) / sum(W[k] for k in UI) * 10)
def band(t): return ("excellent" if t >= 90 else "strong" if t >= 80 else "acceptable" if t >= 70
                     else "weak" if t >= 60 else "redesign candidate")

def S(ia, vis, task, plat, cons, a11y, perf): return dict(ia=ia, vis=vis, task=task, plat=plat, cons=cons, a11y=a11y, perf=perf)

SCREENS = {
  "iPhone": [
    ("Settings", S(5, 6, 5, 6, 6, 5, 5), "High"),
    ("Home / For You", S(7, 8, 7, 7, 7, 6, 6), "Medium"),
    ("Provider Home (Netflix, Hulu...)", S(7, 7, 7, 7, 8, 6, 6), "Low (provisional)"),
    ("Search: idle, results, filters", S(7, 7, 7, 7, 6, 6, 7), "Medium"),
    ("Library: Movies / Shows browse", S(6, 6, 6, 7, 6, 6, 6), "Medium"),
    ("Library: Watchlist", S(6, 6, 6, 7, 7, 6, 6), "Low (provisional)"),
    ("Library: Downloads", S(6, 6, 6, 7, 7, 6, 6), "Low (provisional)"),
    ("Movie details", S(8, 8, 8, 7, 7, 6, 7), "Medium"),
    ("Show details, seasons, episodes", S(6, 7, 6, 7, 7, 6, 5), "Medium"),
    ("Player and overlays", S(7, 8, 8, 8, 7, 5, 7), "Medium"),
    ("Crash report", S(8, 8, 8, 8, 8, 7, 8), "High"),
    ("Loading, offline, server-down states", S(6, 7, 6, 7, 7, 6, 6), "Low (provisional)"),
  ],
  "Apple TV": [
    ("Settings", S(5, 6, 4, 5, 6, 5, 5), "High"),
    ("Home / For You + provider rail", S(7, 8, 7, 6, 7, 5, 6), "Medium"),
    ("Movies / Shows browse", S(6, 6, 6, 6, 7, 5, 6), "Medium (Shows provisional)"),
    ("Search", S(6, 6, 6, 6, 6, 5, 6), "Medium"),
    ("Watchlist", S(5, 5, 5, 6, 6, 5, 4), "Medium (captured before the #14 error-state fix)"),
    ("Movie details", S(8, 7, 7, 7, 6, 6, 7), "Medium"),
    ("Show details, seasons, episodes", S(6, 7, 6, 7, 6, 6, 5), "Medium"),
    ("Player and overlays", S(7, 6, 7, 8, 7, 6, 7), "Medium"),
  ],
  "Mac": [
    ("Home", S(7, 8, 7, 6, 7, 6, 6), "Low (provisional)"),
    ("Details", S(8, 8, 8, 6, 7, 6, 7), "Low (provisional)"),
    ("Movies / Shows browse", S(7, 7, 7, 7, 7, 6, 6), "Low (provisional)"),
    ("Search", S(7, 7, 7, 7, 6, 6, 7), "Low (provisional)"),
    ("Watchlist (error state)", S(7, 7, 7, 7, 7, 6, 8), "Low (provisional)"),
    ("Settings (in-app page + Settings window)", S(5, 7, 6, 5, 5, 6, 6), "Low (provisional)"),
    ("Player", S(7, 8, 7, 6, 7, 5, 7), "Low (provisional)"),
  ],
}

if __name__ == "__main__":
    for platform, rows in SCREENS.items():
        print(f"\n## {platform}\n")
        print("| Screen | IA | Visual | Task | Platform | Consistency | A11y | States | **Total** | UX | UI | Band | Confidence |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|")
        totals = []
        for name, s, conf in rows:
            t = total(s); totals.append(t)
            print(f"| {name} | {s['ia']} | {s['vis']} | {s['task']} | {s['plat']} | {s['cons']} | {s['a11y']} | {s['perf']} | **{t}** | {ux(s)} | {ui(s)} | {band(t)} | {conf} |")
        print(f"\nPlatform mean: **{round(sum(totals) / len(totals))}** ({len(totals)} screens)")
