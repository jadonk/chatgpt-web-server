# ------------------------------- app.cr --------------------------------------
# Save as: app.cr

require "kemal"
require "db"
require "sqlite3"
require "json"

# ------------------------------ Config/State ---------------------------------
APP_TITLE  = "Device Console"
DB_URL     = "sqlite3:./ui.db"

LED_ON     = Atomic(Bool).new(false)

# ------------------------------- DB bootstrap --------------------------------
SCHEMA_SQL = <<-SQL
CREATE TABLE IF NOT EXISTS pages (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  layout TEXT NOT NULL DEFAULT 'two_col',
  hints TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS blocks (
  id INTEGER PRIMARY KEY,
  page_id INTEGER NOT NULL,
  region TEXT NOT NULL,         -- 'chrome' | 'header' | 'main' | 'sidebar' | 'footer'
  ord INTEGER NOT NULL DEFAULT 0,
  kind TEXT NOT NULL,           -- 'text' | 'stat' | 'button' | 'form' | 'table' | 'divider'
  spec TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY(page_id) REFERENCES pages(id)
);
SQL

DB_CONN = DB.open DB_URL

# Ensure schema and seed demo content on first run
DB_CONN.exec SCHEMA_SQL
count = DB_CONN.query_one("SELECT COUNT(*) FROM pages", as: Int64)
if count == 0
  DB_CONN.exec "INSERT INTO pages (slug, title, layout, hints) VALUES (?,?,?,?)",
    "home", "Beagle Device Panel", "two_col", {
      "sidebar_width" => "300px",
      "max_width"     => "1100px"
    }.to_json

  page_id = DB_CONN.query_one("SELECT last_insert_rowid()", as: Int64)

  insert_block = DB_CONN.build_prepared_statement("INSERT INTO blocks (page_id, region, ord, kind, spec) VALUES (?,?,?,?,?)")

  # CHROME
  insert_block.exec page_id, "chrome", 0, "text",    {"html" => "<strong>⚙️ Beagle Panel</strong> — server‑driven UI demo"}.to_json
  insert_block.exec page_id, "chrome", 1, "button",  {
    "label" => "↻ Refresh temp", "method" => "GET", "action" => "temp",
    "target" => "#tempVal", "swap" => "text"
  }.to_json
  insert_block.exec page_id, "chrome", 2, "button",  {
    "label" => "Toggle LED", "method" => "POST", "action" => "toggle_led",
    "target" => "#ledState", "swap" => "text"
  }.to_json

  # HEADER
  insert_block.exec page_id, "header", 0, "text", {"role" => "h1", "text" => "Beagle Device Panel", "style" => {"size" => "2xl", "weight" => "600"}}.to_json
  insert_block.exec page_id, "header", 1, "text", {"text" => "Everything here is defined in SQLite as semantic blocks + layout hints."}.to_json

  # SIDEBAR
  insert_block.exec page_id, "sidebar", 0, "stat", {"label" => "Temperature", "value_id" => "tempVal", "initial" => "-- °C", "icon" => "🌡️"}.to_json
  insert_block.exec page_id, "sidebar", 1, "stat", {"label" => "LED",         "value_id" => "ledState", "initial" => "off",     "icon" => "💡"}.to_json
  insert_block.exec page_id, "sidebar", 2, "divider", {} of String => JSON::Any
  insert_block.exec page_id, "sidebar", 3, "form", {
    "title" => "Send Note",
    "fields" => [{"name" => "text", "placeholder" => "Type a note…"}],
    "method" => "POST", "action" => "note", "after" => "Note sent!"
  }.to_json

  # MAIN
  insert_block.exec page_id, "main", 0, "text",   {"role" => "h2", "text" => "Live Controls", "style" => {"size" => "xl", "weight" => "600"}}.to_json
  insert_block.exec page_id, "main", 1, "button", {"label" => "Read temperature", "method" => "GET",  "action" => "temp",           "target" => "#tempVal", "swap" => "text", "hint" => {"block" => "inline"}}.to_json
  insert_block.exec page_id, "main", 2, "button", {"label" => "LED ON",          "method" => "POST", "action" => "set_led",        "target" => "#ledState", "swap" => "text", "hint" => {"block" => "inline"}}.to_json
  insert_block.exec page_id, "main", 3, "button", {"label" => "LED OFF",         "method" => "POST", "action" => "clear_led",      "target" => "#ledState", "swap" => "text", "hint" => {"block" => "inline"}}.to_json
  insert_block.exec page_id, "main", 4, "text",   {"text" => "Use the buttons above. The values in the sidebar update without reloading the page."}.to_json
  insert_block.exec page_id, "main", 5, "divider", {} of String => JSON::Any
  insert_block.exec page_id, "main", 6, "text",   {"role" => "h2", "text" => "Recent Readings", "style" => {"size" => "xl", "weight" => "600"}}.to_json
  insert_block.exec page_id, "main", 7, "table",  {
    "id" => "readings",
    "columns" => ["When", "Reading"],
    "rows" => [["—", "No data yet"]],
    "append_from_action" => "append_reading"
  }.to_json

  insert_block.close
end

# ------------------------------- Rendering -----------------------------------
struct BlockRow
  getter region, kind, ord, spec_json
  def initialize(@region : String, @kind : String, @ord : Int32, @spec_json : String); end
end

HTMX = %(<script src="https://unpkg.com/htmx.org@1.9.12"></script>)

def html_escape(s : String) : String
  s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
end

def cls_from_hints(spec : JSON::Any) : String
  if (hint = spec["hint"]?).try &.as_h?
    return "inline" if hint["block"]?.try &.as_s? == "inline"
  end
  ""
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
.p{ margin: 6px 0; color: #111827; }
.muted{ color: var(--muted); }
.btn{ display:inline-flex; align-items:center; gap:8px; padding:10px 14px; border-radius: 12px; border:1px solid var(--border); background:#fff; cursor:pointer; }
.btn:hover{ background:#fafafa; }
.row{ display:flex; gap:10px; flex-wrap: wrap; align-items:center; }
.stat{ display:flex; justify-content:space-between; align-items:center; padding:10px 12px; border:1px solid var(--border); border-radius:12px; }
.stat .label{ color: var(--muted); }
.input{ padding:10px 12px; border:1px solid var(--border); border-radius: 12px; min-width: 0; }
.table{ width:100%; border-collapse: collapse; }
.table th,.table td{ border:1px solid var(--border); padding:8px 10px; text-align:left; }
.divider{ height:1px; background: var(--border); margin:10px 0; }
.small{ font-size:12px; color:var(--muted); }
.inline{ display:inline-flex }
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
          <span class="small">Server‑driven UI</span>
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

# Render a single block from its JSON spec
def render_block(kind : String, spec : JSON::Any) : String
  case kind
  when "text"
    role = spec["role"]?.try &.as_s? || "p"
    if html = spec["html"]?.try &.as_s?
      return html
    end
    text = spec["text"]?.try &.as_s? || ""
    case role
    when "h1" then return %(<div class='h1'>#{html_escape text}</div>)
    when "h2" then return %(<div class='h2'>#{html_escape text}</div>)
    else            return %(<p class='p'>#{html_escape text}</p>)
    end

  when "divider"
    return "<div class='divider'></div>"

  when "stat"
    label    = html_escape(spec["label"]?.try &.as_s? || "Stat")
    value_id = spec["value_id"]?.try &.as_s? || ""
    initial  = html_escape(spec["initial"]?.try &.as_s? || "—")
    icon     = spec["icon"]?.try &.as_s? || ""
    left  = %(<span>#{icon} <span class='label'>#{label}</span></span>)
    right = %(<strong id='#{html_escape value_id}'>#{initial}</strong>)
    return %(<div class='stat'>#{left}#{right}</div>)

  when "button"
    label  = html_escape(spec["label"]?.try &.as_s? || "Action")
    method = (spec["method"]?.try &.as_s? || "GET").upcase
    action = spec["action"]?.try &.as_s? || ""
    target = spec["target"]?.try &.as_s? || ""
    swap   = spec["swap"]?.try   &.as_s? || "innerHTML"
    cls    = cls_from_hints(spec)

    hx_method = method == "POST" ? "post" : "get"
    attrs = [
      %Q(hx-#{hx_method}='/action/#{action}'),
      (target.empty? ? nil : %Q(hx-target='#{html_escape target}')),
      (swap.empty?   ? nil : %Q(hx-swap='#{html_escape swap}')),
    ].compact.join(' ')
    return %(<button class='btn #{cls}' #{attrs}>#{label}</button>)

  when "form"
    title  = html_escape(spec["title"]?.try &.as_s? || "Form")
    fields = spec["fields"]?.try &.as_a? || [] of JSON::Any
    method = (spec["method"]?.try &.as_s? || "POST").upcase
    action = spec["action"]?.try &.as_s? || ""
    after  = html_escape(spec["after"]?.try &.as_s?  || "Submitted.")

    inputs = fields.map do |f|
      name = html_escape(f["name"]?.try &.as_s? || "field")
      ph   = html_escape(f["placeholder"]?.try &.as_s? || "")
      %(<input class='input' name='#{name}' placeholder='#{ph}' />)
    end.join

    hx_method = method == "POST" ? "post" : "get"
    hx = %Q(hx-#{hx_method}='/action/#{action}' hx-swap='none' hx-on::after-request="this.reset(); document.querySelector('#flash').textContent='#{after}';")

    return <<-HTML
      <div class='h2'>#{title}</div>
      <form class='row' #{hx}>
        #{inputs}
        <button class='btn'>Send</button>
      </form>
      <div id='flash' class='small muted'></div>
    HTML

  when "table"
    table_id = html_escape(spec["id"]?.try &.as_s? || "tbl")
    cols     = spec["columns"]?.try &.as_a? || [] of JSON::Any
    rows     = spec["rows"]?.try &.as_a?    || [] of JSON::Any

    thead = cols.map { |c| "<th>#{html_escape c.as_s}</th>" }.join
    tbody = rows.map do |r|
      cells = r.as_a.map { |c| "<td>#{html_escape c.to_s}</td>" }.join
      "<tr>#{cells}</tr>"
    end.join

    return %(<table id='#{table_id}' class='table'><thead><tr>#{thead}</tr></thead><tbody>#{tbody}</tbody></table>)
  else
    return %(<div class='p muted'>[unknown block: #{html_escape kind}]</div>)
  end
end

# Render a region from DB rows
def render_region(rows : Array(BlockRow)) : String
  String.build do |io|
    rows.each do |r|
      spec = JSON.parse(r.spec_json)
      io << render_block(r.kind, spec)
      io << "
"
    end
  end
end

# ------------------------------- Routes --------------------------------------
get "/" do |env|
  env.redirect "/page/home"
end

get "/page/:slug" do |env|
  slug = env.params.url["slug"]

  page = DB_CONN.query_one?("SELECT id, title, hints FROM pages WHERE slug = ?", slug, as: {Int64, String, String})
  halt env, status_code: 404, response: "No such page" unless page

  page_id, title, hints_json = page
  hints = JSON.parse(hints_json)
  max_width    = hints["max_width"]?.try &.as_s? || "1200px"
  sidebar_w    = hints["sidebar_width"]?.try &.as_s? || "320px"

  css = CSS_TEMPLATE.gsub("%MAX_WIDTH%", max_width).gsub("%SIDEBAR_WIDTH%", sidebar_w)

  rows = [] of BlockRow
  DB_CONN.query "SELECT region, kind, ord, spec FROM blocks WHERE page_id = ? ORDER BY region, ord, id", page_id do |rs|
    rs.each do
      region = rs.read(String)
      kind   = rs.read(String)
      ord    = rs.read(Int64).to_i
      spec   = rs.read(String)
      rows << BlockRow.new(region, kind, ord, spec)
    end
  end

  # Group by region
  by_region = Hash(String, Array(BlockRow)).new { |h, k| h[k] = [] of BlockRow }
  rows.each { |r| by_region[r.region] << r }

  html = BASE_TEMPLATE
    .gsub("%TITLE%", title)
    .gsub("%CSS%", css)
    .gsub("%CHROME%",  render_region(by_region["chrome"]))
    .gsub("%HEADER%",  render_region(by_region["header"]))
    .gsub("%MAIN%",    render_region(by_region["main"]))
    .gsub("%SIDEBAR%", render_region(by_region["sidebar"]))
    .gsub("%FOOTER%",  render_region(by_region["footer"]))

  env.response.content_type = "text/html"
  html
end

# Interactive actions (server owns state/logic)
post "/action/*" do |env|
  handle_action(env)
end

get "/action/*" do |env|
  handle_action(env)
end

private def handle_action(env)
  name = env.params.url["splat"]? || ""
  name = name.split("?").first # defensive

  case name
  when "temp"
    t = (20.0 + rand * 5).round(1)
    env.response.content_type = "text/plain"
    return "#{t} °C"

  when "append_reading"
    now = Time.local
    t = (20.0 + rand * 5).round(1)
    row = %(<tr><td>#{now.to_s("%H:%M:%S")}</td><td>#{t} °C</td></tr>)
    env.response.content_type = "text/html"
    return row

  when "toggle_led"
    LED_ON.set(!LED_ON.get)
    env.response.content_type = "text/plain"
    return LED_ON.get ? "on" : "off"

  when "set_led"
    LED_ON.set(true)
    env.response.content_type = "text/plain"
    return "on"

  when "clear_led"
    LED_ON.set(false)
    env.response.content_type = "text/plain"
    return "off"

  when "note"
    text = env.params.body["text"]?.to_s.strip
    puts "NOTE: #{text}"
    env.response.content_type = "text/plain"
    return "ok"

  else
    env.response.status_code = 404
    return "Unknown action: #{name}"
  end
end

Kemal.config.port = 3000
Kemal.run

