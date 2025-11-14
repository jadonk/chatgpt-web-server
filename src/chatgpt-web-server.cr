# --- FILE: app.cr -------------------------------------------------------------
require "kemal"
require "./semantic_ui"
require "./layout"
require "./svg_emitter"
require "./jsonld_emitter"

DB_URL = ENV["DB_URL"]? || "sqlite3:./ui.db"
PORT   = (ENV["PORT"]? || "3000").to_i

engine = SemanticUI::Engine.new(DB_URL)
engine.seed_if_empty

get "/" do |env|
  env.redirect "/page/home"
end

get "/page/:slug" do |env|
  slug = env.params.url["slug"]
  begin
    html = SemanticUI::Render.render_page(engine, slug)
    env.response.content_type = "text/html"
    html
  rescue e
    env.response.status_code = 404
    e.message
  end
end

get "/read/:key" do |env|
  key = env.params.url["key"]
  begin
    txt = engine.read_text(key)
    env.response.content_type = "text/plain"
    txt
  rescue e
    env.response.status_code = 400
    e.message
  end
end

post "/write/:key" do |env|
  key = env.params.url["key"]
  params = Hash(String, String).new
  env.params.body.each { |k, v| params[k] = v }
  begin
    txt = engine.write_apply(key, params)
    env.response.content_type = "text/plain"
    txt
  rescue e
    env.response.status_code = 400
    e.message
  end
end

get "/svg/demo" do |env|
  page = Layout::Page.new(
    Layout::Size.new(1000.0, 620.0),
    "Beagle Device Panel",
    "Shows temperature and LED controls.",
    [
      Layout::Text.new(Layout::Point.new(24, 40), "Beagle Device Panel", 28),

      Layout::Stack.new(Layout::Point.new(24, 80), [
        Layout::Text.new(Layout::Point.new(0, 0), "Temperature: — °C", 16),
        Layout::Button.new(Layout::Point.new(0, 24), "Read temperature",
          "/read/temp_sensor", Layout::Size.new(160, 36)),
        Layout::Text.new(Layout::Point.new(0, 74), "LED: off", 16),
        Layout::Button.new(Layout::Point.new(0, 98), "LED ON",
          "/write/led?value=true", Layout::Size.new(120, 36)),
        Layout::Button.new(Layout::Point.new(130, 98), "LED OFF",
          "/write/led?value=false", Layout::Size.new(120, 36)),
      ], 12.0),

      Layout::Image.new(Layout::Point.new(760, 24), "/favicon.ico",
        Layout::Size.new(200, 200), "Project icon"),
    ]
  )

  env.response.content_type = "image/svg+xml"
  SvgEmitter.emit(page)
end

get "/svg/demo.jsonld" do |env|
  page = Layout::Page.new(
    Layout::Size.new(1000.0, 620.0),
    "Beagle Device Panel",
    "Shows temperature and LED controls."
  )
  env.response.content_type = "application/ld+json"
  JsonLdEmitter.emit(page)
end

get "/favicon.ico" do |env|
  env.response.content_type = "image/x-icon"
  File.read("public/favicon.ico")
end

Kemal.config.port = PORT
Kemal.run
