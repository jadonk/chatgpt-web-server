FROM crystallang/crystal:1.14.0
WORKDIR /app
COPY shard.yml shard.lock* ./
RUN shards install --skip-postinstall
RUN apt-get update && apt-get install -y libsqlite3-dev curl && rm -rf /var/lib/apt/lists/*
COPY . .
RUN shards build --release
EXPOSE 3000
ENV PORT=3000 DB_URL=sqlite3:/app/ui.db
HEALTHCHECK --interval=3s --timeout=2s --retries=40 CMD curl -fsS http://localhost:3000/page/home || exit 1
CMD ["/app/bin/chatgpt-web-server"]
