# --- FILE: src/semantic_ui.cr -------------------------------------------------
# frozen_string_literal: true
require "db"
require "sqlite3"
require "json"

module SemanticUI
  # ------------------------------ Data models ---------------------------------
  struct Entity
    getter key, kind, schema_json, read_action, write_action

    def initialize(@key : String, @kind : String, @schema_json : String, @read_action : String?, @write_action : String?)
    end
  end

  struct WidgetRow
    getter region, ord, kind, entity_key, label, hints

    def initialize(@region : String, @ord : Int32, @kind : String, @entity_key : String?, @label : String?, @hints : String)
    end
  end

  # ------------------------------- Engine -------------------------------------
  class Engine
    @db : DB::Database

    SCHEMA_SQL = <<-SQL
    CREATE TABLE IF NOT EXISTS entities (
      id INTEGER PRIMARY KEY,
      key TEXT UNIQUE NOT NULL,
      kind TEXT NOT NULL,
      schema TEXT NOT NULL DEFAULT '{}',
      read_action  TEXT,
      write_action TEXT
    );

    CREATE TABLE IF NOT EXISTS layouts (
      id INTEGER PRIMARY KEY,
      slug TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      hints TEXT NOT NULL DEFAULT '{}'
    );

    CREATE TABLE IF NOT EXISTS widgets (
      id INTEGER PRIMARY KEY,
      layout_id INTEGER NOT NULL,
      region TEXT NOT NULL,
      ord INTEGER NOT NULL DEFAULT 0,
      widget_kind TEXT NOT NULL,
      entity_key TEXT,
      label TEXT,
      hints TEXT NOT NULL DEFAULT '{}',
      FOREIGN KEY(layout_id) REFERENCES layouts(id)
    );
    SQL

    def initialize(db_url : String = "sqlite3:./ui.db")
      @db = DB.open(db_url)
      @led_on = Atomic(Bool).new(false)
      create_schema
    end

    def create_schema
      SCHEMA_SQL.split(';').each do |stmt|
        sql = stmt.strip
        next if sql.empty?
        @db.exec sql
      end
    end

    # ----------- Seeding (idempotent) ----------------------------------------
    def seed_if_empty
      layouts_count = @db.query_one("SELECT COUNT(*) FROM layouts", as: Int64)
      return if layouts_count > 0

      # Entities
      add_entities "temp_sensor", "measurement", {"type" => "number", "unit" => "°C", "format" => "1dp"}.to_json, "temp", nil
      add_entities "led", "actuator", {"type" => "boolean"}.to_json, "led_state", "set_led"
      add_entities "note", "note", {"type" => "string", "max" => 200}.to_json, nil, "note"

      # Layout
      add_layout "home", "Beagle Device Panel", {"sidebar_width" => "300px", "max_width" => "1100px"}.to_json
      layout_id = @db.query_one("SELECT last_insert_rowid()", as: Int64)

      # Widgets
      add_widget layout_id, "chrome", 0, "button", "temp_sensor", "↻ Refresh temp", {"op" => "read"}.to_json
      add_widget layout_id, "chrome", 1, "button", "led", "Toggle LED", {"op" => "toggle"}.to_json

      add_widget layout_id, "header", 0, "heading", nil, "Beagle Device Panel", {"level" => 1}.to_json
      add_widget layout_id, "header", 1, "heading", nil, "Server‑driven from semantics (no HTML in DB)", {"level" => 3}.to_json

      add_widget layout_id, "sidebar", 0, "value", "temp_sensor", "Temperature", {"style" => "stat"}.to_json
      add_widget layout_id, "sidebar", 1, "value", "led", "LED", {"style" => "stat"}.to_json
      add_widget layout_id, "sidebar", 2, "divider", nil, nil, "{}"
      add_widget layout_id, "sidebar", 3, "form", "note", "Send Note", {"fields" => [{"name" => "text", "placeholder" => "Type a note…"}]}.to_json

      add_widget layout_id, "main", 0, "heading", nil, "Live Controls", {"level" => 2}.to_json
      add_widget layout_id, "main", 1, "button", "temp_sensor", "Read temperature", {"op" => "read"}.to_json
      add_widget layout_id, "main", 2, "button", "led", "LED ON", {"op" => "write", "value" => true}.to_json
      add_widget layout_id, "main", 3, "button", "led", "LED OFF", {"op" => "write", "value" => false}.to_json
    end

    private def add_entities(key, kind, schema, read_action, write_action)
      @db.exec(
        "INSERT INTO entities (key, kind, schema, read_action, write_action) VALUES (?,?,?,?,?)",
        key, kind, schema, read_action, write_action
      )
    end

    private def add_layout(slug, title, hints)
      @db.exec(
        "INSERT INTO layouts (slug, title, hints) VALUES (?,?,?)",
        slug, title, hints
      )
    end

    private def add_widget(
      layout_id : Int64, region : String, ord : Int32,
      kind : String, entity_key : String?, label : String?,
      hints_json : String = "{}"
    )
      @db.exec(
        "INSERT INTO widgets (layout_id, region, ord, widget_kind, entity_key, label, hints) VALUES (?,?,?,?,?,?,?)",
        layout_id, region, ord, kind, entity_key, label, hints_json
      )
    end

    # --------------------------- Query helpers --------------------------------
    def get_entity(key : String) : Entity?
      if tup = @db.query_one?("SELECT key, kind, schema, read_action, write_action FROM entities WHERE key = ?", key, as: {String, String, String, String?, String?})
        return Entity.new(*tup)
      end
      nil
    end

    def fetch_layout(slug : String) : {Int64, String, String}?
      @db.query_one?("SELECT id, title, hints FROM layouts WHERE slug = ?", slug, as: {Int64, String, String})
    end

    def fetch_widgets(layout_id : Int64) : Array(WidgetRow)
      rows = [] of WidgetRow
      @db.query "SELECT region, ord, widget_kind, entity_key, label, hints FROM widgets WHERE layout_id = ? ORDER BY region, ord, id", layout_id do |rs|
        rs.each do
          region = rs.read(String)
          ord = rs.read(Int64).to_i
          kind = rs.read(String)
          entkey = rs.read(String?)
          label = rs.read(String?)
          hintsj = rs.read(String)
          rows << WidgetRow.new(region, ord, kind, entkey, label, hintsj)
        end
      end
      rows
    end

    # ----------------------------- Semantics ----------------------------------
    def read_text(key : String) : String
      ent = get_entity(key) || raise "No such entity: #{key}"
      case ent.read_action
      when "temp"
        t = (20.0 + rand * 5).round(1)
        unit = JSON.parse(ent.schema_json)["unit"]?.try &.as_s? || ""
        "#{t} #{unit}".strip
      when "led_state"
        @led_on.get ? "on" : "off"
      when nil
        raise "Entity not readable"
      else
        raise "Unknown read action"
      end
    end

    def write_apply(key : String, params : Hash(String, String)) : String
      ent = get_entity(key) || raise "No such entity: #{key}"
      case ent.write_action
      when "set_led"
        if params["toggle"]? == "true"
          @led_on.set(!@led_on.get)
        else
          if v = params["value"]?
            @led_on.set(v == "true" || v == "1")
          end
        end
        @led_on.get ? "on" : "off"
      when "note"
        # In a real app, persist somewhere; demo prints to stdout
        text = params["text"]?.to_s.strip
        puts "NOTE: #{text}"
        "ok"
      when nil
        raise "Entity not writable"
      else
        raise "Unknown write action"
      end
    end
  end

  # ------------------------------- Render -------------------------------------
  module Render
    extend self

    HTMX = %(<script src="https://unpkg.com/htmx.org@1.9.12"></script>)

    CSS_TEMPLATE = <<-CSS
    :root{ --gap:14px; --radius:14px; --border:#e5e7eb; --bg:#ffffff; --muted:#6b7280 }
    *{ box-sizing:border-box }
    body{ margin:0; font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif; background:#f6f7f9 }
    .header{ position:sticky; top:0; z-index:50; border-bottom:1px solid var(--border); background:var(--bg) }
    .max{ max-width:%MAX_WIDTH%; margin:0 auto; padding:12px 16px }
    .toolbar{ display:flex; gap:var(--gap); align-items:center }
    .toolbar .spacer{ flex:1 }
    .grid{ display:grid; grid-template-columns:1fr %SIDEBAR_WIDTH%; gap:var(--gap); align-items:start }
    .main{ padding:20px 16px }
    .card{ background:var(--bg); border:1px solid var(--border); border-radius:var(--radius); padding:14px 16px }
    .h1{ font-size:28px; font-weight:700; margin:0 0 6px }
    .h2{ font-size:20px; font-weight:600; margin:0 0 6px }
    .h3{ font-size:16px; font-weight:600; margin:0 0 6px; color:#374151 }
    .p{ margin:6px 0; color:#111827 }
    .muted{ color:var(--muted) }
    .btn{ display:inline-flex; align-items:center; gap:8px; padding:10px 14px; border-radius:12px; border:1px solid var(--border); background:#fff; cursor:pointer }
    .btn:hover{ background:#fafafa }
    .row{ display:flex; gap:10px; flex-wrap:wrap; align-items:center }
    .stat{ display:flex; justify-content:space-between; align-items:center; padding:10px 12px; border:1px solid var(--border); border-radius:12px }
    .stat .label{ color:var(--muted) }
    .input{ padding:10px 12px; border:1px solid var(--border); border-radius:12px; min-width:0 }
    .divider{ height:1px; background:var(--border); margin:10px 0 }
    .small{ font-size:12px; color:var(--muted) }
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

    private def html_escape(s : String) : String
      s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    private def target_id_for(entity_key : String) : String
      "value-#{entity_key}"
    end

    private def render_value_widget(engine : Engine, w : WidgetRow) : String
      return %(<div class='p muted'>[value requires entity_key]</div>) unless key = w.entity_key
      label = html_escape(w.label || key)
      target = target_id_for(key)
      btn = %(<button class='btn' hx-get='/read/#{key}' hx-target='##{target}' hx-swap='text'>Refresh</button>)
      value = %(<strong id='#{target}'>—</strong>)
      style = (JSON.parse(w.hints)["style"]?.try &.as_s? || "")
      if style == "stat"
        %(<div class='stat'><span class='label'>#{label}</span>#{value} #{btn}</div>)
      else
        %(<div class='row'><span>#{label}:</span> #{value} #{btn}</div>)
      end
    end

    private def render_toggle_widget(w : WidgetRow) : String
      return %(<div class='p muted'>[toggle requires entity_key]</div>) unless key = w.entity_key
      target = target_id_for(key)
      label = html_escape(w.label || key)
      on = %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"value": true}'  hx-target='##{target}' hx-swap='text'>ON</button>)
      off = %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"value": false}' hx-target='##{target}' hx-swap='text'>OFF</button>)
      %(<div class='row'><span>#{label}:</span> <strong id='#{target}'>off</strong> #{on} #{off}</div>)
    end

    private def render_button_widget(w : WidgetRow) : String
      return %(<div class='p muted'>[button requires entity_key]</div>) unless key = w.entity_key
      label = html_escape(w.label || "Action")
      hints = JSON.parse(w.hints)
      op = hints["op"]?.try &.as_s? || "read"
      target = target_id_for(key)
      case op
      when "read"
        %(<button class='btn' hx-get='/read/#{key}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
      when "toggle"
        %(<button class='btn' hx-post='/write/#{key}' hx-vals='{"toggle": true}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
      when "write"
        vals = hints["value"]? ? %({"value": #{hints["value"].to_json}}) : "{}"
        %(<button class='btn' hx-post='/write/#{key}' hx-vals='#{vals}' hx-target='##{target}' hx-swap='text'>#{label}</button>)
      else
        %(<button class='btn'>#{label}</button>)
      end
    end

    private def render_form_widget(w : WidgetRow) : String
      return %(<div class='p muted'>[form requires entity_key]</div>) unless key = w.entity_key
      label = html_escape(w.label || key)
      h = JSON.parse(w.hints)
      fields_node = h["fields"]?
      fields = if (arr = fields_node.try &.as_a?)
                 arr
               elsif (s = fields_node.try &.as_s?)
                 JSON.parse(s).as_a
               else
                 [] of JSON::Any
               end
      inputs = fields.map do |f|
        name = html_escape(f["name"]?.try &.as_s? || "field")
        ph = html_escape(f["placeholder"]?.try &.as_s? || "")
        %(<input class='input' name='#{name}' placeholder='#{ph}' />)
      end.join
      flash_id = "flash-#{key}"
      hx = %Q(hx-post='/write/#{key}' hx-swap='none' hx-on::after-request="this.reset(); document.getElementById('#{flash_id}').textContent='Sent.';")
      <<-HTML
        <div class='h3'>#{label}</div>
        <form class='row' #{hx}>
          #{inputs}
          <button class='btn'>Send</button>
        </form>
        <div id='#{flash_id}' class='small muted'></div>
      HTML
    end

    def render_widget(engine : Engine, w : WidgetRow) : String
      case w.kind
      when "heading"
        hints = JSON.parse(w.hints)
        lvl = hints["level"]?.try &.as_i? || 2
        cls = case lvl
              when 1 then "h1"
              when 2 then "h2"
              else        "h3"
              end
        label = html_escape(w.label || "")
        %(<div class='#{cls}'>#{label}</div>)
      when "divider" then %(<div class='divider'></div>)
      when "value"   then render_value_widget(engine, w)
      when "toggle"  then render_toggle_widget(w)
      when "button"  then render_button_widget(w)
      when "form"    then render_form_widget(w)
      else                %(<div class='p muted'>[unknown widget: #{w.kind}]</div>)
      end
    end

    def render_page(engine : Engine, slug : String) : String
      page = engine.fetch_layout(slug) || raise "No such page: #{slug}"
      layout_id, title, hints_json = page
      hints = JSON.parse(hints_json)
      css = CSS_TEMPLATE
        .gsub("%MAX_WIDTH%", hints["max_width"]?.try &.as_s? || "1200px")
        .gsub("%SIDEBAR_WIDTH%", hints["sidebar_width"]?.try &.as_s? || "320px")

      rows = engine.fetch_widgets(layout_id)
      regions = Hash(String, Array(WidgetRow)).new { |h, k| h[k] = [] of WidgetRow }
      rows.each { |r| regions[r.region] << r }

      build = ->(ws : Array(WidgetRow)) do
        String.build { |io| ws.each { |w| io << render_widget(engine, w) << "
" } }
      end

      BASE_TEMPLATE
        .gsub("%TITLE%", title)
        .gsub("%CSS%", css)
        .gsub("%CHROME%", build.call(regions["chrome"]))
        .gsub("%HEADER%", build.call(regions["header"]))
        .gsub("%MAIN%", build.call(regions["main"]))
        .gsub("%SIDEBAR%", build.call(regions["sidebar"]))
        .gsub("%FOOTER%", build.call(regions["footer"]))
    end
  end
end
