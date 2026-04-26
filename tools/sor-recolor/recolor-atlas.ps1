<#
SOR atlas recolor pilot tool.
Usage:
  pwsh -File recolor-atlas.ps1 -Atlas <path-to-dds> -Preset resistance|synth [-DryRun]

Behavior:
  1. Backs up original to <atlas>.barbak (only if backup does not already exist).
  2. Decodes DDS -> PNG via ImageMagick.
  3. Applies SOR preset transform.
  4. Re-encodes DXT5 with full mipmap chain back to original DDS path.
  5. Writes a one-line log entry to SOR.sdd/_Source/texture_rebrand.log.

Reversal:
  Copy-Item <atlas>.barbak <atlas> -Force
#>
param(
	[Parameter(Mandatory=$true)][string]$Atlas,
	[Parameter(Mandatory=$true)][ValidateSet('resistance','synth')][string]$Preset,
	[switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$magickExe = 'C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe'
if (-not (Test-Path $magickExe)) { throw "ImageMagick not found at $magickExe" }
if (-not (Test-Path $Atlas))     { throw "Atlas not found: $Atlas" }

$atlasFull = (Resolve-Path $Atlas).Path
$backup    = "$atlasFull.barbak"
$workDir   = Join-Path $env:TEMP ("sor_recolor_" + [IO.Path]::GetFileNameWithoutExtension($atlasFull))
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -ItemType Directory -Path $workDir | Out-Null
$decoded = Join-Path $workDir 'in.png'
$out     = Join-Path $workDir 'out.png'

# 1. Backup
if (-not (Test-Path $backup)) {
	Copy-Item $atlasFull $backup
	Write-Host "[backup] $backup"
} else {
	Write-Host "[backup] already exists, leaving untouched: $backup"
}

# 2. Decode — always from the original BAR atlas (.barbak) so transforms are idempotent
$decodeSource = if (Test-Path $backup) { $backup } else { $atlasFull }
Write-Host "[decode-source] $decodeSource"
& $magickExe $decodeSource $decoded
if ($LASTEXITCODE -ne 0) { throw "DDS decode failed" }
$id = & $magickExe identify $decoded
Write-Host "[decode] $id"

# 3. Transform — CRITICAL: BAR color atlas alpha = team-color mask (non-flat, must be preserved).
#    All recolor operations are scoped to -channel RGB so alpha passes through unmodified.
#    -channel RGBA at end restores default scope before save.
$presetArgs = switch ($Preset) {
	'resistance' {
		# SOR Resistance color grade — duotone palette extracted from reference hero art
		# (4.heroscreen_resistence.png): warm dark brown-charcoal shadows -> worn tan highlights.
		# Result: carbon-fiber + olive plate carrier + leather utility belt feel.
		@(
			'-channel','RGB',
			'-modulate','100,0,100',                   # desaturate fully
			'+sigmoidal-contrast','3,50%',             # tactical matte contrast
			'+level-colors','#15100E,#A89084',         # gradient map: warm-black -> worn tan
			'+channel'
		)
	}
	'synth' {
		# SOR Synth color grade — anthracite shadows -> clean white highlights.
		# (Cyan glow lives in _other.dds emissive; do not add it here.)
		@(
			'-channel','RGB',
			'-modulate','100,0,100',
			'+sigmoidal-contrast','2,55%',
			'+level-colors','#0A0E14,#E8EDF5',
			'+channel'
		)
	}
}
& $magickExe $decoded @presetArgs $out
if ($LASTEXITCODE -ne 0) { throw "Transform failed" }

# Verify alpha is preserved (must match source within tolerance)
$alphaOrig = & $magickExe $decoded -channel A -separate -format "%[fx:mean*255]" info:
$alphaOut  = & $magickExe $out     -channel A -separate -format "%[fx:mean*255]" info:
Write-Host "[alpha-check] orig=$alphaOrig  out=$alphaOut  (must match)"
if ([math]::Abs([double]$alphaOrig - [double]$alphaOut) -gt 0.5) {
	throw "ALPHA CHANNEL DRIFTED - refusing to write DDS. orig=$alphaOrig out=$alphaOut"
}
$id2 = & $magickExe identify $out
Write-Host "[transform] $id2"

if ($DryRun) {
	Write-Host "[dry-run] not writing back. Preview at: $out"
	return
}

# 4. Re-encode DDS with mipmaps (DXT5 to preserve alpha if present)
& $magickExe $out -define dds:compression=dxt5 -define dds:mipmaps=12 $atlasFull
if ($LASTEXITCODE -ne 0) { throw "DDS re-encode failed" }
$id3 = & $magickExe identify $atlasFull
Write-Host "[encode] $id3"

# 5. Log
$logPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '_Source\texture_rebrand.log'
$logDir  = Split-Path -Parent $logPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"$ts | $Preset | $atlasFull | backup=$backup" | Add-Content -Encoding utf8 $logPath
Write-Host "[log] $logPath"

Write-Host "[done] Restart BAR launcher and select 'Beyond All Reason Dev'."
Write-Host "[revert] Copy-Item '$backup' '$atlasFull' -Force"
