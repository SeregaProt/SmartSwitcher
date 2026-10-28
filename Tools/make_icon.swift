import AppKit

// Генератор иконки приложения SmartSwitcher: скруглённый квадрат с градиентом
// и символами раскладок «Я / A» (переключение RU↔EN). Сохраняет PNG 1024×1024.

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Фон-градиент (squircle).
let radius = size * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
path.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.85, alpha: 1),
])!
gradient.draw(in: rect, angle: -90)

// Кольцо-стрелка переключения.
let ring = NSBezierPath()
let center = NSPoint(x: size / 2, y: size / 2)
let r = size * 0.30
ring.appendArc(withCenter: center, radius: r, startAngle: 35, endAngle: 320)
ring.lineWidth = size * 0.045
NSColor.white.withAlphaComponent(0.28).setStroke()
ring.stroke()

func draw(_ text: String, at point: NSPoint, fontSize: CGFloat, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: color,
        .paragraphStyle: style,
    ]
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.size()
    s.draw(at: NSPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
}

// Символы раскладок.
draw("Я", at: NSPoint(x: size * 0.38, y: size * 0.56), fontSize: size * 0.30, color: .white)
draw("A", at: NSPoint(x: size * 0.62, y: size * 0.40), fontSize: size * 0.30, color: NSColor.white.withAlphaComponent(0.85))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("ошибка рендера\n", stderr)
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("сохранено: \(out)")
