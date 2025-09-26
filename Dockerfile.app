# Dockerfile.app
FROM crystallang/crystal:1.14.0

WORKDIR /app

# Install deps
COPY shard.yml shard.lock* ./
RUN shards install --skip-postinstall

# Build
RUN apt-get update && apt-get install -y libsqlite3-dev && rm -rf /var/lib/apt/lists/*
COPY . .
RUN shards build --release

# Expose port + healthcheck
EXPOSE 3000
ENV PORT=3000
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=3s --timeout=2s --retries=30 CMD curl -fsS http://localhost:3000/page/home || exit 1

# Adjust the binary name if your shard target differs
CMD ["/app/bin/chatgpt-web-server"]
