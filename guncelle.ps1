$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "1/4 Flutter web derleniyor..." -ForegroundColor Cyan
Push-Location mobil_uygulama
flutter pub get
flutter build web --release
$derleme = $LASTEXITCODE
Pop-Location
if ($derleme -ne 0) {
    Write-Host "Derleme basarisiz oldu, islem durduruldu." -ForegroundColor Red
    exit 1
}

Write-Host "2/4 backend\static klasoru guncelleniyor..." -ForegroundColor Cyan
if (Test-Path backend\static) { Remove-Item -Recurse -Force backend\static }
New-Item -ItemType Directory -Force backend\static | Out-Null
Copy-Item -Recurse -Force mobil_uygulama\build\web\* backend\static\

Write-Host "3/4 Degisiklikler Git'e ekleniyor..." -ForegroundColor Cyan
git add -A
git commit -m ("guncelleme " + (Get-Date -Format "yyyy-MM-dd HH:mm"))

Write-Host "4/4 GitHub'a gonderiliyor..." -ForegroundColor Cyan
git push

Write-Host ""
Write-Host "Bitti! Render birkac dakika icinde otomatik yayinlayacak." -ForegroundColor Green
Write-Host "Yayina girince sayfada Ctrl+F5 ile yenile."