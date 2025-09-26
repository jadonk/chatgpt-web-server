# ChatGPT generated web server

Several of the statements below are false, but the web server does serve up a pretty slick little UI.

<video src="assets/demo.mp4" controls muted playsinline width="800"></video>

![Live demo](assets/demo.gif)

# Semantic UI (Crystal + SQLite + Kemal)

Build web UIs by defining **semantics**, not HTML.
You declare **entities** (domain objects) and **widgets** (UI blocks) in SQLite; the server renders HTML at request time and owns all interactivity.

- **No HTML stored in DB** — only semantic data (types, labels, ops)
- **Server-side logic** — UI actions are HTTP endpoints you implement
- **Zero custom client JS** — uses a tiny `htmx` script for requests
- **Library-first** — `SemanticUI::Engine` + `SemanticUI::Render`

---

## Requirements
- Crystal ≥ 1.14
- SQLite3 runtime (`libsqlite3`)

## Project layout
```
.
├── shards.yml                 # deps: kemal, sqlite3
├── src/
│   ├── semantic_ui.cr         # module: Engine + Render + data structs
│   └── chatgpt-web-server.cr  # thin Kemal runner
└── spec/
    └── semantic_ui_spec.cr    # tests
```

---

## Quick start
```bash
rm -f ui.db && shards run
# open http://localhost:3000
```
First run creates `ui.db` and seeds a demo page (`/page/home`).

### Run the tests
```bash
crystal spec
```

### Configuration
- `DB_URL` — database URL (default: `sqlite3:./ui.db`)
- `PORT`   — HTTP port (default: `3000`)

---

## Concepts

### Entities (the domain)
Stored in table `entities` with a stable `key`, a `kind`, and a typed `schema` (JSON).

Examples:
```json
{"type":"number","unit":"°C","format":"1dp"}
{"type":"boolean"}
{"type":"string","max":200}
```
Optional: `read_action`, `write_action` (symbolic names your server handles).

### Layouts (pages)
Stored in `layouts` with `slug`, `title`, and `hints` (e.g., `{ "sidebar_width": "300px", "max_width": "1100px" }`).

### Widgets (views)
Stored in `widgets`. Each row declares **what** to show and **where**:
- `region`: `chrome | header | main | sidebar | footer`
- `widget_kind`: `heading | value | toggle | button | form | divider`
- `entity_key`: optional reference to an entity
- `label`: human text
- `hints`: semantic/presentation hints (JSON), e.g.:
  - `{"level": 2}` for headings
  - `{"style": "stat"}` for compact stat blocks
  - `{"op": "read" | "toggle" | "write", "value": true}` for buttons
  - `{"fields": [{"name":"text","placeholder":"Type a note…"}]}` for forms

> All HTML is produced by server templates. The DB never contains raw HTML.

---

## HTTP endpoints
- **Render page**: `GET /page/:slug` → full HTML
- **Read (typed)**: `GET /read/:key` → text, e.g., `23.4 °C`, `on`, `off`
- **Write (typed)**: `POST /write/:key`
  - body fields: `value=true|false|1|0`, `toggle=true`, or domain-specific (e.g., `text`)

The UI triggers these via `hx-*` attributes—no custom JS is authored.

---

## Using the module
```crystal
require "./src/semantic_ui"

engine = SemanticUI::Engine.new(ENV["DB_URL"]? || "sqlite3:./ui.db")
engine.seed_if_empty

html = SemanticUI::Render.render_page(engine, "home")
puts html
```

### Kemal integration (simplified from `app.cr`)
```crystal
require "kemal"
require "./src/semantic_ui"

engine = SemanticUI::Engine.new
engine.seed_if_empty

get "/page/:slug" { |env| env.response.print SemanticUI::Render.render_page(engine, env.params.url["slug"]) }
get "/read/:key"  { |env| env.response.print engine.read_text(env.params.url["key"]) }
post "/write/:key" do |env|
  params = Hash(String, String).new
  env.params.body.each { |k, v| params[k] = v }
  env.response.print engine.write_apply(env.params.url["key"], params)
end
Kemal.run
```

---

## Seeded demo
- **Entities:** `temp_sensor` (number °C), `led` (boolean), `note` (string)
- **Page:** `/page/home`
- **Widgets:** toolbar buttons (refresh temp, toggle LED), stat blocks, simple form

Click “Read temperature” to update the Temperature stat. Use LED buttons to set/toggle state. The Note form posts text to the server.

---

## Customize

### Add an entity
```sql
INSERT INTO entities (key, kind, schema, read_action, write_action)
VALUES (
  'fan', 'actuator',
  '{"type":"boolean"}',
  'fan_state', 'set_fan'
);
```
Then implement `fan_state`/`set_fan` in `Engine#read_text` / `Engine#write_apply`.

### Add a widget
```sql
INSERT INTO widgets (layout_id, region, ord, widget_kind, entity_key, label, hints)
VALUES (
  1, 'main', 10, 'button', 'fan', 'Fan ON',
  '{"op":"write","value":true}'
);
```

### Auto-refresh a value (optional)
Add `{"trigger":"load, every 10s"}` to a value widget’s `hints` and include an autoload div in the value renderer (see comments in code).

---

## Troubleshooting
- **`no such table: layouts`** — Remove `ui.db` (from older versions) and rerun; tables are created on start.
- **JSON parse errors in `hints`** — Ensure valid JSON (double quotes, no symbols/single quotes).
- **Nothing updates** — Use DevTools → Network; confirm `/read/:key` or `/write/:key` returns `200`.

---

## Production
```bash
shards build --release
./chatgpt-web-server
```
Run behind a reverse proxy (nginx/Caddy). Add auth/CSRF if exposing publicly (this demo has none).

---

## License
MIT — see `LICENSE`.

## Acknowledgements
- [Crystal](https://crystal-lang.org/), [Kemal](https://kemalcr.com/), [SQLite](https://sqlite.org/), and the tiny-but-mighty [htmx](https://htmx.org/).

