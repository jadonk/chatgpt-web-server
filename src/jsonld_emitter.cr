require "json"
require "./layout"

# Emit minimal schema.org JSON-LD for SEO/accessibility.
#
# Use alongside SVG so crawlers get structured meaning even though
# the visual output is 100% SVG.
module JsonLdEmitter
  extend self

  # Build a small WebPage JSON-LD document from a Layout::Page.
  def emit(page : Layout::Page) : String
    JSON.build do |j|
      j.object do
        j.field "@context", "https://schema.org"
        j.field "@type", "WebPage"
        j.field "name", page.title
        j.field "description", page.desc
        j.field "about" do
          j.array do
            collect_terms(page).each do |term|
              j.object do
                j.field "@type", "PropertyValue"
                j.field "name", term
              end
            end
          end
        end
      end
    end
  end

  private def collect_terms(page : Layout::Page) : Array(String)
    acc = [] of String
    gather(page.children, acc)
    acc
  end

  private def gather(nodes : Array(Layout::Node), acc : Array(String))
    nodes.each do |n|
      case n
      when Layout::Text
        acc << (n.aria_label || n.content)
      when Layout::Button
        acc << (n.aria_label || n.label)
      when Layout::Image
        acc << (n.alt || "image")
      when Layout::Stack
        gather(n.children, acc)
      end
    end
  end
end
