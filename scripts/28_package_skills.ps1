# Zip each project skill in .claude/skills/<name>/ into build/skills/<name>.zip for upload to
# Claude Cowork / claude.ai (Settings -> Capabilities -> Skills -> Upload skill). Claude Code reads
# .claude/skills/ directly and needs no zip. Run from the project root:
#   powershell -ExecutionPolicy Bypass -File scripts/28_package_skills.ps1
$src = Join-Path $PSScriptRoot "..\.claude\skills"
$out = Join-Path $PSScriptRoot "..\build\skills"
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $src -Directory | ForEach-Object {
  if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { Write-Warning "$($_.Name): no SKILL.md, skipped"; return }
  $zip = Join-Path $out "$($_.Name).zip"
  # The zip holds the skill folder itself (<name>/SKILL.md), the layout the upload expects.
  Compress-Archive -Path $_.FullName -DestinationPath $zip -Force
  Write-Output "packaged $zip"
}
