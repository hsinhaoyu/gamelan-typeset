# 0013 The repository is called notasi

Status: accepted (2026-11-20)

Context: ADR 0010 renamed the package to `notasi` but left the GitHub repository as `gamelan-typeset`. The two names then disagreed, and "gamelan" in the repository name claimed more than the package does, which was the reason for 0010.

Decision: The GitHub repository is `hsinhaoyu/notasi`, matching the package name. The rest of 0010 still applies; only its statement that the repository name is unchanged is replaced.

Consequences: GitHub redirects the old `gamelan-typeset` URLs, so existing clones and links keep working until a new repository takes that name. Local clones should point `origin` at the new URL. No file in the repository referred to the old name. The `.gml` extension is unchanged.

Supersedes: 0010 (only its statement that the repository name is unchanged)
