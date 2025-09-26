# ChatGPT generated web server

Several of the statements below are false, but the web server does serve up a pretty slick little UI.

## Server-Driven Semantic UI (Crystal + SQLite + Kemal)

> Build web UIs by defining **semantics**, not HTML.
> You declare **entities** (domain objects) and **widgets** (UI blocks) in SQLite; the server renders HTML at request time and owns all interactivity.

* **No HTML stored in DB** — only semantic data (types, labels, ops).
* **Server-side logic** — UI actions are HTTP endpoints you implement.
* **Zero custom client JS** — uses a tiny `htmx` script for requests.
* **Single file app** — easy to read, fork, and extend.

---

## Quick start

```bash
# 1) Install Crystal and SQLite3 (libsqlite3 must be available)
# 2) Get deps
shards install

# 3) (Optional) start clean
rm -f ui.db

# 4) Run
shards run

# 5) Open
# http://localhost:3000
```

> First run creates `ui.db` and seeds a demo page (`/page/home`).

---

## Project layout

```
.
├── shards.yml     # dependencies: kemal, sqlite3
├── app.cr         # the entire app: schema, seed, renderers, routes
└── ui.db          # generated SQLite database (created on first run)
```

---

## Concepts

### Entities (the domain)

Stored in table `entities` with a stable `key`, `kind`, and a typed `schema`.

* Examples:

  * `temp_sensor`: `{ "type": "number", "unit": "°C", "format": "1dp" }`
  * `led`: `{ "type": "boolean" }`
  * `note`: `{ "type": "string", "max": 200 }`
* Optional: `read_action`, `write_action` (symbolic names your server handles)

### Layouts (pages)

Stored in `layouts` with a `slug` (e.g., `home`), `title`, and `hints`
(e.g., `{ "sidebar_width": "300px", "max_width": "1100px" }`).

### Widgets (views)

Stored in `widgets`, each row declares **what** to show and **where**:

* `region`: `chrome | header | main | sidebar | footer`
* `widget_kind`: `heading | value | toggle | button | form | divider`
* `entity_key`: optional reference to an entity
* `label`: human text
* `hints`: semantic/presentation hints (JSON), e.g.:

  * `{"level": 2}` for headings
  * `{"style": "stat"}` for compact stat blocks
  * `{"op": "read" | "toggle" | "write", "value": true}` for buttons
  * `{"fields": [{"name":"text","placeholder":"Type a note…"}]}` for forms

> All HTML is produced by server templates. The DB never contains raw HTML.

---

## Endpoints

* **Page render**

  * `GET /page/:slug` → full page render (server-generated HTML)

* **Semantic I/O**

  * `GET /read/:key` → returns a textual representation of the entity

    * e.g., `23.4 °C`, `on`, `off`
  * `POST /write/:key` → applies a typed write

    * Form/body fields:

      * `value=true|false|1|0` (for booleans)
      * `toggle=true` (flip boolean)
      * `text=...` (example for `note`)

> In the demo seed, the UI triggers these via `hx-*` attributes—no custom JS.

---

## Seeded demo

* **Entities:** `temp_sensor`, `led`, `note`
* **Page:** `/page/home`
* **Widgets:** toolbar buttons (refresh temp, toggle LED), stat blocks, simple form

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

Then implement `fan_state`/`set_fan` in the `/read/:key` and `/write/:key` route cases.

### Add a widget

```sql
INSERT INTO widgets (layout_id, region, ord, widget_kind, entity_key, label, hints)
VALUES (
  1, 'main', 10, 'button', 'fan', 'Fan ON',
  '{"op":"write","value":true}'
);
```

### Auto-refresh a value (optional)

By default values refresh on click. To auto-refresh, set a hint like
`{"trigger":"load, every 10s"}` and add a tiny autoload div in the value renderer
(see comments in `render_value_widget`).

---

## Troubleshooting

* **`no such table: layouts`**
  Your driver may not accept multi-statement `.exec`. This project splits the schema and executes each statement separately. If you ran an older version, remove `ui.db` and run again:

  ```bash
  rm ui.db && shards run
  ```

* **JSON parse errors in hints**
  Ensure `widgets.hints` is valid JSON (e.g., `{"op":"read"}`), not single quotes or Ruby-like symbols.

* **Nothing updates**
  Open **DevTools → Network**. Click a button and verify `/read/:key` or `/write/:key` returns `200 text/plain`.

* **Port in use**
  Edit `Kemal.config.port` near the end of `chatgpt-web-server.cr`.

---

## Deploy

* Behind a reverse proxy (nginx/Caddy), run:

  ```bash
  shards build --release
  ./bin/chatgpt-web-server
  ```
* Add auth/CSRF if exposing publicly (this demo has none).
* Back up `ui.db` (or switch `DB_URL` to a managed path).

---

## Roadmap / Ideas

* Typed schemas as Crystal structs instead of `JSON::Any`
* Chart/table widgets with server-rendered HTML
* Auth (basic/session) + role-based widget visibility
* Export static HTML for read-only dashboards

---

## License

MIT — see `LICENSE`.

---

## Acknowledgements

* [Crystal](https://crystal-lang.org/), [Kemal](https://kemalcr.com/), [SQLite](https://sqlite.org/), and the tiny-but-mighty [htmx](https://htmx.org/).

---

If you want, I can drop this into a `README.md` file next to `app.cr` and tweak the wording to match your org/repo name.

