require "xml"
require "./layout"

# XML-driven SVG emitter (no string concatenation).
module SvgEmitter
  extend self

  def emit(page : Layout::Page) : String
    XML.build(indent: "  ") do |xml|
      xml.element("svg",
        {"xmlns"           => "http://www.w3.org/2000/svg",
         "xmlns:xlink"     => "http://www.w3.org/1999/xlink",
         "role"            => "img",
         "aria-labelledby" => "title desc",
         "width"           => page.size.w.to_i.to_s,
         "height"          => page.size.h.to_i.to_s}
      ) do
        xml.element("title", {"id" => "title"}) { xml.text page.title }
        xml.element("desc", {"id" => "desc"}) { xml.text page.desc }
        draw_children(xml, page.children, ox: 0.0, oy: 0.0)
      end
    end
  end

  private def draw_children(xml, nodes : Array(Layout::Node), *, ox : Float64, oy : Float64)
    nodes.each do |n|
      case n
      when Layout::Text
        xml.comment "text: #{n.aria_label || n.content}"
        xml.element("text", {
          "x" => (ox + n.at.x).to_s, "y" => (oy + n.at.y).to_s,
          "font-size" => n.size.to_s,
        }) { xml.text n.content }
      when Layout::Button
        xml.comment "button: #{n.aria_label || n.label}"
        xml.element("a", {"xlink:href" => n.href}) do
          xml.element("g", {
            "role"         => "button",
            "tabindex"     => "0",
            "aria-pressed" => (n.pressed ? "true" : "false"),
            "aria-label"   => (n.aria_label || n.label),
          }) do
            x = ox + n.at.x; y = oy + n.at.y
            xml.element("rect", {
              "x" => x.to_s, "y" => y.to_s,
              "rx" => "10", "ry" => "10",
              "width" => n.box.w.to_s, "height" => n.box.h.to_s,
              "fill" => "#ffffff", "stroke" => "#e5e7eb",
            })
            # Vertically center-ish the label
            xml.element("text", {
              "x" => (x + 12).to_s, "y" => (y + n.box.h/2 + 5).to_s,
              "font-size" => "14",
            }) { xml.text n.label }
          end
        end
      when Layout::Image
        xml.comment "image: #{n.alt || n.href}"
        xml.element("image", {
          "x" => (ox + n.at.x).to_s, "y" => (oy + n.at.y).to_s,
          "width" => n.box.w.to_s, "height" => n.box.h.to_s,
          "xlink:href" => n.href,
        })
      when Layout::Stack
        xml.comment "stack start"
        # Translate children by this stack's origin.
        draw_children(xml, n.children, ox: ox + n.at.x, oy: oy + n.at.y)
        xml.comment "stack end"
      end
    end
  end
end
