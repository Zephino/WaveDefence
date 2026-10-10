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
    $exportStarted = Get-Date
    $pckPath = Join-Path $ProjectRoot "docs\index.pck"
    $pckBefore = if (Test-Path $pckPath) { (Get-Item $pckPath).Length } else { -1 }
    & $godot --headless --path $ProjectRoot --export-release "Web" "docs/index.html"
    $godotExit = $LASTEXITCODE
    if (-not (Test-Path "docs\index.html")) {
        throw "Web export did not create docs/index.html (exit $godotExit)"
    }
    if ($godotExit -ne 0) {
        Write-Host "Godot reported exit $godotExit but web export output exists (continuing)." -ForegroundColor Yellow
    }
    # WinGet shim can return before the pack is fully flushed; wait for a fresh, stable .pck.
    $prevSize = -1
    $stable = 0
    for ($i = 0; $i -lt 240; $i++) {
        if (-not (Test-Path $pckPath)) {
            Start-Sleep -Milliseconds 250
            continue
        }
        $item = Get-Item $pckPath
        if ($item.LastWriteTime -lt $exportStarted -and $item.Length -eq $pckBefore) {
            Start-Sleep -Milliseconds 250
            continue
        }
        $size = $item.Length
        if ($size -gt 0 -and $size -eq $prevSize) {
            $stable++
            if ($stable -ge 3) { break }
        } else {
            $stable = 0
        }
        $prevSize = $size
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-Path $pckPath) -or $prevSize -le 0) {
        throw "Web export did not finish writing docs/index.pck"
    }
    # GitHub Pages: skip Jekyll so wasm/pck paths work.
    Set-Content -Path (Join-Path $ProjectRoot "docs\.nojekyll") -Value "" -NoNewline
    $ver = (Get-Content (Join-Path $ProjectRoot "VERSION") -Raw).Trim()
    $htmlPath = Join-Path $ProjectRoot "docs\index.html"
    $swPath = Join-Path $ProjectRoot "docs\index.service.worker.js"
    $manifestPath = Join-Path $ProjectRoot "docs\index.manifest.json"
    $mobileJsSrc = Join-Path $ProjectRoot "web\mobile_play.js"
    $mobileJsDst = Join-Path $ProjectRoot "docs\mobile_play.js"
    $manifestSrc = Join-Path $ProjectRoot "web\index.manifest.json"
    $icon192Src = Join-Path $ProjectRoot "web\index.192x192.png"
    $icon192Dst = Join-Path $ProjectRoot "docs\index.192x192.png"

    function Read-TextFileRetry([string]$Path, [int]$Tries = 20) {
        for ($i = 0; $i -lt $Tries; $i++) {
            try {
                return [System.IO.File]::ReadAllText($Path)
            } catch {
                Start-Sleep -Milliseconds 250
            }
        }
        return [System.IO.File]::ReadAllText($Path)
    }

    function Write-TextFileRetry([string]$Path, [string]$Content, [int]$Tries = 20) {
        for ($i = 0; $i -lt $Tries; $i++) {
            try {
                [System.IO.File]::WriteAllText($Path, $Content)
                return
            } catch {
                Start-Sleep -Milliseconds 250
            }
        }
        [System.IO.File]::WriteAllText($Path, $Content)
    }

    function Get-WebInject([string]$Version) {
        return @"
<script src="mobile_play.js?v=$Version"></script>
<script>
(function () {
	var VER = "$Version";
	var KEY = "wd_game_ver";
	try {
		var prev = localStorage.getItem(KEY);
		if (prev && prev !== VER && "serviceWorker" in navigator) {
			localStorage.setItem(KEY, VER);
			Promise.all([
				navigator.serviceWorker.getRegistrations().then(function (regs) {
					return Promise.all(regs.map(function (r) { return r.unregister(); }));
				}),
				caches.keys().then(function (keys) {
					return Promise.all(keys.map(function (k) { return caches.delete(k); }));
				})
			]).then(function () { location.reload(); });
			return;
		}
		localStorage.setItem(KEY, VER);
	} catch (e) {}
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
    }

    function Stamp-WebShell([string]$Version) {
        Copy-Item -Force $mobileJsSrc $mobileJsDst
        if (Test-Path $manifestSrc) {
            Copy-Item -Force $manifestSrc $manifestPath
        }
        if (Test-Path $icon192Src) {
            Copy-Item -Force $icon192Src $icon192Dst
        }

        $html = Read-TextFileRetry $htmlPath
        $html = [regex]::Replace($html, '(?s)<script src="mobile_play\.js\?v=[^"]*"></script>\s*', "")
        $html = [regex]::Replace($html, '(?s)<script>\s*\(function \(\) \{\s*var VER = "[^"]*";.*?</script>\s*', "")
        $inject = Get-WebInject $Version
        $headIdx = $html.IndexOf("</head>")
        if ($headIdx -lt 0) { throw "docs/index.html missing </head>" }
        $html = $html.Insert($headIdx, $inject)
        Write-TextFileRetry $htmlPath $html

        if (Test-Path $swPath) {
            $sw = Read-TextFileRetry $swPath
            $swTagged = "const CACHE_VERSION = '" + $Version + "';"
            $swNew = [regex]::Replace($sw, "const CACHE_VERSION = '[^']*';", $swTagged)
            if ($swNew -notmatch [regex]::Escape($swTagged)) {
                throw "Failed to stamp CACHE_VERSION=$Version into service worker"
            }
            $swNew = $swNew -replace "event.waitUntil\(caches.open\(CACHE_NAME\).then\(\(cache\) => cache.addAll\(CACHED_FILES\)\)\);", "event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CACHED_FILES)).then(() => self.skipWaiting()));"
            $navOld = @'
				if (isNavigate) {
					// Check if we have full cache during HTML page request.
					/** @type {Response[]} */
					const fullCache = await Promise.all(FULL_CACHE.map((name) => cache.match(name)));
					const missing = fullCache.some((v) => v === undefined);
					if (missing) {
						try {
							// Try network if some cached file is missing (so we can display offline page in case).
							const response = await fetchAndCache(event, cache, isCacheable);
							return response;
						} catch (e) {
							// And return the hopefully always cached offline page in case of network failure.
							console.error('Network error: ', e); // eslint-disable-line no-console
							return caches.match(OFFLINE_URL);
						}
					}
				}
'@
            $navNew = @'
				if (isNavigate) {
					// NETWORK_FIRST_HTML: always try the network so updates reach installed PWAs.
					try {
						const response = await fetchAndCache(event, cache, true);
						return response;
					} catch (e) {
						console.error('Network error: ', e); // eslint-disable-line no-console
						const cachedNav = await cache.match(event.request);
						if (cachedNav) { return cachedNav; }
						return caches.match(OFFLINE_URL);
					}
				}
'@
            if ($swNew.Contains("if (isNavigate)")) {
                $swNew = $swNew.Replace($navOld, $navNew)
            }
            Write-TextFileRetry $swPath $swNew
        }
    }

    function Test-WebStamp([string]$Version) {
        $htmlOnDisk = Read-TextFileRetry $htmlPath
        if ($htmlOnDisk -notmatch [regex]::Escape('var VER = "' + $Version + '"')) { return $false }
        if ($htmlOnDisk -notmatch 'mobile_play\.js\?v=') { return $false }
        if (Test-Path $swPath) {
            $swOnDisk = Read-TextFileRetry $swPath
            if ($swOnDisk -notmatch [regex]::Escape("const CACHE_VERSION = '" + $Version + "';")) { return $false }
            if ($swOnDisk -notmatch "NETWORK_FIRST_HTML") { return $false }
        }
        if (Test-Path $manifestPath) {
            $man = Read-TextFileRetry $manifestPath
            if ($man -notmatch '"short_name"' -or $man -notmatch '192x192') { return $false }
        } elseif (Test-Path $manifestSrc) {
            return $false
        }
        if ((Test-Path $icon192Src) -and -not (Test-Path $icon192Dst)) { return $false }
        return $true
    }

    # Godot may keep rewriting HTML/SW/manifest after the pack settles — stamp, wait, re-stamp.
    $stampOk = $false
    for ($attempt = 0; $attempt -lt 24; $attempt++) {
        Stamp-WebShell -Version $ver
        Start-Sleep -Milliseconds 400
        if (Test-WebStamp -Version $ver) {
            Start-Sleep -Milliseconds 800
            if (Test-WebStamp -Version $ver) {
                $stampOk = $true
                break
            }
        }
    }
    # Final overwrite after Godot is quiet.
    Stamp-WebShell -Version $ver
    Start-Sleep -Milliseconds 500
    Stamp-WebShell -Version $ver
    if (-not (Test-WebStamp -Version $ver)) {
        throw "Failed to keep VER=$ver / mobile_play / PWA manifest in docs (Godot overwrite race)"
    }
    Write-Host "OK: docs/ (GitHub Pages, cache-bust v$ver + mobile helper + SW + manifest)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. pc/ = Windows, phone/android/ = Android, phone/ios/ = iOS, docs/ = Web." -ForegroundColor Green
