**push_auto.ps1**

Usage:

- PowerShell (recommended):

```powershell
# push current branch (default 'main') using SSH if available, otherwise HTTPS
./scripts/push_auto.ps1

# force HTTPS push
./scripts/push_auto.ps1 -ForceHTTPS

# push another branch
./scripts/push_auto.ps1 -Branch feature/x
```

Notes:
- Requires `https-origin` remote to exist as a fallback. Use `git remote add https-origin <url>` if missing.
- Ensure `ssh-agent` is running and your key is added to the agent for SSH pushes.
