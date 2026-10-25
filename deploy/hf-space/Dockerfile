# Q-Stock R API container (Hugging Face Spaces, Docker SDK; also runs on any Docker host).
# Build context = the folder assembled by scripts/27_build_hf_space.sh.
FROM rocker/r-ver:4.4.2

# System libraries for curl/openssl (Yahoo fetch), sodium (plumber) and SQLite.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libsodium-dev zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN install2.r --error --skipinstalled plumber RSQLite DBI curl jsonlite Matrix
# duckdb (live candle store) pinned to the version the tests ran on (1.5.6): the image's own CRAN
# snapshot has 1.2.0, and current CRAN is 2.x. P3M serves it as a prebuilt binary for this distro.
RUN install2.r --error -r "https://p3m.dev/cran/__linux__/$(. /etc/os-release && echo $VERSION_CODENAME)/2026-10-20" duckdb \
    && Rscript -e 'stopifnot(packageVersion("duckdb") == "1.5.6")'

# Spaces run the container as user 1000.
RUN useradd -m -u 1000 user
WORKDIR /home/user/app
COPY --chown=user . .
USER user

# Download the daily price history once at build time (faster wake-ups). If Yahoo is
# unreachable from the builder, the API downloads it at start-up instead.
RUN Rscript -e 'for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f); invisible(load_market_data())' || true

# One BLAS/OpenMP thread: the base image's OpenBLAS otherwise starts one thread per detected
# core (8) on a 0.1-CPU container, and thread contention made small matrix products ~170x slower.
ENV OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
ENV QSTOCK_HOST=0.0.0.0 PORT=7860
EXPOSE 7860
CMD ["Rscript", "api/run_api.R"]
