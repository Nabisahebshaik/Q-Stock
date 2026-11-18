# Deploy the 2026-11-18 update (terminal UI, sign-in, XAI, news, assistant, Kotak Neo) to
# GitHub -> Vercel (q-stock-pink.vercel.app) and Render (q-stock-api.onrender.com).
# Run from the project root in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\33_deploy_update.ps1
# Steps: create/reset the Nabi account (you type the password), run the API tests,
# re-export the static snapshot, commit only the files of this update, push.
$ErrorActionPreference = "Stop"
$R = "C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe"
function Step($name, [scriptblock]$body) {
  Write-Host "`n=== $name" -ForegroundColor Yellow
  & $body
  if ($LASTEXITCODE -ne 0) { Write-Host "=== $name FAIL (exit $LASTEXITCODE) - nothing was pushed" -ForegroundColor Red; exit 1 }
  Write-Host "=== $name OK" -ForegroundColor Green
}

Step "1/5 account for Nabi (type your password when asked)" { & $R scripts/32_create_user.R Nabi --print-env }
Write-Host "Copy the QSTOCK_AUTH_USERS=... line above into Render -> q-stock-api -> Environment (it holds only the hash)." -ForegroundColor Cyan
Read-Host "Press Enter when done (or Enter to skip and do it later)"

Step "2/5 API end-to-end tests" { & $R tests/test_api.R }
Step "3/5 unit tests" { & $R tests/run_tests.R }
Step "4/5 static snapshot (needs internet; a few minutes)" { & $R scripts/25_export_snapshot.R }

$files = @(
  ".dockerignore", ".gitignore", ".Renviron.example", "README.md", "CLAUDE.md",
  "R/auth.R", "R/news_feed.R", "R/assistant.R", "R/explain.R", "R/kotak_neo.R", "R/live_market.R",
  "api/plumber.R", "api/run_api.R",
  "scripts/25_export_snapshot.R", "scripts/32_create_user.R", "scripts/33_deploy_update.ps1",
  "tests/test_api.R", "tests/testthat/test_features_v4.R",
  "docs/design/TERMINAL_UI.md", "docs/operations/HANDOFF.md", "docs/operations/KOTAK_NEO.md",
  "web/index.html", "web/tailwind.config.js", "web/src/App.tsx", "web/src/index.css", "web/src/lib/api.ts",
  "web/src/components/ui.tsx", "web/src/components/terminal", "web/src/pages/LivePage.tsx",
  "web/src/pages/ExplainPage.tsx", "web/src/pages/NewsPage.tsx", "web/public/data"
)
Step "5/5 commit and push" {
  git add -- $files
  $staged = git diff --cached --name-only
  if ($staged -match '(^|/)\.Renviron$' -or $staged -match '^data/auth/') { Write-Host "secret file staged - aborting" -ForegroundColor Red; git reset -q; exit 1 }
  git commit -m "Terminal UI, sign-in, explainable forecast, news, assistant, Kotak Neo feed"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  git push
}
Write-Host "`nPushed. Vercel and Render rebuild in about 5-10 minutes: https://q-stock-pink.vercel.app" -ForegroundColor Green
