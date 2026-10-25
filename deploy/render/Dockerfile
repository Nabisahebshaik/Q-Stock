# Q-Stock R API on Render (free web service, Docker runtime). Built from the repository root
# (see render.yaml); only what the API needs is copied in, no raw or curated data.
FROM rocker/r-ver:4.4.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libsodium-dev zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# duckdb: live candle store (R/store_duckdb.R); RSQLite stays for the rollback backend.
RUN install2.r --error --skipinstalled plumber duckdb RSQLite DBI curl jsonlite Matrix

WORKDIR /app
COPY R ./R
COPY api/plumber.R api/run_api.R ./api/
COPY api/model ./api/model
COPY api/precomputed ./api/precomputed
COPY results/tables ./results/tables

# Daily price history downloaded once at build time (faster start); falls back to start-up.
RUN Rscript -e 'for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f); invisible(load_market_data())' || true

# Render provides PORT; listen on all interfaces.
# One BLAS/OpenMP thread: the base image's OpenBLAS otherwise starts one thread per detected
# core (8) on a 0.1-CPU container, and thread contention made small matrix products ~170x slower.
ENV OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
ENV QSTOCK_HOST=0.0.0.0
CMD ["Rscript", "api/run_api.R"]
