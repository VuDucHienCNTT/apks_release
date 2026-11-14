<#
.SYNOPSIS
  Phát hành bản mới của một app lên apks_release để các box tự cập nhật (khỏi cắm USB).

.DESCRIPTION
  1. Build bản release của app (bỏ qua với -NoBuild).
  2. Đọc package / versionCode / versionName ngay trong APK, kiểm tra:
       - đúng package của app,
       - ký đúng khóa dùng chung (khác khóa thì box sẽ không cài đè được -> dừng),
       - versionCode lớn hơn bản đang phát hành.
  3. Tạo GitHub Release (tag <app>-v<version>) và upload APK.
  4. Ghi <app>/version.json (apkUrl, sha256, sizeBytes, notes), commit và push.
     Từ lúc này các box mở app sẽ thấy bản mới.

  Cần: GitHub CLI (winget install GitHub.cli, rồi gh auth login một lần).

.EXAMPLE
  .\release.ps1 novatv -Notes "Thêm tự cập nhật"
  .\release.ps1 thtv -NoBuild
  .\release.ps1 -List
#>
param(
    [Parameter(Position = 0)] [string] $App,
    [string] $Notes = "",
    [switch] $NoBuild,
    [switch] $List,
    # Chỉ kiểm tra và in ra version.json, không upload / commit / push gì cả.
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"
$Repo = "VuDucHienCNTT/apks_release"
$Here = $PSScriptRoot
$Projects = Split-Path $Here -Parent

# Chứng chỉ ký mà mọi bản đã cài trên box đang dùng (~/.android/hien-release.keystore).
$ExpectedSigner = "80654e1ac28c7a9af7ecebcb2895ad9d712857ce3ce0735ed93d2666ab84baa2"

# slug -> project, package. APK lấy là file .apk mới nhất (không unsigned) trong app/build/outputs/apk/release.
$Apps = [ordered]@{
    "novatv"      = @{ Project = "NovaTV";      Package = "com.novatv.launcher";         Name = "Nova TV" }
    "thtv"        = @{ Project = "VietTV";      Package = "com.example.viettv";          Name = "THTV" }
    "docbao"      = @{ Project = "DocBao";      Package = "com.example.vnexpresscom";    Name = "Doc Bao" }
    "bongdatv"    = @{ Project = "BongDaTV";    Package = "com.example.bongdacom.multi"; Name = "Bong da TV" }
    "youtubelite" = @{ Project = "YoutubeLite"; Package = "com.example.youtubelite";     Name = "YouTube Lite" }
    "castly"      = @{ Project = "Castly";      Package = "dev.castly.receiver";         Name = "Castly" }
}

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

function Read-VersionJson($slug) {
    $path = Join-Path $Here "$slug\version.json"
    if (Test-Path $path) { return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

if ($List -or -not $App) {
    Write-Host "Ban dang phat hanh:"
    foreach ($slug in $Apps.Keys) {
        $v = Read-VersionJson $slug
        if ($v) { Write-Host ("  {0,-12} {1} (versionCode {2})" -f $slug, $v.versionName, $v.versionCode) }
        else { Write-Host ("  {0,-12} (chua phat hanh)" -f $slug) }
    }
    if (-not $App) { Write-Host "`nDung: .\release.ps1 <app> [-Notes ""...""] [-NoBuild] [-DryRun]" }
    exit 0
}

$cfg = $Apps[$App]
if (-not $cfg) { Fail "Khong biet app '$App'. Chon mot trong: $($Apps.Keys -join ', ')" }
$projectDir = Join-Path $Projects $cfg.Project

# --- Công cụ Android SDK ---
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$buildTools = Get-ChildItem (Join-Path $sdk "build-tools") -Directory | Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } | Select-Object -Last 1
if (-not $buildTools) { Fail "Khong tim thay Android SDK build-tools trong $sdk" }
$aapt2 = Join-Path $buildTools.FullName "aapt2.exe"
$apksigner = Join-Path $buildTools.FullName "apksigner.bat"

if (-not $DryRun) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Fail "Chua co GitHub CLI. Cai: winget install GitHub.cli  roi chay: gh auth login"
    }
}

# --- 1. Build ---
if (-not $NoBuild) {
    Write-Host "== Build $($cfg.Project) (assembleRelease)..." -ForegroundColor Cyan
    Push-Location $projectDir
    try {
        & .\gradlew.bat assembleRelease
        if ($LASTEXITCODE -ne 0) { Fail "Build that bai" }
    } finally { Pop-Location }
}

$apk = Get-ChildItem (Join-Path $projectDir "app\build\outputs\apk\release") -Filter *.apk -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch "unsigned" } | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $apk) { Fail "Khong thay APK release da ky trong $projectDir\app\build\outputs\apk\release" }
Write-Host "APK: $($apk.FullName)"

# --- 2. Kiểm tra APK ---
$badging = (& $aapt2 dump badging $apk.FullName | Select-Object -First 1)
if ($badging -notmatch "name='([^']+)' versionCode='(\d+)' versionName='([^']*)'") { Fail "Khong doc duoc thong tin APK" }
$package = $Matches[1]; $versionCode = [long]$Matches[2]; $versionName = $Matches[3]
if ($package -ne $cfg.Package) { Fail "APK la package $package, khong phai $($cfg.Package)" }

$signer = (& $apksigner verify --print-certs $apk.FullName | Select-String "certificate SHA-256 digest" | Select-Object -First 1)
if (-not $signer) { Fail "APK chua ky hoac chu ky hong" }
$signer = ($signer.ToString() -split ":\s*")[-1].Trim().ToLower()
if ($signer -ne $ExpectedSigner) {
    Fail "APK ky bang khoa khac ($signer). Box se KHONG cai de duoc. Kiem tra RELEASE_* trong ~/.gradle/gradle.properties."
}

$current = Read-VersionJson $App
if ($current -and $versionCode -le [long]$current.versionCode) {
    Fail "versionCode $versionCode khong lon hon ban dang phat hanh ($($current.versionCode)). Tang versionCode roi build lai."
}

$sha256 = (Get-FileHash $apk.FullName -Algorithm SHA256).Hash.ToLower()
$tag = "$App-v$versionName"
$assetName = "${App}_$versionName.apk"
$apkUrl = "https://github.com/$Repo/releases/download/$tag/$assetName"

$info = [ordered]@{
    versionCode = $versionCode
    versionName = $versionName
    apkUrl      = $apkUrl
    sha256      = $sha256
    sizeBytes   = $apk.Length
    notes       = $Notes
}
$json = $info | ConvertTo-Json
Write-Host "`n$App $versionName (versionCode $versionCode), $([math]::Round($apk.Length / 1MB, 2)) MB, ky dung khoa." -ForegroundColor Green
Write-Host $json

if ($DryRun) { Write-Host "`n(-DryRun: khong upload, khong push)"; exit 0 }

# --- 3. GitHub Release ---
Push-Location $Here
try {
    # Release cần repo có ít nhất một commit trên GitHub.
    git rev-parse --verify HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Repo apks_release chua co commit nao. Commit README/release.ps1 va push truoc." }
    git push origin HEAD
    if ($LASTEXITCODE -ne 0) { Fail "git push that bai" }

    $staged = Join-Path $env:TEMP $assetName
    Copy-Item $apk.FullName $staged -Force
    $title = "$($cfg.Name) $versionName"
    $releaseNotes = $Notes
    if (-not $releaseNotes) { $releaseNotes = "$($cfg.Name) $versionName" }
    Write-Host "== Tao release $tag..." -ForegroundColor Cyan
    gh release create $tag $staged --repo $Repo --title $title --notes $releaseNotes --target main
    if ($LASTEXITCODE -ne 0) { Fail "gh release create that bai" }
    Remove-Item $staged -Force

    # --- 4. version.json: chỉ ghi sau khi APK đã lên, để box không bao giờ thấy link hỏng ---
    New-Item -ItemType Directory -Force (Join-Path $Here $App) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Here "$App\version.json"), $json + "`n", (New-Object System.Text.UTF8Encoding $false))
    git add "$App/version.json"
    git commit -m "$App $versionName"
    git push origin HEAD
    if ($LASTEXITCODE -ne 0) { Fail "git push version.json that bai (APK da len release $tag; push lai bang tay)" }
    Write-Host "`nXong! Box se thay $($cfg.Name) $versionName o lan mo app ke tiep (CDN GitHub co the cham ~5 phut)." -ForegroundColor Green
} finally { Pop-Location }
