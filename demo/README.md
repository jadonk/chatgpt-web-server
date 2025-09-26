# Demo: record a browser screen-capture (local)

## 1) Start the Crystal server
In a separate terminal:
```bash
shards run
# or: crystal run src/chatgpt-web-server.cr
```

## 2) Record with Playwright
```bash
cd demo
npm install
npm run install:browsers
npm run record
```

