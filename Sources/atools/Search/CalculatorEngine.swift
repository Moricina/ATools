import Foundation

public final class CalculatorEngine {
    public static let shared = CalculatorEngine()

    private init() {}

    public func evaluate(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Must contain at least one operator or math function to be considered a calculation
        let mathOperators = CharacterSet(charactersIn: "+-*/%^")
        let hasOperator = trimmed.rangeOfCharacter(from: mathOperators) != nil
        let hasMathWord = trimmed.lowercased().hasPrefix("sqrt(") ||
                          trimmed.lowercased().hasPrefix("sin(") ||
                          trimmed.lowercased().hasPrefix("cos(") ||
                          trimmed.lowercased().hasPrefix("tan(") ||
                          trimmed.lowercased().hasPrefix("log(")

        guard hasOperator || hasMathWord else { return nil }

        // Sanitize string for NSExpression
        var sanitized = trimmed
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")

        // Handle simple hex like 0x10
        if sanitized.contains("0x") || sanitized.contains("0X") {
            let components = sanitized.components(separatedBy: " ")
            var converted: [String] = []
            for comp in components {
                if comp.hasPrefix("0x") || comp.hasPrefix("0X"),
                   let val = Int(comp.dropFirst(2), radix: 16) {
                    converted.append("\(val)")
                } else {
                    converted.append(comp)
                }
            }
            sanitized = converted.joined(separator: " ")
        }

        let expr = NSExpression(format: sanitized)
        if let result = expr.expressionValue(with: nil, context: nil) as? NSNumber {
            let doubleVal = result.doubleValue
            if doubleVal.isNaN || doubleVal.isInfinite {
                return nil
            }
            if floor(doubleVal) == doubleVal && doubleVal < Double(Int64.max) && doubleVal > Double(Int64.min) {
                return "\(Int64(doubleVal))"
            } else {
                return String(format: "%.6g", doubleVal)
            }
        }
        return nil

    }
}
