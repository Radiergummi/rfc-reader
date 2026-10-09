import Foundation
import Testing

@testable import RFCKit

/// A drawing told by its shape (#297, #361): mostly lines, boxes and arrows, and not
/// mostly lines of words. Hand-written blocks in the shape of an RFC's.
@Suite("Drawing shape")
struct DrawingShapeTests {
  @Test(arguments: [
    """
    +--------+          +--------+
    | Client | -------> | Server |
    +--------+          +--------+
    """,
    """
     0                   1                   2
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |    Kind Field     |       Length Field    |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    """,
    """
    Sender                  Receiver
      |                         |
      |------- Request -------->|
      |<------ Reply -----------|
    """,
    """
    ┌──────┐     ┌──────┐
    │ Left │ ──> │ Right│
    └──────┘     └──────┘
    """,
  ])
  func `a drawing is a diagram`(artwork: String) {
    #expect(DrawingShape.looksLikeDrawing(artwork))
  }

  @Test(arguments: [
    """
    message   = start-line *( field CRLF ) CRLF [ body ]
    field     = field-name ":" OWS field-value OWS
    delimiter = "/" / "," / ";" / "=" / "<" / ">"
    """,
    """
    Example Record {
      Kind (8) = 2,
      Length (16),
      Value (..),
    }
    """,
    """
    GET /index.html HTTP/1.1
    Host: www.example.com
    Accept-Language: en-US
    """,
    """
    0x00 0x1f 0x2e 0x41 0x5b 0x60 0x7e 0x80
    """,
    """
    +-------+--------------------+-----------+
    | Value | Name               | Reference |
    +-------+--------------------+-----------+
    | 0     | Reserved           | [RFCxxxx] |
    | 1     | Echo Request       | [RFCxxxx] |
    | 2     | Echo Reply         | [RFCxxxx] |
    +-------+--------------------+-----------+
    """,
    """
    Value   Name              Reference
    -----   ---------------   ---------
    0       Reserved          [RFCxxxx]
    1       Echo Request      [RFCxxxx]
    """,
    "",
  ])
  func `text set as artwork is not a diagram`(artwork: String) {
    #expect(!DrawingShape.looksLikeDrawing(artwork))
  }
}
