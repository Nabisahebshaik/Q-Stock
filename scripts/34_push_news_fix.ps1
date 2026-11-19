# Push the NSE-news fix (Yahoo company-name search) of 2026-11-18 evening.
# Run from the project root:  powershell -ExecutionPolicy Bypass -File scripts\34_push_news_fix.ps1
$R = "C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe"
& $R tests/run_tests.R; if ($LASTEXITCODE -ne 0) { Write-Host "unit tests failed - nothing pushed" -ForegroundColor Red; exit 1 }
& $R tests/test_api.R;  if ($LASTEXITCODE -ne 0) { Write-Host "API tests failed - nothing pushed" -ForegroundColor Red; exit 1 }
git add -- R/news_feed.R R/explain.R tests/testthat/test_features_v4.R scripts/34_push_news_fix.ps1
git commit -m "News: Yahoo company-name search for NSE stocks, relevance filter, longer GDELT timeout"
git push
Write-Host "Pushed. Render redeploys in about 5-10 minutes." -ForegroundColor Green
