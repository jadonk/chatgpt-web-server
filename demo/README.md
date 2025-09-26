# Demo: record a browser screen-capture (local)

## 1) Start the Crystal server
In a separate terminal:
```bash
shards run
# or: crystal run src/chatgpt-web-server.cr
# or: ./run-app-in-container.sh
```

## 2) Record with Playwright
In the demo directory:
```bash
# ./setup.sh
npm install --silent
npx playwright install --with-deps
# ./run.sh
npx playwright test --config=${PWD}/playwright.config.ts --reporter=line
```
