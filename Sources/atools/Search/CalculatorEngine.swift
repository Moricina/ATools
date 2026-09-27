import Foundation

/// Safe arithmetic evaluator for the search bar.
///
/// `NSExpression(format:)` raises Objective-C exceptions (uncatchable in Swift) for
/// half-typed input such as `1+`, `c++`, `wi-fi` or `100%`, and it performs integer
/// division (`7/2 == 3`). Since Layer 1 search runs on every keystroke, this engine uses
/// a small recursive-descent parser that simply returns nil for anything it can't parse.
public final class CalculatorEngine {
    public static let shared = CalculatorEngine()

    private init() {}

    public func evaluate(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return nil }

        // Must contain at least one operator or math function to be considered a calculation
        let mathOperators = CharacterSet(charactersIn: "+-*/%^×÷")
        let lower = trimmed.lowercased()
        let hasOperator = trimmed.rangeOfCharacter(from: mathOperators) != nil
        let hasMathWord = Parser.functions.keys.contains { lower.hasPrefix($0 + "(") }
        guard hasOperator || hasMathWord else { return nil }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }

        // Dates such as 2024-01-01 are far more likely to be file searches than subtraction.
        if trimmed.range(of: #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#, options: .regularExpression) != nil {
            return nil
        }

        var parser = Parser(Array(lower))
        guard let value = parser.parse(), value.isFinite else { return nil }
        return Self.format(value)
    }

    private static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return "\(Int64(value))"
        }
        return String(format: "%.10g", value)
    }

    /// Grammar:
    ///   expr   := term (('+' | '-') term)*
    ///   term   := power (('*' | '/' | '%') power)*
    ///   power  := unary ('^' power)?
    ///   unary  := ('+' | '-') unary | primary
    ///   primary:= number | func '(' expr ')' | '(' expr ')'
    private struct Parser {
        static let functions: [String: (Double) -> Double] = [
            "sqrt": { $0.squareRoot() },
            "sin": { sin($0) },
            "cos": { cos($0) },
            "tan": { tan($0) },
            "log": { log10($0) },
            "ln": { log($0) },
            "abs": { abs($0) }
        ]

        private let chars: [Character]
        private var index = 0

        init(_ chars: [Character]) {
            self.chars = chars
        }

        mutating func parse() -> Double? {
            guard let value = parseExpression() else { return nil }
            skipSpaces()
            return index == chars.count ? value : nil
        }

        private mutating func skipSpaces() {
            while index < chars.count, chars[index].isWhitespace { index += 1 }
        }

        private mutating func peek() -> Character? {
            skipSpaces()
            return index < chars.count ? chars[index] : nil
        }

        private mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = op == "+" ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        private mutating func parseTerm() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while let op = peek(), "*/%×÷".contains(op) {
                index += 1
                guard let rhs = parsePower() else { return nil }
                switch op {
                case "*", "×": lhs *= rhs
                case "/", "÷":
                    guard rhs != 0 else { return nil }
                    lhs /= rhs
                default:
                    guard rhs != 0 else { return nil }
                    lhs = lhs.truncatingRemainder(dividingBy: rhs)
                }
            }
            return lhs
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exponent = parsePower() else { return nil }
                return pow(base, exponent)
            }
            // `**` is accepted as an alias for `^`
            if peek() == "*", index + 1 < chars.count, chars[index + 1] == "*" {
                index += 2
                guard let exponent = parsePower() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        private mutating func parseUnary() -> Double? {
            if let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return op == "-" ? -value : value
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Double? {
            guard let c = peek() else { return nil }

            if c == "(" {
                index += 1
                guard let value = parseExpression(), peek() == ")" else { return nil }
                index += 1
                return value
            }

            if c.isLetter {
                var name = ""
                while index < chars.count, chars[index].isLetter {
                    name.append(chars[index])
                    index += 1
                }
                guard let fn = Parser.functions[name], peek() == "(" else { return nil }
                index += 1
                guard let arg = parseExpression(), peek() == ")" else { return nil }
                index += 1
                return fn(arg)
            }

            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            skipSpaces()
            // Hex literal: 0x1F
            if index + 1 < chars.count, chars[index] == "0", chars[index + 1] == "x" {
                var digits = ""
                var i = index + 2
                while i < chars.count, chars[i].isHexDigit {
                    digits.append(chars[i])
                    i += 1
                }
                guard !digits.isEmpty, let value = UInt64(digits, radix: 16) else { return nil }
                index = i
                return Double(value)
            }

            var literal = ""
            while index < chars.count, chars[index].isNumber || chars[index] == "." {
                guard chars[index].isASCII else { return nil }
                literal.append(chars[index])
                index += 1
            }
            return Double(literal)
        }
    }
}
