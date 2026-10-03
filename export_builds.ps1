#Requires -Version 5.1
<#
.SYNOPSIS
  Rebuilds playable packages into pc/, phone/android/, phone/ios/, and docs/ (web) from one source.
#>
param(
    [switch]$PcOnly,
    [switch]$PhoneOnly,
    [switch]$AndroidOnly,
    [switch]$IosOnly,
    [switch]$WebOnly
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

function Find-Godot {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\godot.exe"
    if (Test-Path $wingetLinks) { return $wingetLinks }
    throw "Godot not found. Install Godot 4, then re-run."
}

$godot = Find-Godot
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "pc") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "phone\android") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "phone\ios") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "docs") | Out-Null

$jdk = Get-ChildItem "C:\Program Files\Microsoft" -Directory -Filter "jdk-17*" -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if ($jdk) {
    $env:JAVA_HOME = $jdk
    $env:Path = "$jdk\bin;" + $env:Path
}

$sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
if (Test-Path $sdkRoot) {
    $env:ANDROID_HOME = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot
}

$doPc = $true
$doAndroid = $true
$doIos = $true
$doWeb = $true
if ($PcOnly) {
    $doAndroid = $false
    $doIos = $false
    $doWeb = $false
}
if ($PhoneOnly) {
    $doPc = $false
    $doWeb = $false
}
if ($AndroidOnly) {
    $doPc = $false
    $doAndroid = $true
    $doIos = $false
    $doWeb = $false
}
if ($IosOnly) {
    $doPc = $false
    $doAndroid = $false
    $doIos = $true
    $doWeb = $false
}
if ($WebOnly) {
    $doPc = $false
    $doAndroid = $false
    $doIos = $false
    $doWeb = $true
}

if ($doPc) {
    Write-Host "==> Exporting PC -> pc/WaveDefence.exe" -ForegroundColor Cyan
    & $godot --headless --path $ProjectRoot --export-release "Windows Desktop" "pc/WaveDefence.exe"
    if ($LASTEXITCODE -ne 0) { throw "PC export failed (exit $LASTEXITCODE)" }
    if (-not (Test-Path "pc\WaveDefence.exe")) { throw "PC export did not create pc/WaveDefence.exe" }
    Write-Host "OK: pc/WaveDefence.exe" -ForegroundColor Green
}

if ($doAndroid) {
    Write-Host "==> Exporting Android -> phone/android/WaveDefence.apk" -ForegroundColor Cyan
    & $godot --headless --path $ProjectRoot --export-debug "Android" "phone/android/WaveDefence.apk"
    if ($LASTEXITCODE -ne 0) {
        throw "Android export failed (exit $LASTEXITCODE). Check Android SDK / Java in Godot Editor Settings."
    }
    if (-not (Test-Path "phone\android\WaveDefence.apk")) {
        throw "Android export did not create phone/android/WaveDefence.apk"
    }
    Write-Host "OK: phone/android/WaveDefence.apk" -ForegroundColor Green
}

if ($doIos) {
    $isMac = ($IsMacOS -eq $true) -or (Test-Path "/System/Library/CoreServices/SystemVersion.plist")
    if (-not $isMac) {
        Write-Host "==> Skipping iOS export on this OS (needs macOS + Xcode)." -ForegroundColor Yellow
        Write-Host "    Preset ready for: phone/ios/WaveDefence.ipa" -ForegroundColor Yellow
    } else {
        Write-Host "==> Exporting iOS -> phone/ios/WaveDefence.ipa" -ForegroundColor Cyan
        & $godot --headless --path $ProjectRoot --export-debug "iOS" "phone/ios/WaveDefence.ipa"
        if ($LASTEXITCODE -ne 0) {
            throw "iOS export failed (exit $LASTEXITCODE). Configure Apple signing in Godot Export settings."
        }
        if (-not (Test-Path "phone/ios/WaveDefence.ipa")) {
            throw "iOS export did not create phone/ios/WaveDefence.ipa"
        }
        Write-Host "OK: phone/ios/WaveDefence.ipa" -ForegroundColor Green
    }
}

if ($doWeb) {
    Write-Host "==> Exporting Web -> docs/index.html (GitHub Pages)" -ForegroundColor Cyan
    & $godot --headless --path $ProjectRoot --export-release "Web" "docs/index.html"
    if (-not (Test-Path "docs\index.html")) {
        throw "Web export did not create docs/index.html (exit $LASTEXITCODE)"
    }
    # GitHub Pages: skip Jekyll so wasm/pck paths work.
    Set-Content -Path (Join-Path $ProjectRoot "docs\.nojekyll") -Value "" -NoNewline
    $ver = (Get-Content (Join-Path $ProjectRoot "VERSION") -Raw).Trim()
    $htmlPath = Join-Path $ProjectRoot "docs\index.html"
    $html = Get-Content $htmlPath -Raw

    # Mobile helper + cache-bust (always rewrite so VERSION bumps replace old tags).
    $mobileJsSrc = Join-Path $ProjectRoot "web\mobile_play.js"
    $mobileJsDst = Join-Path $ProjectRoot "docs\mobile_play.js"
    Copy-Item -Force $mobileJsSrc $mobileJsDst
    $html = [regex]::Replace($html, '(?s)<script src="mobile_play\.js\?v=[^"]*"></script>', "")
    $html = [regex]::Replace($html, '(?s)<script>\s*\(function \(\) \{\s*var VER = "[^"]*";.*?</script>', "")
    $inject = @"
<script src="mobile_play.js?v=$ver"></script>
<script>
(function () {
	var VER = "$ver";
	function withVer(url) {
		if (!url || typeof url !== "string") return url;
		if (!/\.(pck|wasm|js)(\?|$)/i.test(url)) return url;
		return url + (url.indexOf("?") >= 0 ? "&" : "?") + "v=" + encodeURIComponent(VER);
	}
	var _fetch = window.fetch;
	window.fetch = function (input, init) {
		if (typeof input === "string") input = withVer(input);
		else if (input && typeof Request !== "undefined" && input instanceof Request) {
			input = new Request(withVer(input.url), input);
		}
		return _fetch.call(this, input, init);
	};
	var XO = XMLHttpRequest.prototype.open;
	XMLHttpRequest.prototype.open = function (method, url) {
		arguments[1] = withVer(url);
		return XO.apply(this, arguments);
	};
})();
</script>
"@
    # Use Insert — PowerShell -replace treats $ in the inject as backrefs and can drop the tag.
    $headIdx = $html.IndexOf("</head>")
    if ($headIdx -lt 0) { throw "docs/index.html missing </head>" }
    $html = $html.Insert($headIdx, $inject)
    [System.IO.File]::WriteAllText($htmlPath, $html)
    Write-Host "OK: docs/ (GitHub Pages, cache-bust v$ver + mobile helper)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. pc/ = Windows, phone/android/ = Android, phone/ios/ = iOS, docs/ = Web." -ForegroundColor Green
