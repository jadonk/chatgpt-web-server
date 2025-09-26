FROM crystallang/crystal:1.12.2
WORKDIR /app
COPY shard.yml shard.lock* ./
RUN shards install --skip-postinstall
COPY . .
RUN shards build --release
EXPOSE 3000
ENV PORT=3000 DB_URL=sqlite3:/app/ui.db
# curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
HEALTHCHECK --interval=3s --timeout=2s --retries=40 CMD curl -fsS http://localhost:3000/page/home || exit 1
CMD ["/app/bin/chatgpt-web-server"]
