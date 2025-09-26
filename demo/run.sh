#!/usr/bin/env bash
set -euo pipefail
npx playwright test --config=$(dirname $0)/playwright.config.ts --reporter=line
