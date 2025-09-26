# --- FILE: spec/semantic_ui_spec.cr ------------------------------------------
require "spec"
require "../src/semantic_ui"

private def with_tmp_engine(path : String)
  File.delete(path) if File.exists?(path)
  engine = SemanticUI::Engine.new("sqlite3:./#{path}")
  engine.seed_if_empty
  begin
    yield engine
  ensure
    # keep DB for post-mortem if desired; uncomment to delete
    # File.delete(path) if File.exists?(path)
  end
end

describe SemanticUI do
  it "creates schema, seeds data, and renders a page" do
    with_tmp_engine("spec_ui1.db") do |engine|
      html = SemanticUI::Render.render_page(engine, "home")
      html.includes?("Beagle Device Panel").should be_true
      html.includes?("Temperature").should be_true
      html.includes?("LED").should be_true
    end
  end

  it "reads and writes LED state" do
    with_tmp_engine("spec_ui2.db") do |engine|
      # initial led_state is off
      x = engine.read_text("led")
      (["on", "off"] & [x]).should eq([x]) # allow either if seed changes later
      engine.write_apply("led", {"value" => "true"}).should eq "on"
      engine.read_text("led").should eq "on"
      engine.write_apply("led", {"toggle" => "true"}).should eq "off"
      engine.read_text("led").should eq "off"
    end
  end

  it "reads temperature with unit" do
    with_tmp_engine("spec_ui3.db") do |engine|
      t = engine.read_text("temp_sensor")
      t.should match /°C$/
    end
  end

  it "errors for unknown entity" do
    with_tmp_engine("spec_ui4.db") do |engine|
      expect_raises(Exception) { engine.read_text("nope") }
    end
  end
end
