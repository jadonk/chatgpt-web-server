require "spec"
require "../src/layout"
require "../src/svg_emitter"
require "../src/jsonld_emitter"

private def demo_page
  Layout::Page.new(
    Layout::Size.new(400.0, 200.0),
    "Demo Title",
    "Demo Desc",
    [
      Layout::Text.new(Layout::Point.new(20, 24), "Hello", 18),
      Layout::Stack.new(Layout::Point.new(10, 10), [
        Layout::Text.new(Layout::Point.new(5, 5), "T1", 12),
        Layout::Button.new(Layout::Point.new(5, 25), "Click", "/do", Layout::Size.new(80, 24)),
      ], 8.0),
      Layout::Image.new(Layout::Point.new(300, 20), "/favicon.ico", Layout::Size.new(32, 32), "icon"),
    ]
  )
end

describe "SvgEmitter" do
  it "emits an <svg> with title/desc and visible text" do
    svg = SvgEmitter.emit(demo_page)
    svg.should contain("<svg")
    svg.should contain("<title")
    svg.should contain(">Demo Title<")
    svg.should contain("<desc")
    svg.should contain(">Demo Desc<")
    svg.should contain(">Hello<")
  end

  it "composes relative coordinates through Stack (x=15,y=15 for inner text)" do
    svg = SvgEmitter.emit(demo_page)
    # Inner text T1 is at Stack(10,10) + Text(5,5) => (15,15)
    svg.should match(/<text[^>]*x=\"15(?:\.0+)?\"[^>]*y=\"15(?:\.0+)?\"/)
  end

  it "wraps buttons in <a> and uses role=button with a rect" do
    svg = SvgEmitter.emit(demo_page)
    svg.should contain("<a")
    svg.should contain("role=\"button\"")
    svg.should contain("<rect")
    svg.should contain(">Click<")
  end

  it "preserves DOM order for reading order (Hello before T1)" do
    svg = SvgEmitter.emit(demo_page)
    svg.includes?("Hello").should be_true
    svg.includes?(">T1<").should be_true
    idx_hello = svg.index("Hello").not_nil!
    idx_t1    = svg.index(">T1<").not_nil!
    (idx_hello < idx_t1).should be_true
  end
end

describe "JsonLdEmitter" do
  it "emits WebPage context with name/description" do
    json = JsonLdEmitter.emit(demo_page)
    json.should contain("\"@context\":\"https://schema.org\"")
    json.should contain("\"@type\":\"WebPage\"")
    json.should contain("\"name\":\"Demo Title\"")
    json.should contain("\"description\":\"Demo Desc\"")
  end

  it "collects about terms from text/button/image" do
    json = JsonLdEmitter.emit(demo_page)
    json.should contain("\"about\"")
    json.should contain("\"name\":\"Hello\"")
    json.should contain("\"name\":\"Click\"")
    json.should contain("\"name\":\"icon\"")
  end
end
