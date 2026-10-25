# Q-Stock R API on Render (free web service, Docker runtime). Built from the repository root
# (see render.yaml); only what the API needs is copied in, no raw or curated data.
FROM rocker/r-ver:4.4.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libsodium-dev zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN install2.r --error --skipinstalled plumber RSQLite DBI curl jsonlite Matrix
# duckdb (live candle store) pinned to the version the tests ran on (1.5.6): the image's own CRAN
# snapshot has 1.2.0, and current CRAN is 2.x. P3M serves it as a prebuilt binary for this distro.
RUN install2.r --error -r "https://p3m.dev/cran/__linux__/$(. /etc/os-release && echo $VERSION_CODENAME)/2026-10-20" duckdb \
    && Rscript -e 'stopifnot(packageVersion("duckdb") == "1.5.6")'

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
