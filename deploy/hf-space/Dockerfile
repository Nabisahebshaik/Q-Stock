# Q-Stock R API container (Hugging Face Spaces, Docker SDK; also runs on any Docker host).
# Build context = the folder assembled by scripts/27_build_hf_space.sh.
FROM rocker/r-ver:4.4.2

# System libraries for curl/openssl (Yahoo fetch), sodium (plumber) and SQLite.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libsodium-dev zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN install2.r --error --skipinstalled plumber RSQLite DBI curl jsonlite Matrix

# Spaces run the container as user 1000.
RUN useradd -m -u 1000 user
WORKDIR /home/user/app
COPY --chown=user . .
USER user

# Download the daily price history once at build time (faster wake-ups). If Yahoo is
# unreachable from the builder, the API downloads it at start-up instead.
RUN Rscript -e 'for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f); invisible(load_market_data())' || true

ENV QSTOCK_HOST=0.0.0.0 PORT=7860
EXPOSE 7860
CMD ["Rscript", "api/run_api.R"]
