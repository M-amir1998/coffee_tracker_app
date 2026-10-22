<#
.SYNOPSIS
    Prepares a Windows machine for Coffee Tracker development.

.DESCRIPTION
    1. Checks Git, Flutter, Node.js and Docker (downloads Flutter on request).
    2. Fetches the Dart and Flutter packages.
    3. Starts a local Supabase stack in Docker. On the first start the
       migrations and the demo data in supabase/seed.sql are applied.
    4. Writes config/development.json with the local API URL and the local
       publishable key.

    The script only talks to local containers. It never connects to a remote
    Supabase project and never writes secret keys to disk.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\setup.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\setup.ps1 -InstallFlutter -AddFlutterToPath
#>
[CmdletBinding()]
param(
    # Download Flutter into -FlutterDir when it cannot be found.
    [switch]$InstallFlutter,
    # Add Flutter's bin folder to your user PATH (takes effect in new terminals).
    [switch]$AddFlutterToPath,
    # Turn off the Windows and Linux desktop targets in your Flutter config so
    # packages can be fetched without Windows Developer Mode.
    [switch]$WithoutDeveloperMode,
    # Start every Supabase service, including Studio (needs more memory).
    [switch]$FullStack,
    # Check the tools and fetch packages only; do not start containers.
    [switch]$SkipSupabase,
    # Regenerate config/development.json even if it exists.
    [switch]$Force,
    [string]$FlutterDir = (Join-Path $env:USERPROFILE 'develop\flutter'),
    [string]$FlutterVersion = '3.47.7',
    [string]$SupabaseCliVersion = '2.121.0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-Step([string]$Message) { Write-Host ''; Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "    ok  $Message" -ForegroundColor Green }
function Write-Note([string]$Message) { Write-Host "    !   $Message" -ForegroundColor Yellow }

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @())
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Command $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Supabase([string[]]$Arguments) {
    Invoke-Checked 'npx.cmd' (@('--yes', "supabase@$SupabaseCliVersion") + $Arguments)
}

# Extracts the JSON object from command output that may contain other lines.
function ConvertFrom-JsonOutput([object[]]$Lines) {
    $text = ($Lines | ForEach-Object { "$_" }) -join "`n"
    $start = $text.IndexOf('{')
    $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -lt $start) { throw "Expected JSON output but got:`n$text" }
    return $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
}

function Get-Field($Object, [string]$Name) {
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return [string]$property.Value }
    return ''
}

function Test-DeveloperMode {
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        $value = Get-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -ErrorAction Stop
        return $value.AllowDevelopmentWithoutDevLicense -eq 1
    } catch {
        return $false
    }
}

function Test-DockerRunning {
    # docker writes to stderr when the engine is down; do not let that throw.
    $ErrorActionPreference = 'Continue'
    & docker info *> $null
    return $LASTEXITCODE -eq 0
}

function Install-Flutter {
    if (Test-Path $FlutterDir) {
        throw "$FlutterDir exists but does not contain Flutter. Remove it or pass another -FlutterDir."
    }
    $drive = Get-PSDrive -Name (Split-Path -Qualifier $FlutterDir).TrimEnd(':')
    if ($drive.Free -lt 4GB) {
        throw ('Installing Flutter needs about 4 GB of free space on {0}: ({1:N1} GB free).' -f $drive.Name, ($drive.Free / 1GB))
    }

    $ProgressPreference = 'SilentlyContinue'  # the progress bar makes downloads very slow in Windows PowerShell
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $index = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $release = $index.releases | Where-Object { $_.version -eq $FlutterVersion -and $_.channel -eq 'stable' } |
        Select-Object -First 1
    if (-not $release) { throw "Flutter $FlutterVersion is not listed as a stable release." }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) 'coffee-tracker-flutter'
    if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
    New-Item -ItemType Directory -Force (Join-Path $temp 'extract') | Out-Null
    $zip = Join-Path $temp 'flutter.zip'
    $url = "$($index.base_url)/$($release.archive)"
    Write-Host "    downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

    $hash = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash
    if ($hash -ne $release.sha256) { throw "Checksum mismatch for $url. The download was not used." }
    Write-Ok 'download verified (SHA-256)'

    Write-Host '    extracting...'
    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        Invoke-Checked 'tar.exe' @('-xf', $zip, '-C', (Join-Path $temp 'extract'))
    } else {
        Expand-Archive -Path $zip -DestinationPath (Join-Path $temp 'extract')
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $FlutterDir) | Out-Null
    Move-Item (Join-Path $temp 'extract\flutter') $FlutterDir
    Remove-Item -Recurse -Force $temp
    return (Join-Path $FlutterDir 'bin')
}

function Add-ToUserPath([string]$Folder) {
    # Edit the registry value directly so entries such as %USERPROFILE% stay unexpanded.
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $current = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($current -split ';' | Where-Object { $_ })
        if ($entries -contains $Folder) {
            Write-Ok 'Flutter is already on your user PATH'
            return
        }
        $key.SetValue('Path', (($entries + $Folder) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        $key.Close()
    }
    # Setting any user variable through .NET notifies running programs of the change.
    [Environment]::SetEnvironmentVariable('COFFEE_TRACKER_SETUP', '1', 'User')
    [Environment]::SetEnvironmentVariable('COFFEE_TRACKER_SETUP', $null, 'User')
    Write-Ok "added $Folder to your user PATH (open a new terminal to use it)"
}

# -----------------------------------------------------------------------------

Write-Step 'Git'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is required: https://git-scm.com/download/win'
}
Write-Ok (& git --version)

Write-Step 'Flutter'
$flutterBin = $null
$onPath = Get-Command flutter -ErrorAction SilentlyContinue
if ($onPath) {
    $flutterBin = Split-Path -Parent $onPath.Source
} elseif (Test-Path (Join-Path $FlutterDir 'bin\flutter.bat')) {
    $flutterBin = Join-Path $FlutterDir 'bin'
} elseif ($InstallFlutter) {
    $flutterBin = Install-Flutter
} else {
    throw ("Flutter was not found on PATH or in $FlutterDir.`n" +
        "    Run this script again with -InstallFlutter, or install Flutter $FlutterVersion yourself:`n" +
        '    https://docs.flutter.dev/get-started/install/windows')
}
$env:Path = "$flutterBin;$env:Path"
if ($AddFlutterToPath) { Add-ToUserPath $flutterBin }

Invoke-Checked 'flutter' @('--version')
$flutterInfo = ConvertFrom-JsonOutput (& flutter --version --machine)
if ($flutterInfo.frameworkVersion -eq $FlutterVersion) {
    Write-Ok "Flutter $FlutterVersion in $flutterBin"
} else {
    Write-Note "Flutter $($flutterInfo.frameworkVersion) found. The project and CI use $FlutterVersion."
}

Write-Step 'Windows Developer Mode'
if (Test-DeveloperMode) {
    Write-Ok 'enabled (Flutter can create the symlinks that plugins need)'
} elseif ($WithoutDeveloperMode) {
    Invoke-Checked 'flutter' @('config', '--no-enable-windows-desktop', '--no-enable-linux-desktop')
    Write-Note 'Desktop targets are now off in your Flutter config. Web and Android development still work.'
    Write-Note 'For Windows builds: enable Developer Mode, then run  flutter config --enable-windows-desktop'
} else {
    Write-Note 'off. If fetching packages fails, either enable it (start ms-settings:developers)'
    Write-Note 'or run this script with -WithoutDeveloperMode to work on web and Android only.'
}

Write-Step 'Packages'
& flutter pub get
if ($LASTEXITCODE -ne 0) {
    if (-not (Test-DeveloperMode)) {
        throw ("flutter pub get failed. Plugins need symlinks, which Windows only allows in Developer Mode.`n" +
            '    Enable it (start ms-settings:developers) or run this script with -WithoutDeveloperMode.')
    }
    throw 'flutter pub get failed (see the output above).'
}
Write-Ok 'packages fetched'

if ($SkipSupabase) {
    Write-Step 'Done (Supabase skipped)'
    exit 0
}

Write-Step 'Node.js (runs the Supabase CLI through npx)'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Node.js 20 or newer is required: https://nodejs.org/'
}
Write-Ok "Node $(& node --version)"

Write-Step 'Docker'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop is required for the local stack: https://docs.docker.com/desktop/setup/install/windows-install/'
}
if (-not (Test-DockerRunning)) {
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $desktop) {
        Write-Host '    starting Docker Desktop...'
        Start-Process $desktop
        $deadline = (Get-Date).AddMinutes(3)
        while (-not (Test-DockerRunning) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
    }
    if (-not (Test-DockerRunning)) { throw 'Docker is installed but not running. Start Docker Desktop and try again.' }
}
Write-Ok 'Docker engine is running'

Write-Step 'Local Supabase stack'
$startArguments = @('start')
if (-not $FullStack) {
    # Only what the app and the tests need; Studio and analytics use a lot of memory.
    $startArguments += @('-x', 'studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta')
}
Invoke-Supabase $startArguments

$statusOutput = & npx.cmd --yes "supabase@$SupabaseCliVersion" status -o json
if ($LASTEXITCODE -ne 0) { throw 'supabase status failed (see the output above).' }
$status = ConvertFrom-JsonOutput $statusOutput
$apiUrl = Get-Field $status 'API_URL'
$publishableKey = Get-Field $status 'PUBLISHABLE_KEY'
if (-not $publishableKey) { $publishableKey = Get-Field $status 'ANON_KEY' }
$mailUrl = Get-Field $status 'MAILPIT_URL'
if (-not $mailUrl) { $mailUrl = Get-Field $status 'INBUCKET_URL' }
if (-not $apiUrl -or -not $publishableKey) { throw 'Could not read the API URL and publishable key from supabase status.' }
Write-Ok "API at $apiUrl"

Write-Step 'App configuration'
$configPath = Join-Path $root 'config\development.json'
if ((Test-Path $configPath) -and -not $Force) {
    Write-Ok 'config/development.json already exists (use -Force to regenerate it)'
} else {
    $config = [ordered]@{
        SUPABASE_URL             = $apiUrl
        SUPABASE_PUBLISHABLE_KEY = $publishableKey
        APP_ENV                  = 'development'
        WEB_REDIRECT_URL         = ''
        PUBLIC_APP_URL           = 'http://localhost:3000'
    }
    # UTF-8 without a byte order mark, which --dart-define-from-file expects.
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json) + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok 'wrote config/development.json (local URL and publishable key only; ignored by Git)'
}

Write-Step 'Ready'
Write-Host '    Run the web app:   flutter run -d chrome --web-port 3000 --dart-define-from-file=config/development.json'
Write-Host '    Demo accounts:     alice@example.com, bob@example.com, charlie@example.com, diana@example.com,'
Write-Host '                       emma@example.com - password coffee-demo-1 (local stack only)'
if ($mailUrl) { Write-Host "    Emails (sign-up):  $mailUrl" }
Write-Host "    Database tests:    npx supabase@$SupabaseCliVersion test db"
Write-Host "    Reset demo data:   npx supabase@$SupabaseCliVersion db reset"
Write-Host "    Stop the stack:    npx supabase@$SupabaseCliVersion stop"
