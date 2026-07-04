param(
    [string]$Branch = "main",
    [switch]$ForceHTTPS
)

Write-Output "[push-auto] branch=$Branch, forceHTTPS=$ForceHTTPS"

# Detect ssh-agent identities
$usingSSH = $false
try {
    $sshAdd = "C:\\Windows\\System32\\OpenSSH\\ssh-add.exe"
    if (Test-Path $sshAdd) {
        $out = & $sshAdd -l 2>&1
        if ($LASTEXITCODE -eq 0 -and $out -notmatch "The agent has no identities") {
            $usingSSH = $true
        }
    }
} catch {
    $usingSSH = $false
}

if ($ForceHTTPS) { $usingSSH = $false }

if ($usingSSH) {
    Write-Output "[push-auto] Using SSH remote 'origin'"
    git push origin $Branch
} else {
    Write-Output "[push-auto] Using HTTPS backup remote 'https-origin'"
    git push https-origin $Branch
}
