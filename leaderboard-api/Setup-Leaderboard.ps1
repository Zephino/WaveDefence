#Requires -Version 5.1
<#
.SYNOPSIS
  Windows helper app for one-time Wave Defence leaderboard Cloudflare setup.
  Double-click Setup-Leaderboard.bat - do not paste secrets into chat.
#>
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir
$WranglerToml = Join-Path $ScriptDir "wrangler.toml"
$OnlineConfig = Join-Path (Split-Path $ScriptDir -Parent) "scripts\online_config.gd"
$OnboardingUrl = "https://dash.cloudflare.com/?to=/:account/workers/onboarding"

function Write-Log {
    param([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::Gainsboro)
    if ($LogBox.IsDisposed) { return }
    $LogBox.SelectionStart = $LogBox.TextLength
    $LogBox.SelectionLength = 0
    $LogBox.SelectionColor = $Color
    $LogBox.AppendText($Text + [Environment]::NewLine)
    $LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-Step {
    param(
        [string]$Title,
        [scriptblock]$Action
    )
    Write-Log ""
    Write-Log ("==> " + $Title) ([System.Drawing.Color]::LightSkyBlue)
    & $Action
}

function Get-NpmPath {
    $cmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Npm {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$NpmArgs)
    $npm = Get-NpmPath
    if (-not $npm) { throw "npm not found. Install Node.js LTS from https://nodejs.org/ then restart this app." }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $npm
    $psi.Arguments = ($NpmArgs -join " ")
    $psi.WorkingDirectory = $ScriptDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # Let wrangler prompts default usefully when possible.
    $psi.EnvironmentVariables["CI"] = "true"
    $psi.EnvironmentVariables["WRANGLER_SEND_METRICS"] = "false"
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $combined = ($stdout + "`n" + $stderr)
    if ($stdout) { Write-Log $stdout.TrimEnd() }
    if ($stderr) { Write-Log $stderr.TrimEnd() ([System.Drawing.Color]::Khaki) }
    if ($p.ExitCode -ne 0) {
        if ($combined -match "workers\.dev subdomain") {
            try { Start-Process $OnboardingUrl } catch {}
            throw "Cloudflare needs a free workers.dev name first. Finish the page that opened (pick any subdomain name), then click '5. Retry deploy only'."
        }
        throw ("Command failed (exit " + $p.ExitCode + "): npm " + ($NpmArgs -join " "))
    }
    return $combined
}

function Invoke-WranglerCapture {
    param([string[]]$WArgs)
    $all = @("exec", "--yes", "--", "wrangler") + $WArgs
    return Invoke-Npm @all
}

function Set-KvIdInToml {
    param([string]$KvId)
    $text = Get-Content -Raw $WranglerToml
    $block = @"

[[kv_namespaces]]
binding = "LEADERBOARD_KV"
id = "$KvId"
"@
    if ($text -match '(?m)^\[\[kv_namespaces\]\][\s\S]*?^id = "[^"]*"') {
        $text = [regex]::Replace($text, '(?m)^id = "[^"]*"', ('id = "' + $KvId + '"'))
        $text = $text -replace '(?m)^# \[\[kv_namespaces\]\]', '[[kv_namespaces]]'
        $text = $text -replace '(?m)^# binding = "LEADERBOARD_KV"', 'binding = "LEADERBOARD_KV"'
        $text = $text -replace '(?m)^# id = "YOUR_KV_NAMESPACE_ID"', ('id = "' + $KvId + '"')
    }
    elseif ($text -match '(?ms)^# \[\[kv_namespaces\]\].*?^# id = "YOUR_KV_NAMESPACE_ID"\r?\n') {
        $text = [regex]::Replace(
            $text,
            '(?ms)^# \[\[kv_namespaces\]\].*?^# id = "YOUR_KV_NAMESPACE_ID"\r?\n',
            ($block.TrimStart() + "`r`n")
        )
    }
    else {
        $text = $text.TrimEnd() + "`r`n" + $block + "`r`n"
    }
    if ($text -notmatch '(?m)^workers_dev\s*=') {
        $text = $text -replace '(?m)^(name = "[^"]+"\r?\n)', ('$1workers_dev = true' + "`r`n")
    }
    [System.IO.File]::WriteAllText($WranglerToml, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Ensure-WorkersDevFlag {
    $text = Get-Content -Raw $WranglerToml
    if ($text -notmatch '(?m)^workers_dev\s*=') {
        $text = $text -replace '(?m)^(name = "[^"]+"\r?\n)', ('$1workers_dev = true' + "`r`n")
        [System.IO.File]::WriteAllText($WranglerToml, $text, (New-Object System.Text.UTF8Encoding $false))
        Write-Log "Enabled workers_dev = true in wrangler.toml"
    }
}

function Set-ApiBaseUrl {
    param([string]$Url)
    if (-not (Test-Path $OnlineConfig)) { throw ("Missing " + $OnlineConfig) }
    $text = Get-Content -Raw $OnlineConfig
    if ($text -notmatch 'const API_BASE_URL :=') {
        throw "API_BASE_URL not found in online_config.gd"
    }
    $updated = [regex]::Replace($text, 'const API_BASE_URL := "[^"]*"', ('const API_BASE_URL := "' + $Url + '"'))
    [System.IO.File]::WriteAllText($OnlineConfig, $updated, (New-Object System.Text.UTF8Encoding $false))
}

function Complete-Deploy {
    Ensure-WorkersDevFlag
    $out = Invoke-WranglerCapture @("deploy")
    $url = $null
    if ($out -match '(https://[a-zA-Z0-9._-]+\.workers\.dev)') { $url = $Matches[1].TrimEnd("/") }
    if (-not $url) {
        # Common default name after subdomain is registered.
        $guess = "https://wave-defence-leaderboard.workers.dev"
        Write-Log ("Could not parse URL from output. Trying guess: " + $guess) ([System.Drawing.Color]::Khaki)
        $url = $guess
    }
    Set-ApiBaseUrl -Url $url
    Write-Log ""
    Write-Log "SUCCESS" ([System.Drawing.Color]::LightGreen)
    Write-Log ("Worker URL: " + $url) ([System.Drawing.Color]::LightGreen)
    Write-Log "Updated scripts/online_config.gd API_BASE_URL" ([System.Drawing.Color]::LightGreen)
    Write-Log ("Open test: " + $url + "/leaderboard")
    Write-Log "Next: tell Cursor to rebuild/export and push so players get uploads."
    $status.Text = "Done - rebuild + push the game next."
    $status.ForeColor = [System.Drawing.Color]::LightGreen
    try { Start-Process ($url + "/leaderboard") } catch {}
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Wave Defence - Leaderboard Setup"
$form.Size = New-Object System.Drawing.Size(740, 640)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(640, 520)
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 28, 34)
$form.ForeColor = [System.Drawing.Color]::WhiteSmoke
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Shared leaderboard setup (you only - once)"
$title.Location = New-Object System.Drawing.Point(20, 16)
$title.AutoSize = $true
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14)
$form.Controls.Add($title)

$help = New-Object System.Windows.Forms.Label
$help.Text = "Players never use this. It deploys the Cloudflare Worker that saves scores to the GitHub data branch."
$help.Location = New-Object System.Drawing.Point(22, 48)
$help.Size = New-Object System.Drawing.Size(680, 36)
$help.ForeColor = [System.Drawing.Color]::Silver
$form.Controls.Add($help)

$btnCf = New-Object System.Windows.Forms.Button
$btnCf.Text = "1. Open Cloudflare signup"
$btnCf.Location = New-Object System.Drawing.Point(22, 90)
$btnCf.Size = New-Object System.Drawing.Size(200, 34)
$btnCf.FlatStyle = "Flat"
$btnCf.BackColor = [System.Drawing.Color]::FromArgb(45, 55, 70)
$btnCf.ForeColor = [System.Drawing.Color]::White
$btnCf.Add_Click({ Start-Process "https://dash.cloudflare.com/sign-up" })
$form.Controls.Add($btnCf)

$btnPat = New-Object System.Windows.Forms.Button
$btnPat.Text = "2. Open GitHub token page"
$btnPat.Location = New-Object System.Drawing.Point(232, 90)
$btnPat.Size = New-Object System.Drawing.Size(200, 34)
$btnPat.FlatStyle = "Flat"
$btnPat.BackColor = [System.Drawing.Color]::FromArgb(45, 55, 70)
$btnPat.ForeColor = [System.Drawing.Color]::White
$btnPat.Add_Click({ Start-Process "https://github.com/settings/personal-access-tokens/new" })
$form.Controls.Add($btnPat)

$btnSub = New-Object System.Windows.Forms.Button
$btnSub.Text = "Open workers.dev setup"
$btnSub.Location = New-Object System.Drawing.Point(442, 90)
$btnSub.Size = New-Object System.Drawing.Size(200, 34)
$btnSub.FlatStyle = "Flat"
$btnSub.BackColor = [System.Drawing.Color]::FromArgb(70, 55, 40)
$btnSub.ForeColor = [System.Drawing.Color]::White
$btnSub.Add_Click({ Start-Process $OnboardingUrl })
$form.Controls.Add($btnSub)

$patHint = New-Object System.Windows.Forms.Label
$patHint.Text = "Token tip: Repository permissions -> Contents -> Read and write (WaveDefence only). Or classic token with 'repo'."
$patHint.Location = New-Object System.Drawing.Point(22, 130)
$patHint.Size = New-Object System.Drawing.Size(680, 32)
$patHint.ForeColor = [System.Drawing.Color]::DarkGray
$form.Controls.Add($patHint)

$tokenLabel = New-Object System.Windows.Forms.Label
$tokenLabel.Text = "3. Paste GitHub token (needed for first full run; not needed for Retry deploy):"
$tokenLabel.Location = New-Object System.Drawing.Point(22, 168)
$tokenLabel.AutoSize = $true
$form.Controls.Add($tokenLabel)

$tokenBox = New-Object System.Windows.Forms.TextBox
$tokenBox.Location = New-Object System.Drawing.Point(22, 196)
$tokenBox.Size = New-Object System.Drawing.Size(680, 28)
$tokenBox.UseSystemPasswordChar = $true
$tokenBox.BackColor = [System.Drawing.Color]::FromArgb(36, 42, 52)
$tokenBox.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($tokenBox)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "4. Run full setup"
$btnRun.Location = New-Object System.Drawing.Point(22, 238)
$btnRun.Size = New-Object System.Drawing.Size(200, 40)
$btnRun.FlatStyle = "Flat"
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(46, 120, 80)
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$form.Controls.Add($btnRun)

$btnRetry = New-Object System.Windows.Forms.Button
$btnRetry.Text = "5. Retry deploy only"
$btnRetry.Location = New-Object System.Drawing.Point(232, 238)
$btnRetry.Size = New-Object System.Drawing.Size(200, 40)
$btnRetry.FlatStyle = "Flat"
$btnRetry.BackColor = [System.Drawing.Color]::FromArgb(50, 90, 140)
$btnRetry.ForeColor = [System.Drawing.Color]::White
$btnRetry.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$form.Controls.Add($btnRetry)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Ready."
$status.Location = New-Object System.Drawing.Point(450, 246)
$status.Size = New-Object System.Drawing.Size(260, 28)
$status.ForeColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($status)

$LogBox = New-Object System.Windows.Forms.RichTextBox
$LogBox.Location = New-Object System.Drawing.Point(22, 294)
$LogBox.Size = New-Object System.Drawing.Size(680, 270)
$LogBox.Anchor = "Top,Bottom,Left,Right"
$LogBox.ReadOnly = $true
$LogBox.BackColor = [System.Drawing.Color]::FromArgb(16, 18, 22)
$LogBox.ForeColor = [System.Drawing.Color]::Gainsboro
$LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$LogBox.BorderStyle = "FixedSingle"
$form.Controls.Add($LogBox)

function Set-Busy([bool]$Busy) {
    $btnRun.Enabled = -not $Busy
    $btnRetry.Enabled = -not $Busy
    $btnCf.Enabled = -not $Busy
    $btnPat.Enabled = -not $Busy
    $btnSub.Enabled = -not $Busy
}

$btnRun.Add_Click({
    Set-Busy $true
    $token = $tokenBox.Text.Trim()
    try {
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw "Paste your GitHub token in the box first (step 3)."
        }
        $status.Text = "Working..."
        $status.ForeColor = [System.Drawing.Color]::Khaki
        Write-Log ("Setup folder: " + $ScriptDir)

        Invoke-Step "Check Node / npm" {
            $npm = Get-NpmPath
            if (-not $npm) { throw "npm not found. Install Node.js LTS, then close and reopen this app." }
            Write-Log ("npm: " + $npm)
        }

        Invoke-Step "npm install" {
            Invoke-Npm "install" | Out-Null
        }

        Invoke-Step "Cloudflare login (approve in the browser window)" {
            Write-Log "A browser window should open. Log into Cloudflare and Allow."
            Invoke-WranglerCapture @("login") | Out-Null
        }

        Invoke-Step "Create / bind KV namespace" {
            $toml = Get-Content -Raw $WranglerToml
            $kvPattern = '(?m)^id = "([a-fA-F0-9]{32})"'
            if (($toml -match '(?m)^\[\[kv_namespaces\]\]') -and ($toml -match $kvPattern)) {
                Write-Log ("KV already configured: " + $Matches[1])
            }
            else {
                $out = Invoke-WranglerCapture @("kv", "namespace", "create", "LEADERBOARD_KV")
                $kvId = $null
                if ($out -match '"id":\s*"([a-fA-F0-9]{32})"') { $kvId = $Matches[1] }
                elseif ($out -match '([a-fA-F0-9]{32})') { $kvId = $Matches[1] }
                if (-not $kvId) { throw "Could not read KV id from wrangler output. Check the log." }
                Set-KvIdInToml -KvId $kvId
                Write-Log ("Wrote KV id to wrangler.toml: " + $kvId) ([System.Drawing.Color]::LightGreen)
            }
        }

        Invoke-Step "Store GITHUB_TOKEN on Cloudflare (secret)" {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $npm = Get-NpmPath
            $psi.FileName = $npm
            $psi.Arguments = "exec --yes -- wrangler secret put GITHUB_TOKEN"
            $psi.WorkingDirectory = $ScriptDir
            $psi.UseShellExecute = $false
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.StandardInput.WriteLine($token)
            $p.StandardInput.Close()
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()
            if ($stdout) { Write-Log $stdout.TrimEnd() }
            if ($stderr) { Write-Log $stderr.TrimEnd() ([System.Drawing.Color]::Khaki) }
            if ($p.ExitCode -ne 0) { throw "Failed to set GITHUB_TOKEN secret." }
            Write-Log "Secret stored on Cloudflare." ([System.Drawing.Color]::LightGreen)
        }

        Invoke-Step "Deploy Worker" {
            Complete-Deploy
        }
    }
    catch {
        Write-Log ("ERROR: " + $_.Exception.Message) ([System.Drawing.Color]::Salmon)
        $status.Text = "Failed - see log."
        $status.ForeColor = [System.Drawing.Color]::Salmon
    }
    finally {
        $tokenBox.Clear()
        Set-Busy $false
    }
})

$btnRetry.Add_Click({
    Set-Busy $true
    try {
        $status.Text = "Retrying deploy..."
        $status.ForeColor = [System.Drawing.Color]::Khaki
        Write-Log ""
        Write-Log "Retry deploy only (after workers.dev subdomain is registered)." ([System.Drawing.Color]::LightSkyBlue)
        Invoke-Step "Deploy Worker" {
            Complete-Deploy
        }
    }
    catch {
        Write-Log ("ERROR: " + $_.Exception.Message) ([System.Drawing.Color]::Salmon)
        $status.Text = "Failed - see log."
        $status.ForeColor = [System.Drawing.Color]::Salmon
    }
    finally {
        Set-Busy $false
    }
})

Write-Log "This app is only for you (the developer), once."
Write-Log "Need: Node.js LTS, a Cloudflare account, and a GitHub token."
Write-Log "If deploy fails on workers.dev: open that setup page, pick a subdomain, then click button 5."

[void]$form.ShowDialog()
