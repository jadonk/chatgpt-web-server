# ------------------------------- app.cr --------------------------------------
require "kemal"
require "db"
require "sqlite3"
require "json"

APP_TITLE = "Device Console"
DB_URL    = "sqlite3:./ui.db"

# Simulated device state
LED_ON    = Atomic(Bool).new(false)

# ------------------------------- Schema --------------------------------------
# No HTML in DB. Two layers:
# 1) Model layer: semantic **entities** (measurement/actuator/note/etc.) with typed schema
# 2) View layer: **layouts** and **widgets** that reference entities by key and
#    give layout/presentation hints (still semantic: labels, roles, ops)

SCHEMA_SQL = <<-SQL
CREATE TABLE IF NOT EXISTS entities (
  id INTEGER PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,           -- stable key like 'temp_sensor', 'led'
  kind TEXT NOT NULL,                 -- 'measurement' | 'actuator' | 'note'
  schema TEXT NOT NULL DEFAULT '{}',  -- JSON: {type: 'number'|'boolean'|'string', unit?, format?}
  read_action  TEXT,                  -- symbolic handler name for reads
  write_action TEXT                   -- symbolic handler name for writes
);

CREATE TABLE IF NOT EXISTS layouts (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  hints TEXT NOT NULL DEFAULT '{}'    -- JSON: {max_width, sidebar_width, ...}
);

CREATE TABLE IF NOT EXISTS widgets (
  id INTEGER PRIMARY KEY,
  layout_id INTEGER NOT NULL,
  region TEXT NOT NULL,               -- 'chrome'|'header'|'main'|'sidebar'|'footer'
  ord INTEGER NOT NULL DEFAULT 0,
  widget_kind TEXT NOT NULL,          -- 'heading'|'value'|'toggle'|'button'|'form'|'divider'
  entity_key TEXT,                    -- references entities.key (nullable for heading/divider)
  label TEXT,                         -- human label (plain text only)
  hints TEXT NOT NULL DEFAULT '{}',   -- JSON: semantic/presentation hints (e.g., {level:1}, {op:'read'})
  FOREIGN KEY(layout_id) REFERENCES layouts(id)
);
SQL

DB_CONN = DB.open DB_URL
DB_CONN.exec SCHEMA_SQL

# ------------------------------- Seeding -------------------------------------
count = DB_CONN.query_one("SELECT COUNT(*) FROM layouts", as: Int64)
if count == 0
  # Entities (semantics)
  DB_CONN.exec "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
    "temp_sensor", "measurement", {"type" => "number", "unit" => "°C", "format" => "1dp"}.to_json, "temp", nil
  DB_CONN.exec "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
    "led", "actuator", {"type" => "boolean"}.to_json, "led_state", "set_led"
  DB_CONN.exec "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
    "note", "note", {"type" => "string", "max" => 200}.to_json, nil, "note"

  # Layout
  DB_CONN.exec "INSERT INTO layouts (slug, title, hints) VALUES (?,?,?)",
    "home", "Beagle Device Panel", {"sidebar_width"=>"300px","max_width"=>"1100px"}.to_json
  layout_id = DB_CONN.query_one("SELECT last_insert_rowid()", as: Int64)

  add = ->(region : String, ord : Int32, kind : String, entity_key : String?, label : String?, hints : Hash(String, JSON::Any) = {} of String => JSON::Any) do
    DB_CONN.exec "INSERT INTO widgets (layout_id, region, ord, widget_kind, entity_key, label, hints) VALUES (?,?,?,?,?,?,?)",
      layout_id, region, ord, kind, entity_key, label, hints.to_json
  end

  # Chrome (toolbar; semantic buttons)
  add.call "chrome", 0, "button", "temp_sensor", "↻ Refresh temp", {"op"=>"read"}.as_h
  add.call "chrome", 1, "button", "led",          "Toggle LED",   {"op"=>"toggle"}.as_h

  # Header
  add.call "header", 0, "heading", nil, "Beagle Device Panel", {"level"=>1}.as_h
  add.call "header", 1, "heading", nil, "Server‑driven from semantics (no HTML in DB)", {"level"=>3}.as_h

  # Sidebar values
  add.call "sidebar", 0, "value",  "temp_sensor", "Temperature", {"style"=>"stat"}.as_h
  add.call "sidebar", 1, "value",  "led",         "LED",         {"style"=>"stat"}.as_h
  add.call "sidebar", 2, "divider", nil, nil, {} of String => JSON::Any
  add.call "sidebar", 3, "form",   "note",        "Send Note",   {"fields"=>[{"name"=>"text","placeholder"=>"Type a note…"}].to_json}.as_h

  # Main controls
  add.call "main", 0, "heading", nil, "Live Controls", {"level"=>2}.as_h
  add.call "main", 1, "button",  "temp_sensor", "Read temperature", {"op"=>"read"}.as_h
  add.call "main", 2, "button",  "led",          "LED ON",          {"op"=>"write","value"=>true}.as_h
  add.call "main", 3, "button",  "led",          "LED OFF",         {"op"=>"write","value"=>false}.as_h
end

# ------------------------------- Rendering -----------------------------------
struct Widget
  getter region, ord, kind, entity_key, label, hints
  def initialize(@region : String, @ord : Int32, @kind : String, @entity_key : String?, @label : String?, @hints : String)
  end
end

HTMX = %(<script src="https://unpkg.com/htmx.org@1.9.12"></script>)

def html_escape(s : String) : String
  s.gsub("&","&amp;").gsub("<","&lt;").gsub(">","&gt;")
end

CSS_TEMPLATE = <<-CSS
:root{ --gap: 14px; --radius: 14px; --border:#e5e7eb; --bg:#ffffff; --muted:#6b7280; }
*{ box-sizing: border-box }
body{ margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; background:#f6f7f9; }
.header{ position: sticky; top: 0; z-index: 50; border-bottom: 1px solid var(--border); background: var(--bg); }
.max{ max-width: %MAX_WIDTH%; margin: 0 auto; padding: 12px 16px; }
.toolbar{ display:flex; gap: var(--gap); align-items:center; }
.toolbar .spacer{ flex:1 }
.grid{ display:grid; grid-template-columns: 1fr %SIDEBAR_WIDTH%; gap: var(--gap); align-items:start; }
.main{ padding: 20px 16px; }
.card{ background: var(--bg); border: 1px solid var(--border); border-radius: var(--radius); padding: 14px 16px; }
.h1{ font-size: 28px; font-weight: 700; margin:0 0 6px 0; }
.h2{ font-size: 20px; font-weight: 600; margin:0 0 6px 0; }
.h3{ font-size: 16px; font-weight: 600; margin:0 0 6px 0; color:#374151 }
.p{ margin: 6px 0; color: #111827; }
.muted{ color: var(--muted); }
.btn{ display:inline-flex; align-items:center; gap:8px; padding:10px 14px; border-radius: 12px; border:1px solid var(--border); background:#fff; cursor:pointer; }
.btn:hover{ background:#fafafa; }
.row{ display:flex; gap:10px; flex-wrap: wrap; align-items:center; }
.stat{ display:flex; justify-content:space-between; align-items:center; padding:10px 12px; border:1px solid var(--border); border-radius:12px; }
.stat .label{ color: var(--muted); }
.input{ padding:10px 12px; border:1px solid var(--border); border-radius: 12px; min-width: 0; }
.divider{ height:1px; background: var(--border); margin:10px 0; }
.small{ font-size:12px; color:var(--muted); }
CSS

BASE_TEMPLATE = <<-HTML
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>%TITLE%</title>
    #{HTMX}
    <style>%CSS%</style>
  </head>
  <body>
    <div class="header">
      <div class="max">
        <div class="toolbar">
          %CHROME%
          <span class="spacer"></span>
          <span class="small">Server‑driven (semantic)</span>
        </div>
      </div>
    </div>

    <div class="main">
      <div class="max grid">
        <div class="content">
          <div class="card">%HEADER%</div>
          <div class="card">%MAIN%</div>
        </div>
        <aside>
          <div class="card">%SIDEBAR%</div>
        </aside>
      </div>
    </div>

    <footer class="max">
      <div class="small muted">%FOOTER%</div>
    </footer>
  </body>
</html>
HTML

# --------- Model helpers ------------------------------------------------------
record Entity, key : String, kind : String, schema_json : String, read_action : String?, write_action : String?

def get_entity(key : String) : Entity?
  DB_CONN.query_one?("SELECT key, kind, schema, read_action, write_action FROM entities WHERE key = ?", key, as: {String, String, String, String?, String?})
    .try { |t| Entity.new(*t) }
end

# --------- Renderer -----------------------------------------------------------

def target_id_for(entity_key : String) : String
  "value-#{entity_key}"
end


def render_widget(w : Widget) : String
  hints = JSON.parse(w.hints)
  case w.kind
  when "heading"
    lvl = hints["level"]?.try &.as_i? || 2
    cls = case lvl
      when 1 then "h1"
      when 2 then "h2"
      else         "h3"
    end
    label = html_escape(w.label || "")
    return %(<div class='#{cls}'>#{label}</div>)

  when "divider"
    return %(<div class='divider'></div>)

  when "value"
    return render_value_widget(w)

  when "toggle"
    return render_toggle_widget(w)

  when "button"
    return render_button_widget(w)

  when "form"
    return render_form_widget(w)

  else
    return %(<div class='p muted'>[unknown widget: #{html_escape w.kind}]</div>)
  end
end

# -- concrete widget renderers (no HTML in DB; pure templates) -----------------

def render_value_widget(w : Widget) : String
  return %(<div class='p muted'>[value requires entity_key]</div>) unless key = w.entity_key
  ent = get_entity(key)
  return %(<div class='p muted'>[missing entity #{html_escape key}]</div>) unless ent

  label   = html_escape(w.label || key)
  target  = target_id_for(key)
  # semantic default: number shows unit; boolean shows on/off
  # Fetch via GET /read/:key and swap text into target
  btn = %(<button class='btn' hx-get='/read/#{key}' hx-target='##{target}' hx-swap='text'>Refresh</button>)
  value = %(<strong id='#{target}'>—</strong>)
  if (JSON.parse(ent.schema_json)["style"]? == JSON::Any.new("stat")) || (JSON.parse(w.hints)["style"]? == JSON::Any.new("stat"))
    return %(<div class='stat'><span class='label'>#{label}</span>#{value} #{btn}</div>)
  else
    return %(<div class='row'><span>#{label}:</span> #{value} #{btn}</div>)
  end
end


def render_toggle_widget(w : Widget) : String
  return %(<div class='p muted'>[toggle requires entity_key]</div>) unless key = w.entity_key
  ent = get_entity(key)
  return %(<div class='p muted'>[missing entity #{html_escape key}]</div>) unless ent
  target = target_id_for(key)
  on  = %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"value": true}' hx-target='##{target}' hx-swap='text'>ON</button>)
  off = %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"value": false}' hx-target='##{target}' hx-swap='text'>OFF</button>)
  label = html_escape(w.label || key)
  return %(<div class='row'><span>#{label}:</span> <strong id='#{target}'>off</strong> #{on} #{off}</div>)
end


def render_button_widget(w : Widget) : String
  return %(<div class='p muted'>[button requires entity_key]</div>) unless key = w.entity_key
  label = html_escape(w.label || "Action")
  hints = JSON.parse(w.hints)
  op    = hints["op"]?.try &.as_s? || "read"
  target = target_id_for(key)

  case op
  when "read"
    return %(<button class='btn' hx-get='/read/#{key}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
  when "toggle"
    return %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"toggle": true}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
  when "write"
    value = hints["value"]?.try { |v| v.to_s }
    vals  = value ? %({"value": #{value}}) : "{}"
    return %(<button class='btn' hx-post='/write/#{key}' hx-vals='#{vals}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
  else
    return %(<button class='btn'>#{label}</button>)
  end
end


def render_form_widget(w : Widget) : String
  return %(<div class='p muted'>[form requires entity_key]</div>) unless key = w.entity_key
  label = html_escape(w.label || key)
  fields_json = JSON.parse(w.hints)["fields"]?.try &.as_s?
  fields = fields_json ? JSON.parse(fields_json).as_a : [] of JSON::Any
  inputs = fields.map do |f|
    name = html_escape(f["name"]?.try &.as_s? || "field")
    ph   = html_escape(f["placeholder"]?.try &.as_s? || "")
    %(<input class='input' name='#{name}' placeholder='#{ph}' />)
  end.join
  flash_id = "flash-#{key}"
  hx = %Q(hx-post='/write/#{key}' hx-swap='none' hx-on::after-request="this.reset(); document.getElementById('#{flash_id}').textContent='Sent.';")
  return <<-HTML
    <div class='h3'>#{label}</div>
    <form class='row' #{hx}>
      #{inputs}
      <button class='btn'>Send</button>
    </form>
    <div id='#{flash_id}' class='small muted'></div>
  HTML
end

# --------- Page render --------------------------------------------------------
get "/" do |env|
  env.redirect "/page/home"
end

get "/page/:slug" do |env|
  slug = env.params.url["slug"]
  page = DB_CONN.query_one?("SELECT id, title, hints FROM layouts WHERE slug = ?", slug, as: {Int64, String, String})
  halt env, status_code: 404, response: "No such page" unless page

  layout_id, title, hints_json = page
  hints = JSON.parse(hints_json)
  css = CSS_TEMPLATE
    .gsub("%MAX_WIDTH%", hints["max_width"]?.try &.as_s? || "1200px")
    .gsub("%SIDEBAR_WIDTH%", hints["sidebar_width"]?.try &.as_s? || "320px")

  widgets = [] of Widget
  DB_CONN.query "SELECT region, ord, widget_kind, entity_key, label, hints FROM widgets WHERE layout_id = ? ORDER BY region, ord, id", layout_id do |rs|
    rs.each do
      region = rs.read(String)
      ord    = rs.read(Int64).to_i
      kind   = rs.read(String)
      entkey = rs.read(String?)
      label  = rs.read(String?)
      hints  = rs.read(String)
      widgets << Widget.new(region, ord, kind, entkey, label, hints)
    end
  end

  regions = Hash(String, Array(Widget)).new { |h,k| h[k] = [] of Widget }
  widgets.each { |w| regions[w.region] << w }

  build = ->(ws : Array(Widget)) do
    String.build { |io| ws.each { |w| io << render_widget(w) << "
" } }
  end

  html = BASE_TEMPLATE
    .gsub("%TITLE%", title)
    .gsub("%CSS%", css)
    .gsub("%CHROME%",  build.call(regions["chrome"]))
    .gsub("%HEADER%",  build.call(regions["header"]))
    .gsub("%MAIN%",    build.call(regions["main"]))
    .gsub("%SIDEBAR%", build.call(regions["sidebar"]))
    .gsub("%FOOTER%",  build.call(regions["footer"]))

  env.response.content_type = "text/html"
  html
end

# ----------------------------- Semantic actions -------------------------------
# Generic: /read/:key returns a textual representation based on entity schema.
get "/read/:key" do |env|
  key = env.params.url["key"]
  ent = get_entity(key)
  halt env, status_code: 404, response: "No such entity" unless ent

  case ent.read_action
  when "temp"
    t = (20.0 + rand * 5).round(1)
    unit = JSON.parse(ent.schema_json)["unit"]?.try &.as_s? || ""
    env.response.content_type = "text/plain"
    next "#{t} #{unit}".strip
  when "led_state"
    env.response.content_type = "text/plain"
    next (LED_ON.get ? "on" : "off")
  when nil
    env.response.status_code = 400
    next "Entity not readable"
  else
    env.response.status_code = 400
    next "Unknown read action"
  end
end

# Generic: /write/:key applies a typed write based on entity schema.
post "/write/:key" do |env|
  key = env.params.url["key"]
  ent = get_entity(key)
  halt env, status_code: 404, response: "No such entity" unless ent

  case ent.write_action
  when "set_led"
    if env.params.body["toggle"]? == "true"
      LED_ON.set(!LED_ON.get)
    else
      v = env.params.body["value"]?
      LED_ON.set(v == "true" || v == "1") if v
    end
    env.response.content_type = "text/plain"
    next (LED_ON.get ? "on" : "off")
  when "note"
    text = env.params.body["text"]?.to_s.strip
    puts "NOTE: #{text}"
    env.response.content_type = "text/plain"
    next "ok"
  when nil
    env.response.status_code = 400
    next "Entity not writable"
  else
    env.response.status_code = 400
    next "Unknown write action"
  end
end

Kemal.config.port = 3000
Kemal.run
# Server‑driven UI, but **semantic** (Crystal + SQLite)
#
# This version removes any HTML stored in the DB. You define **domain entities**
# (Measurement, Actuator, Note, …) and **widgets** that reference those entities.
# The server maps semantic kinds → templates and renders HTML at request time.
#
# Structure
# ├── shards.yml
# └── app.cr
#
# Run:
#   shards install
#   crystal run app.cr
#   # open http://localhost:3000

# ------------------------------ shards.yml -----------------------------------
name: server_ui
version: 0.2.0
license: MIT
authors:
  - You <you@example.com>

dependencies:
  kemal:
    github: kemalcr/kemal
  sqlite3:
    github: crystal-lang/crystal-sqlite3

# ------------------------------- app.cr --------------------------------------
require "kemal"
require "db"
require "sqlite3"
require "json"

APP_TITLE = "Device Console"
DB_URL    = "sqlite3:./ui.db"

# Simulated device state
LED_ON    = Atomic(Bool).new(false)

# ------------------------------- Schema --------------------------------------
# No HTML in DB. Two layers:
# 1) Model layer: semantic **entities** (measurement/actuator/note/etc.) with typed schema
# 2) View layer: **layouts** and **widgets** that reference entities by key and
#    give layout/presentation hints (still semantic: labels, roles, ops)

SCHEMA_SQL = <<-SQL
CREATE TABLE IF NOT EXISTS entities (
  id INTEGER PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,           -- stable key like 'temp_sensor', 'led'
  kind TEXT NOT NULL,                 -- 'measurement' | 'actuator' | 'note'
  schema TEXT NOT NULL DEFAULT '{}',  -- JSON: {type: 'number'|'boolean'|'string', unit?, format?}
  read_action  TEXT,                  -- symbolic handler name for reads
  write_action TEXT                   -- symbolic handler name for writes
);

CREATE TABLE IF NOT EXISTS layouts (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  hints TEXT NOT NULL DEFAULT '{}'    -- JSON: {max_width, sidebar_width, ...}
);

CREATE TABLE IF NOT EXISTS widgets (
  id INTEGER PRIMARY KEY,
  layout_id INTEGER NOT NULL,
  region TEXT NOT NULL,               -- 'chrome'|'header'|'main'|'sidebar'|'footer'
  ord INTEGER NOT NULL DEFAULT 0,
  widget_kind TEXT NOT NULL,          -- 'heading'|'value'|'toggle'|'button'|'form'|'divider'
  entity_key TEXT,                    -- references entities.key (nullable for heading/divider)
  label TEXT,                         -- human label (plain text only)
  hints TEXT NOT NULL DEFAULT '{}',   -- JSON: semantic/presentation hints (e.g., {level:1}, {op:'read'})
  FOREIGN KEY(layout_id) REFERENCES layouts(id)
);
SQL

DB_CONN = DB.open DB_URL
DB_CONN.exec SCHEMA_SQL

# ------------------------------- Seeding -------------------------------------
count = DB_CONN.query_one("SELECT COUNT(*) FROM layouts", as: Int64)
if count == 0
  # Entities (semantics)
  DB_CONN.exec "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
    "temp_sensor", "measurement", {"type"=>"number","unit"=>"°C","format"=>"1dp"}.to_json, "temp", nil
  DB_CONN.exec "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
    "led", "actuator", {"type"=>"boolean"}.to_json, "led_state", "set_led"
  DB_CONN.exec "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
    "note", "note", {"type"=>"string","max"=>200}.to_json, nil, "note"

  # Layout
  DB_CONN.exec "INSERT INTO layouts (slug, title, hints) VALUES (?,?,?)",
    "home", "Beagle Device Panel", {"sidebar_width"=>"300px","max_width"=>"1100px"}.to_json
  layout_id = DB_CONN.query_one("SELECT last_insert_rowid()", as: Int64)

  add = ->(region : String, ord : Int32, kind : String, entity_key : String?, label : String?, hints : Hash(String, JSON::Any) = {} of String => JSON::Any) do
    DB_CONN.exec "INSERT INTO widgets (layout_id, region, ord, widget_kind, entity_key, label, hints) VALUES (?,?,?,?,?,?,?)",
      layout_id, region, ord, kind, entity_key, label, hints.to_json
  end

  # Chrome (toolbar; semantic buttons)
  add.call "chrome", 0, "button", "temp_sensor", "↻ Refresh temp", {"op"=>"read"}.as_h
  add.call "chrome", 1, "button", "led",          "Toggle LED",   {"op"=>"toggle"}.as_h

  # Header
  add.call "header", 0, "heading", nil, "Beagle Device Panel", {"level"=>1}.as_h
  add.call "header", 1, "heading", nil, "Server‑driven from semantics (no HTML in DB)", {"level"=>3}.as_h

  # Sidebar values
  add.call "sidebar", 0, "value",  "temp_sensor", "Temperature", {"style"=>"stat"}.as_h
  add.call "sidebar", 1, "value",  "led",         "LED",         {"style"=>"stat"}.as_h
  add.call "sidebar", 2, "divider", nil, nil, {} of String => JSON::Any
  add.call "sidebar", 3, "form",   "note",        "Send Note",   {"fields"=>[{"name"=>"text","placeholder"=>"Type a note…"}].to_json}.as_h

  # Main controls
  add.call "main", 0, "heading", nil, "Live Controls", {"level"=>2}.as_h
  add.call "main", 1, "button",  "temp_sensor", "Read temperature", {"op"=>"read"}.as_h
  add.call "main", 2, "button",  "led",          "LED ON",          {"op"=>"write","value"=>true}.as_h
  add.call "main", 3, "button",  "led",          "LED OFF",         {"op"=>"write","value"=>false}.as_h
end

# ------------------------------- Rendering -----------------------------------
struct Widget
  getter region, ord, kind, entity_key, label, hints
  def initialize(@region : String, @ord : Int32, @kind : String, @entity_key : String?, @label : String?, @hints : String)
  end
end

HTMX = %(<script src="https://unpkg.com/htmx.org@1.9.12"></script>)

def html_escape(s : String) : String
  s.gsub("&","&amp;").gsub("<","&lt;").gsub(">","&gt;")
end

CSS_TEMPLATE = <<-CSS
:root{ --gap: 14px; --radius: 14px; --border:#e5e7eb; --bg:#ffffff; --muted:#6b7280; }
*{ box-sizing: border-box }
body{ margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif; background:#f6f7f9; }
.header{ position: sticky; top: 0; z-index: 50; border-bottom: 1px solid var(--border); background: var(--bg); }
.max{ max-width: %MAX_WIDTH%; margin: 0 auto; padding: 12px 16px; }
.toolbar{ display:flex; gap: var(--gap); align-items:center; }
.toolbar .spacer{ flex:1 }
.grid{ display:grid; grid-template-columns: 1fr %SIDEBAR_WIDTH%; gap: var(--gap); align-items:start; }
.main{ padding: 20px 16px; }
.card{ background: var(--bg); border: 1px solid var(--border); border-radius: var(--radius); padding: 14px 16px; }
.h1{ font-size: 28px; font-weight: 700; margin:0 0 6px 0; }
.h2{ font-size: 20px; font-weight: 600; margin:0 0 6px 0; }
.h3{ font-size: 16px; font-weight: 600; margin:0 0 6px 0; color:#374151 }
.p{ margin: 6px 0; color: #111827; }
.muted{ color: var(--muted); }
.btn{ display:inline-flex; align-items:center; gap:8px; padding:10px 14px; border-radius: 12px; border:1px solid var(--border); background:#fff; cursor:pointer; }
.btn:hover{ background:#fafafa; }
.row{ display:flex; gap:10px; flex-wrap: wrap; align-items:center; }
.stat{ display:flex; justify-content:space-between; align-items:center; padding:10px 12px; border:1px solid var(--border); border-radius:12px; }
.stat .label{ color: var(--muted); }
.input{ padding:10px 12px; border:1px solid var(--border); border-radius: 12px; min-width: 0; }
.divider{ height:1px; background: var(--border); margin:10px 0; }
.small{ font-size:12px; color:var(--muted); }
CSS

BASE_TEMPLATE = <<-HTML
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>%TITLE%</title>
    #{HTMX}
    <style>%CSS%</style>
  </head>
  <body>
    <div class="header">
      <div class="max">
        <div class="toolbar">
          %CHROME%
          <span class="spacer"></span>
          <span class="small">Server‑driven (semantic)</span>
        </div>
      </div>
    </div>

    <div class="main">
      <div class="max grid">
        <div class="content">
          <div class="card">%HEADER%</div>
          <div class="card">%MAIN%</div>
        </div>
        <aside>
          <div class="card">%SIDEBAR%</div>
        </aside>
      </div>
    </div>

    <footer class="max">
      <div class="small muted">%FOOTER%</div>
    </footer>
  </body>
</html>
HTML

# --------- Model helpers ------------------------------------------------------
record Entity, key : String, kind : String, schema_json : String, read_action : String?, write_action : String?

def get_entity(key : String) : Entity?
  DB_CONN.query_one?("SELECT key, kind, schema, read_action, write_action FROM entities WHERE key = ?", key, as: {String, String, String, String?, String?})
    .try { |t| Entity.new(*t) }
end

# --------- Renderer -----------------------------------------------------------

def target_id_for(entity_key : String) : String
  "value-#{entity_key}"
end


def render_widget(w : Widget) : String
  hints = JSON.parse(w.hints)
  case w.kind
  when "heading"
    lvl = hints["level"]?.try &.as_i? || 2
    cls = case lvl
      when 1 then "h1"
      when 2 then "h2"
      else         "h3"
    end
    label = html_escape(w.label || "")
    return %(<div class='#{cls}'>#{label}</div>)

  when "divider"
    return %(<div class='divider'></div>)

  when "value"
    return render_value_widget(w)

  when "toggle"
    return render_toggle_widget(w)

  when "button"
    return render_button_widget(w)

  when "form"
    return render_form_widget(w)

  else
    return %(<div class='p muted'>[unknown widget: #{html_escape w.kind}]</div>)
  end
end

# -- concrete widget renderers (no HTML in DB; pure templates) -----------------

def render_value_widget(w : Widget) : String
  return %(<div class='p muted'>[value requires entity_key]</div>) unless key = w.entity_key
  ent = get_entity(key)
  return %(<div class='p muted'>[missing entity #{html_escape key}]</div>) unless ent

  label   = html_escape(w.label || key)
  target  = target_id_for(key)
  # semantic default: number shows unit; boolean shows on/off
  # Fetch via GET /read/:key and swap text into target
  btn = %(<button class='btn' hx-get='/read/#{key}' hx-target='##{target}' hx-swap='text'>Refresh</button>)
  value = %(<strong id='#{target}'>—</strong>)
  if (JSON.parse(ent.schema_json)["style"]? == JSON::Any.new("stat")) || (JSON.parse(w.hints)["style"]? == JSON::Any.new("stat"))
    return %(<div class='stat'><span class='label'>#{label}</span>#{value} #{btn}</div>)
  else
    return %(<div class='row'><span>#{label}:</span> #{value} #{btn}</div>)
  end
end


def render_toggle_widget(w : Widget) : String
  return %(<div class='p muted'>[toggle requires entity_key]</div>) unless key = w.entity_key
  ent = get_entity(key)
  return %(<div class='p muted'>[missing entity #{html_escape key}]</div>) unless ent
  target = target_id_for(key)
  on  = %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"value": true}' hx-target='##{target}' hx-swap='text'>ON</button>)
  off = %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"value": false}' hx-target='##{target}' hx-swap='text'>OFF</button>)
  label = html_escape(w.label || key)
  return %(<div class='row'><span>#{label}:</span> <strong id='#{target}'>off</strong> #{on} #{off}</div>)
end


def render_button_widget(w : Widget) : String
  return %(<div class='p muted'>[button requires entity_key]</div>) unless key = w.entity_key
  label = html_escape(w.label || "Action")
  hints = JSON.parse(w.hints)
  op    = hints["op"]?.try &.as_s? || "read"
  target = target_id_for(key)

  case op
  when "read"
    return %(<button class='btn' hx-get='/read/#{key}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
  when "toggle"
    return %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"toggle": true}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
  when "write"
    value = hints["value"]?.try { |v| v.to_s }
    vals  = value ? %({"value": #{value}}) : "{}"
    return %(<button class='btn' hx-post='/write/#{key}' hx-vals='#{vals}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
  else
    return %(<button class='btn'>#{label}</button>)
  end
end


def render_form_widget(w : Widget) : String
  return %(<div class='p muted'>[form requires entity_key]</div>) unless key = w.entity_key
  label = html_escape(w.label || key)
  fields_json = JSON.parse(w.hints)["fields"]?.try &.as_s?
  fields = fields_json ? JSON.parse(fields_json).as_a : [] of JSON::Any
  inputs = fields.map do |f|
    name = html_escape(f["name"]?.try &.as_s? || "field")
    ph   = html_escape(f["placeholder"]?.try &.as_s? || "")
    %(<input class='input' name='#{name}' placeholder='#{ph}' />)
  end.join
  flash_id = "flash-#{key}"
  hx = %Q(hx-post='/write/#{key}' hx-swap='none' hx-on::after-request="this.reset(); document.getElementById('#{flash_id}').textContent='Sent.';")
  return <<-HTML
    <div class='h3'>#{label}</div>
    <form class='row' #{hx}>
      #{inputs}
      <button class='btn'>Send</button>
    </form>
    <div id='#{flash_id}' class='small muted'></div>
  HTML
end

# --------- Page render --------------------------------------------------------
get "/" do |env|
  env.redirect "/page/home"
end

get "/page/:slug" do |env|
  slug = env.params.url["slug"]
  page = DB_CONN.query_one?("SELECT id, title, hints FROM layouts WHERE slug = ?", slug, as: {Int64, String, String})
  halt env, status_code: 404, response: "No such page" unless page

  layout_id, title, hints_json = page
  hints = JSON.parse(hints_json)
  css = CSS_TEMPLATE
    .gsub("%MAX_WIDTH%", hints["max_width"]?.try &.as_s? || "1200px")
    .gsub("%SIDEBAR_WIDTH%", hints["sidebar_width"]?.try &.as_s? || "320px")

  widgets = [] of Widget
  DB_CONN.query "SELECT region, ord, widget_kind, entity_key, label, hints FROM widgets WHERE layout_id = ? ORDER BY region, ord, id", layout_id do |rs|
    rs.each do
      region = rs.read(String)
      ord    = rs.read(Int64).to_i
      kind   = rs.read(String)
      entkey = rs.read(String?)
      label  = rs.read(String?)
      hints  = rs.read(String)
      widgets << Widget.new(region, ord, kind, entkey, label, hints)
    end
  end

  regions = Hash(String, Array(Widget)).new { |h,k| h[k] = [] of Widget }
  widgets.each { |w| regions[w.region] << w }

  build = ->(ws : Array(Widget)) do
    String.build { |io| ws.each { |w| io << render_widget(w) << "
" } }
  end

  html = BASE_TEMPLATE
    .gsub("%TITLE%", title)
    .gsub("%CSS%", css)
    .gsub("%CHROME%",  build.call(regions["chrome"]))
    .gsub("%HEADER%",  build.call(regions["header"]))
    .gsub("%MAIN%",    build.call(regions["main"]))
    .gsub("%SIDEBAR%", build.call(regions["sidebar"]))
    .gsub("%FOOTER%",  build.call(regions["footer"]))

  env.response.content_type = "text/html"
  html
end

# ----------------------------- Semantic actions -------------------------------
# Generic: /read/:key returns a textual representation based on entity schema.
get "/read/:key" do |env|
  key = env.params.url["key"]
  ent = get_entity(key)
  halt env, status_code: 404, response: "No such entity" unless ent

  case ent.read_action
  when "temp"
    t = (20.0 + rand * 5).round(1)
    unit = JSON.parse(ent.schema_json)["unit"]?.try &.as_s? || ""
    env.response.content_type = "text/plain"
    next "#{t} #{unit}".strip
  when "led_state"
    env.response.content_type = "text/plain"
    next (LED_ON.get ? "on" : "off")
  when nil
    env.response.status_code = 400
    next "Entity not readable"
  else
    env.response.status_code = 400
    next "Unknown read action"
  end
end

# Generic: /write/:key applies a typed write based on entity schema.
post "/write/:key" do |env|
  key = env.params.url["key"]
  ent = get_entity(key)
  halt env, status_code: 404, response: "No such entity" unless ent

  case ent.write_action
  when "set_led"
    if env.params.body["toggle"]? == "true"
      LED_ON.set(!LED_ON.get)
    else
      v = env.params.body["value"]?
      LED_ON.set(v == "true" || v == "1") if v
    end
    env.response.content_type = "text/plain"
    next (LED_ON.get ? "on" : "off")
  when "note"
    text = env.params.body["text"]?.to_s.strip
    puts "NOTE: #{text}"
    env.response.content_type = "text/plain"
    next "ok"
  when nil
    env.response.status_code = 400
    next "Entity not writable"
  else
    env.response.status_code = 400
    next "Unknown write action"
  end
end

Kemal.config.port = 3000
Kemal.run

