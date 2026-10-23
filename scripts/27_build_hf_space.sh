#!/bin/bash
# Assemble the Hugging Face Space (Docker) for the R API into build/hf-space/.
# Only what the API needs is copied: the R library, the API, the exported GHAR coefficients
# and the small result tables. Raw and curated data are not shipped; prices are downloaded
# from Yahoo when the image is built.
#   bash scripts/27_build_hf_space.sh
set -euo pipefail
OUT=build/hf-space
rm -rf "$OUT"; mkdir -p "$OUT/results/tables" "$OUT/api/model"
cp deploy/hf-space/Dockerfile deploy/hf-space/README.md "$OUT/"
cp -r R "$OUT/R"
cp api/plumber.R api/run_api.R "$OUT/api/"
cp api/model/ghar_live_model.json "$OUT/api/model/"
for f in results/tables/*.csv; do
  case "$(basename "$f")" in predictions_*) ;; *) cp "$f" "$OUT/results/tables/" ;; esac
done
printf '.git\n' > "$OUT/.dockerignore"
du -sh "$OUT" | awk '{print "assembled " $2 " (" $1 ")"}'
