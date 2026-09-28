import Foundation
import AppKit

/// 轻量 Markdown 渲染器，用于把 GitHub Release 正文渲染成 NSAttributedString。
///
/// 系统自带的 `NSAttributedString(markdown:)` 只产出 NSPresentationIntent 结构标记，
/// 不生成字体/换行/颜色，无法直接给 NSTextView 用；这里针对 Release Notes 实际用到的
/// 语法子集（标题、无序/有序列表、粗体、斜体、行内代码、链接）自己排版。
enum MarkdownText {

    /// - Parameters:
    ///   - markdown: GitHub Release body 原文
    ///   - fontSize: 正文基准字号
    static func render(_ markdown: String, fontSize: CGFloat = 11) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let result = NSMutableAttributedString()
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue } // 段间距由 paragraphStyle 控制

            if let level = headingLevel(of: line) {
                let content = String(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                guard !content.isEmpty else { continue }
                // 1-2 级标题比正文大 2pt，3 级以下大 1pt，避免在 110pt 高的小窗里喧宾夺主。
                let size = fontSize + (level <= 2 ? 2 : 1)
                let style = NSMutableParagraphStyle()
                style.paragraphSpacingBefore = 6
                style.paragraphSpacing = 2
                style.lineHeightMultiple = 1.1
                result.append(NSAttributedString(string: content, attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: style
                ]))
            } else if let content = listItemContent(of: line) {
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 0
                style.headIndent = fontSize + 2
                style.paragraphSpacing = 3
                style.lineHeightMultiple = 1.1
                let bullet = NSMutableAttributedString(string: "• ", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style
                ])
                bullet.append(inline(content, font: baseFont, color: .labelColor))
                result.append(bullet)
            } else {
                let paragraph = NSMutableAttributedString(attributedString: inline(line, font: baseFont, color: .labelColor))
                let style = NSMutableParagraphStyle()
                style.paragraphSpacing = 4
                style.lineHeightMultiple = 1.1
                paragraph.addAttribute(.paragraphStyle, value: style,
                                       range: NSRange(location: 0, length: paragraph.length))
                result.append(paragraph)
            }
            result.append(NSAttributedString(string: "\n", attributes: [
                .font: baseFont, .foregroundColor: NSColor.labelColor
            ]))
        }

        if result.length == 0 {
            return NSAttributedString(string: markdown, attributes: [
                .font: baseFont, .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
        return result
    }

    // MARK: - 行级语法

    private static func headingLevel(of line: String) -> Int? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
        return level
    }

    /// 命中 `- ` / `* ` / `+ ` / `1. ` 时返回去掉标记后的正文。
    private static func listItemContent(of line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let content = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : content
        }
        // 有序列表：12. 内容（只匹配行首连续数字）
        var digits = 0
        for ch in line {
            if ch.isNumber { digits += 1 } else { break }
        }
        guard digits > 0, line.count > digits + 1 else { return nil }
        let idx = line.index(line.startIndex, offsetBy: digits)
        guard line[idx] == "." else { return nil }
        let after = line.index(after: idx)
        guard after < line.endIndex, line[after] == " " else { return nil }
        let content = String(line[line.index(after: after)...]).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }

    // MARK: - 行内语法

    private static func inline(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var plain = ""
        func flush() {
            guard !plain.isEmpty else { return }
            out.append(NSAttributedString(string: plain, attributes: [
                .font: font, .foregroundColor: color
            ]))
            plain = ""
        }

        var i = text.startIndex
        while i < text.endIndex {
            // 行内代码 `code`
            if text[i] == "`" {
                let after = text.index(after: i)
                if after < text.endIndex, let close = text[after...].firstIndex(of: "`"), close > after {
                    flush()
                    let codeFont = NSFont.monospacedSystemFont(ofSize: max(9, font.pointSize - 0.5), weight: .regular)
                    out.append(NSAttributedString(string: String(text[after..<close]), attributes: [
                        .font: codeFont, .foregroundColor: NSColor.secondaryLabelColor
                    ]))
                    i = text.index(after: close)
                    continue
                }
            }
            // 粗体 **text**
            if text[i...].hasPrefix("**") {
                let after = text.index(i, offsetBy: 2)
                if let close = text.range(of: "**", range: after..<text.endIndex) {
                    flush()
                    let bold = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
                    out.append(inline(String(text[after..<close.lowerBound]), font: bold, color: color))
                    i = close.upperBound
                    continue
                }
            }
            // 斜体 *text*
            if text[i] == "*" {
                let after = text.index(after: i)
                if after < text.endIndex, let close = text[after...].firstIndex(of: "*") {
                    flush()
                    let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    out.append(inline(String(text[after..<close]), font: italic, color: color))
                    i = text.index(after: close)
                    continue
                }
            }
            // 链接 [label](url)
            if text[i] == "[" {
                let labelStart = text.index(after: i)
                if labelStart < text.endIndex, let closeBracket = text[labelStart...].firstIndex(of: "]") {
                    let paren = text.index(after: closeBracket)
                    if paren < text.endIndex, text[paren] == "(",
                       let closeParen = text[text.index(after: paren)...].firstIndex(of: ")") {
                        flush()
                        let label = String(text[labelStart..<closeBracket])
                        let url = String(text[text.index(after: paren)..<closeParen])
                        out.append(NSAttributedString(string: label.isEmpty ? url : label, attributes: [
                            .font: font,
                            .foregroundColor: NSColor.controlAccentColor,
                            .underlineStyle: NSUnderlineStyle.single.rawValue,
                            .link: url
                        ]))
                        i = text.index(after: closeParen)
                        continue
                    }
                }
            }
            plain.append(text[i])
            i = text.index(after: i)
        }
        flush()
        return out
    }
}
