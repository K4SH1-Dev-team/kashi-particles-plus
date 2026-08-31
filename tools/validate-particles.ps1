# Validates a whole folder of .particle.json files against the runtime's parser.
#
# Use before importing a pack: it lists the effects that would not load at all (and why), and the
# components that load but silently lose behaviour.
#
#   tools\validate-particles.ps1 "G:\...\ds rp\particles"

param([Parameter(Mandatory = $true)][string]$Folder)

$ErrorActionPreference = "Stop"

$project  = Split-Path -Parent $PSScriptRoot
$mcreator = Join-Path $project "mcreator"
$out      = Join-Path $env:TEMP "kashi-validate"

$javac = Join-Path $mcreator "jdk\bin\javac.exe"
$java  = Join-Path $mcreator "jdk\bin\java.exe"
$gson  = Get-ChildItem (Join-Path $mcreator "lib") -Filter "gson-*.jar" | Select-Object -First 1

if (-not (Test-Path $Folder)) { throw "not found: $Folder" }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null

$sources = @()
$sources += Get-ChildItem (Join-Path $project "core\src\main\java") -Recurse -Filter "*.java" | ForEach-Object { $_.FullName }
$sources += (Join-Path $project "core\src\test\java\net\kashi\particles\core\ParticleBatchValidator.java")

& $javac -encoding UTF-8 -proc:none -nowarn -classpath $gson.FullName -d $out $sources
if ($LASTEXITCODE -ne 0) { throw "validator failed to compile" }

& $java -classpath "$out;$($gson.FullName)" net.kashi.particles.core.ParticleBatchValidator (Resolve-Path $Folder)
