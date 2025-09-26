# --- FILE: app.cr -------------------------------------------------------------
require "kemal"
require "./semantic_ui"

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

get "/favicon.ico" do |env|
  env.response.content_type = "image/x-icon"
  File.read("public/favicon.ico")
end

Kemal.config.port = PORT
Kemal.run
