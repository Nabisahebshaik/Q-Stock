# Q-Stock R API on Render (free web service, Docker runtime). Built from the repository root
# (see render.yaml); only what the API needs is copied in, no raw or curated data.
FROM rocker/r-ver:4.4.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev libssl-dev libsodium-dev zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN install2.r --error --skipinstalled plumber RSQLite DBI curl jsonlite Matrix

WORKDIR /app
COPY R ./R
COPY api/plumber.R api/run_api.R ./api/
COPY api/model ./api/model
COPY results/tables ./results/tables

# Daily price history downloaded once at build time (faster start); falls back to start-up.
RUN Rscript -e 'for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f); invisible(load_market_data())' || true

# Render provides PORT; listen on all interfaces.
ENV QSTOCK_HOST=0.0.0.0
CMD ["Rscript", "api/run_api.R"]
