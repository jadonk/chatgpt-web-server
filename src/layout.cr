# Typed, minimal layout primitives for SVG emission.
# Coordinates are *relative to the parent container's origin*.
# The Page's origin (0,0) is the top-left of the SVG viewport.
# Units are CSS pixels for now (a unit system can be layered later).
#
# Reading order == DOM order: place nodes in the order you want screen
# readers to traverse them. Accessibility metadata is carried on nodes
# and emitted into <title>/<desc> or ARIA attributes as appropriate.
module Layout
  # A 2D coordinate in CSS pixels.
  record Point, x : Float64, y : Float64

  # A width/height in CSS pixels.
  record Size, w : Float64, h : Float64

  # Base node. All positions are *relative* to the parent origin.
  abstract class Node
    getter at : Point

    def initialize(@at : Point); end
  end

  # A container that translates its children by `at`.
  class Stack < Node
    getter gap : Float64
    getter children : Array(Node)

    def initialize(at : Point, @children : Array(Node), @gap : Float64 = 8.0)
      super(at)
    end
  end

  # Text content; emitted as <text> so it remains searchable/indexable.
  class Text < Node
    getter content : String
    getter size : Float64
    getter aria_label : String?

    def initialize(at : Point, @content : String, @size : Float64 = 16.0, @aria_label : String? = nil)
      super(at)
    end
  end

  # A clickable region rendered as <a><g role="button" ...><rect/><text/></g></a>.
  class Button < Node
    getter label : String
    getter href : String # GET for now; WASM can POST later
    getter box : Size
    getter pressed : Bool
    getter aria_label : String?

    def initialize(at : Point, @label : String, @href : String, @box : Size, @pressed : Bool = false, @aria_label : String? = nil)
      super(at)
    end
  end

  # Raster/vector image reference. Keep <text> for true text; use Image for icons/photos.
  class Image < Node
    getter href : String
    getter box : Size
    getter alt : String?

    def initialize(at : Point, @href : String, @box : Size, @alt : String? = nil)
      super(at)
    end
  end

  # A single page to emit as SVG.
  class Page
    getter size : Size
    getter title : String
    getter desc : String
    getter children : Array(Node)

    def initialize(@size : Size, @title : String, @desc : String, @children : Array(Node) = [] of Node)
    end
  end
end
