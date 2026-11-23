import AppKit
import CoreText
import ImageIO

// Measurements in points, using the original A4 proposal and US Letter invoice.
struct LetterLayout {
    struct Block {
        var text: String
        var size: CGFloat = 11
        var bold = false
        var band = false
        var right = false
        var after: CGFloat = 3
        var pageBreak = false
        var header = false
        var footer = false
        var terms = false
        var termsStart = false
        var centered = false
    }
    let invoice: Bool
    let footer: [String]
    var font = LetterFont.arial
    var logo: Data?
    var style = DocumentStyle()
    private(set) var blocks: [Block] = []
    private var width: CGFloat { invoice ? 612 : 595 }
    private var height: CGFloat { invoice ? 792 : 842 }
    private var bodyWidth: CGFloat { width - 126 }

    mutating func add(_ text: String, size: CGFloat = 11, bold: Bool = false, band: Bool = false, right: Bool = false, after: CGFloat = 3) {
        blocks.append(Block(text: text, size: size == 11 && !band ? CGFloat(style.bodySize) : size, bold: bold, band: band, right: right, after: after))
    }
    mutating func breakPage() { blocks.append(Block(text: "", pageBreak: true)) }
    mutating func addHeader(_ text: String) {
        blocks.append(Block(text: text, size: 12, bold: true, after: 30, header: true))
    }
    mutating func addTerms(title: String, text: String) {
        blocks.append(Block(text: "", pageBreak: true, termsStart: true))
        blocks.append(Block(text: title, size: CGFloat(style.termsSize + 2), bold: true, after: 8, terms: true))
        blocks.append(Block(text: text, size: CGFloat(style.termsSize), terms: true))
    }
    private func family(_ block: Block) -> LetterFont {
        if block.header { return style.headerFont ?? font }
        if block.footer { return style.footerFont ?? font }
        if block.terms { return style.termsFont ?? font }
        if block.band { return style.phaseFont ?? font }
        return font
    }
    mutating func letterhead(identity: String, contact: String) {
        let lines = InlineText.lines(contact)
        for (i, line) in lines.enumerated() {
            let mark = i == lines.count - 1 && logo == nil ? identity : ""
            blocks.append(Block(text: "\t" + mark + "\t" + line, size: 8, after: i == lines.count - 1 ? 42 : 0, header: true))
        }
    }
    private func attributed(_ block: Block) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = block.centered ? .center : (block.right ? .right : .left)
        style.tabStops = block.header ? [NSTextTab(textAlignment: .right, location: 266), NSTextTab(textAlignment: .left, location: 278)] : [NSTextTab(textAlignment: .right, location: bodyWidth - 3)]
        let font = NSFont(name: family(block).face(bold: block.bold), size: block.size) ?? NSFont.systemFont(ofSize: block.size)
        return InlineText.attributed(block.text, attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: style])
    }

    func pdfData() throws -> Data {
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw CocoaError(.fileWriteUnknown) }
        var pageNumber = 0
        var y: CGFloat = 0
        func begin() {
            context.beginPDFPage(nil)
            pageNumber += 1
            y = height - (pageNumber == 1 ? 79 : 65)
        }
        func finish() {
            func draw(_ block: Block, in rect: CGRect) {
                let setter = CTFramesetterCreateWithAttributedString(attributed(block))
                CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil), context)
            }
            let third = bodyWidth / 3
            for (index, value) in footer.enumerated() {
                let block = Block(text: value, size: 8, right: index == 2, footer: true, centered: index == 1)
                draw(block, in: CGRect(x: 70 + CGFloat(index) * third, y: 6, width: third, height: 66))
            }
            if style.pageNumbers {
                draw(Block(text: String(pageNumber), size: 8, right: true, footer: true),
                     in: CGRect(x: 70, y: 74, width: bodyWidth, height: 13))
            }
            context.endPDFPage()
        }
        begin()
        if let logo, let source = CGImageSourceCreateWithData(logo as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let scale = min(268 / CGFloat(image.width), 50 / CGFloat(image.height))
            let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
            context.draw(image, in: CGRect(x: 70 + 268 - w, y: y - 45, width: w, height: h))
        }
        var column = 0
        var columnTop = y
        for block in blocks {
            if block.pageBreak { finish(); begin(); column = 0; columnTop = y; continue }
            let columns = block.terms && style.twoColumns
            let lineWidth = columns ? (bodyWidth - 20) / 2 : bodyWidth
            func advance() {
                if columns && column == 0 { column = 1; y = columnTop }
                else { finish(); begin(); column = 0; columnTop = y }
            }
            let string = attributed(block)
            let setter = CTFramesetterCreateWithAttributedString(string)
            var offset = 0
            while offset < string.length {
                let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: offset, length: 0), nil, CGSize(width: lineWidth, height: .greatestFiniteMagnitude), nil)
                let needed = ceil(size.height) + 3
                let fitsFreshPage = needed < height - 185
                let minimum = !columns && fitsFreshPage ? needed + (block.band ? 34 : 0) : block.size * 2
                if y < 99 + minimum { advance() }
                let used = min(needed, y - 94)
                let rect = CGRect(x: 70 + CGFloat(column) * (lineWidth + 20), y: y-used, width: lineWidth, height: used)
                if block.band && style.phase != "Plain" {
                    if style.phase == "Shaded band" { context.setFillColor(gray: 0.87, alpha: 1); context.fill(rect) }
                    context.setFillColor(gray: 0, alpha: 1); context.fill(CGRect(x: 70, y: rect.minY, width: bodyWidth, height: 1))
                }
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), CGPath(rect: rect, transform: nil), nil)
                let count = CTFrameGetVisibleStringRange(frame).length
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                CTFrameDraw(frame, context)
                offset += count
                y -= used + block.after
            }
        }
        finish(); context.closePDF()
        return data as Data
    }
}

extension LetterLayout {
    func wordData() throws -> Data {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        func write(_ path: String, _ xml: String) throws {
            let url = temp.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: url)
        }
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let rels = "http://schemas.openxmlformats.org/package/2006/relationships"
        func escape(_ text: String) -> String {
            String(text.unicodeScalars.filter { $0.value >= 32 && $0.value != 0xFFFE && $0.value != 0xFFFF })
                .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var logoRun = ""
        var imageRel = ""
        if let logo, let rep = NSBitmapImageRep(data: logo), rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            let media = temp.appendingPathComponent("word/media")
            try fm.createDirectory(at: media, withIntermediateDirectories: true)
            try logo.write(to: media.appendingPathComponent("logo.png"))
            let scale = min(268 / Double(rep.pixelsWide), 50 / Double(rep.pixelsHigh))
            let cx = Int(Double(rep.pixelsWide) * scale * 12700)
            let cy = Int(Double(rep.pixelsHigh) * scale * 12700)
            imageRel = "<Relationship Id=\"logo\" Type=\"\(r)/image\" Target=\"media/logo.png\"/>"
            logoRun = """
            <w:r><w:drawing xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><wp:anchor simplePos="0" relativeHeight="0" behindDoc="1" locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="margin"><wp:posOffset>\(268*12700-cx)</wp:posOffset></wp:positionH><wp:positionV relativeFrom="paragraph"><wp:posOffset>\(45*12700-cy)</wp:posOffset></wp:positionV><wp:extent cx="\(cx)" cy="\(cy)"/><wp:wrapNone/><wp:docPr id="1" name="Letterhead"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="Logo"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="logo"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>
            """
        }
        let twoColumnTerms = style.twoColumns && blocks.contains { $0.termsStart }
        let pageSettings = "<w:pgSz w:w=\"\(Int(width*20))\" w:h=\"\(Int(height*20))\"/><w:pgMar w:top=\"1500\" w:left=\"1400\" w:right=\"1120\" w:bottom=\"1800\" w:footer=\"650\"/>"
        func p(_ block: Block) -> String {
            if block.termsStart && twoColumnTerms {
                return "<w:p><w:pPr><w:sectPr><w:footerReference w:type=\"default\" r:id=\"footer\"/>" + pageSettings + "</w:sectPr></w:pPr></w:p>"
            }
            if block.pageBreak { return #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# }
            let tabs = block.header ? #"<w:tab w:val="right" w:pos="5320"/><w:tab w:val="left" w:pos="5560"/>"# : "<w:tab w:val=\"right\" w:pos=\"\(Int((bodyWidth-3)*20))\"/>"
            var band = block.band ? #"<w:keepNext/><w:pBdr><w:bottom w:val="single" w:sz="8" w:color="000000"/></w:pBdr><w:shd w:fill="DDDDDD"/>"# : ""
            if style.phase != "Shaded band" { band = band.replacingOccurrences(of: #"<w:shd w:fill="DDDDDD"/>"#, with: "") }
            if style.phase == "Plain" && block.band { band = "<w:keepNext/>" }
            let drawing = block.header ? logoRun : ""
            if block.header { logoRun = "" }
            let alignment = block.centered ? "center" : (block.right ? "right" : "left")
            let font = escape(family(block).rawValue).replacingOccurrences(of: "\"", with: "&quot;")
            let runs = InlineText.runs(block.text).map { span in
                let content = span.text.components(separatedBy: .newlines).map { line in
                    line.components(separatedBy: "\t").map { "<w:t xml:space=\"preserve\">\(escape($0))</w:t>" }.joined(separator: "<w:tab/>")
                }.joined(separator: "<w:br/>")
                let properties = InlineText.properties(span.mask | (block.bold ? 1 : 0))
                return "<w:r><w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\"/>\(properties)<w:sz w:val=\"\(Int(block.size*2))\"/></w:rPr>\(content)</w:r>"
            }.joined()
            return """
            <w:p><w:pPr>\(band)<w:tabs>\(tabs)</w:tabs><w:spacing w:before="0" w:after="\(Int(block.after*20))"/><w:jc w:val="\(alignment)"/></w:pPr>\(drawing)\(runs)</w:p>
            """
        }
        try write("[Content_Types].xml", #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="png" ContentType="image/png"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>"#)
        try write("_rels/.rels", "<Relationships xmlns=\"\(rels)\"><Relationship Id=\"r1\" Type=\"\(r)/officeDocument\" Target=\"word/document.xml\"/></Relationships>")
        try write("word/_rels/document.xml.rels", "<Relationships xmlns=\"\(rels)\"><Relationship Id=\"footer\" Type=\"\(r)/footer\" Target=\"footer1.xml\"/>\(imageRel)</Relationships>")
        let fullWidth = Int(bodyWidth * 20)
        let third = fullWidth / 3
        let widths = [third, fullWidth - 2 * third, third]
        let cells = footer.enumerated().map { i, value in
            let block = Block(text: value, size: 8, right: i == 2, after: 0, footer: true, centered: i == 1)
            return "<w:tc><w:tcPr><w:tcW w:w=\"\(widths[i])\" w:type=\"dxa\"/></w:tcPr>" + p(block) + "</w:tc>"
        }.joined()
        let number = style.pageNumbers ? p(Block(text: "PAGE_NUMBER", size: 8, right: true, after: 2, footer: true))
            .replacingOccurrences(of: "<w:r><w:rPr>", with: "<w:fldSimple w:instr=\"PAGE\"><w:r><w:rPr>")
            .replacingOccurrences(of: ">PAGE_NUMBER</w:t></w:r>", with: ">1</w:t></w:r></w:fldSimple>") : ""
        let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        try write("word/footer1.xml", """
            <w:ftr xmlns:w="\(w)">\(number)<w:tbl><w:tblPr><w:tblW w:w="\(fullWidth)" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>\(grid)</w:tblGrid><w:tr>\(cells)</w:tr></w:tbl><w:p/></w:ftr>
            """)
        try write("word/document.xml", """
            <w:document xmlns:w="\(w)" xmlns:r="\(r)"><w:body>\(blocks.map(p).joined())<w:sectPr><w:footerReference w:type="default" r:id="footer"/>\(pageSettings)\(twoColumnTerms ? "<w:cols w:num=\"2\" w:space=\"400\"/>" : "")</w:sectPr></w:body></w:document>
            """)
        let archive = temp.appendingPathComponent("export.docx")
        let zipTask = Process()
        zipTask.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipTask.currentDirectoryURL = temp
        zipTask.arguments = ["-q", "-r", archive.path, "[Content_Types].xml", "_rels", "word"]
        try zipTask.run()
        zipTask.waitUntilExit()
        guard zipTask.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return try Data(contentsOf: archive)
    }
}
