<#
  Confirms the live GitHub Pages site actually serves the bundle you just built.

  Usage:
    .\scripts\verify_deploy.ps1
    .\scripts\verify_deploy.ps1 -Marker "Display Settings","Extra Large"
    .\scripts\verify_deploy.ps1 -Wait 300      # keep polling for up to 5 minutes

  Exit code 0 = live bundle contains every marker, 1 = it does not.
#>
param(
  [string[]] $Marker = @(),
  [string]   $Url    = 'https://kjcj.github.io/na-you-get/main.dart.js',
  [int]      $Wait   = 0
)

$ErrorActionPreference = 'Stop'

$deadline = (Get-Date).AddSeconds($Wait)
$attempt  = 0
$result   = $null

while ($true) {
  $attempt++
  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  try {
    $res = Invoke-WebRequest -Uri "$Url`?x=$stamp" -UseBasicParsing `
            -Headers @{ 'Cache-Control' = 'no-cache' } -TimeoutSec 90
    $bytes   = $res.RawContentLength
    $content = $res.Content
    $md5     = [System.BitConverter]::ToString(
                 [System.Security.Cryptography.MD5]::Create().ComputeHash(
                   [System.Text.Encoding]::UTF8.GetBytes($content)
                 )).Replace('-', '').ToLower().Substring(0, 12)
    $lastMod = $res.Headers['Last-Modified']

    Write-Host ("  attempt {0,-2} {1,6:N0} KB  md5 {2}  {3}" -f `
      $attempt, ($bytes / 1KB), $md5, $lastMod)

    $missing = @($Marker | Where-Object { $content -notlike "*$_*" })
    if ($missing.Count -eq 0) {
      $result = 'ok'
      break
    }
    foreach ($m in $missing) {
      Write-Host "    missing: $m" -ForegroundColor Yellow
    }
    $result = 'missing'
  }
  catch {
    Write-Host "  attempt $attempt  fetch failed: $($_.Exception.Message)" -ForegroundColor Yellow
    $result = 'error'
  }

  if ((Get-Date) -ge $deadline) { break }
  Start-Sleep -Seconds 20
}

Write-Host ''
if ($result -eq 'ok') {
  if ($Marker.Count -gt 0) {
    Write-Host "  LIVE - all $($Marker.Count) marker(s) present" -ForegroundColor Green
  } else {
    Write-Host "  Reachable. Pass -Marker to assert the new build is live." -ForegroundColor Green
  }
  exit 0
}

Write-Host "  NOT LIVE - the site is still serving an older bundle." -ForegroundColor Red
Write-Host "  Fix: git commit --allow-empty -m 'ci: retrigger Pages deploy' ; git push"
exit 1
