import Foundation

/// Evaluates arithmetic for the harness's calculate tool. A small parser of its own, so a model's
/// expression can only ever do arithmetic. Whole numbers stay exact until they overflow.
struct Calculator {
    enum Failure: Error { case syntax, unknownFunction(String), domain }

    private enum Value {
        case whole(Int)
        case real(Double)

        var double: Double {
            switch self {
            case .whole(let i): return Double(i)
            case .real(let d): return d
            }
        }

        var text: String {
            switch self {
            case .whole(let i): return "\(i)"
            case .real(let d): return d == d.rounded() && abs(d) < 1e15 ? String(format: "%.0f", d) : "\(d)"
            }
        }
    }

    static func evaluate(_ expression: String) -> String {
        var parser = Calculator(characters: Array(expression.replacingOccurrences(of: ",", with: " , ")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")))
        do {
            let value = try parser.sum()
            parser.skipSpaces()
            guard parser.position == parser.characters.count else { throw Failure.syntax }
            return value.text
        } catch {
            return "Error: can't evaluate that. Use numbers, + - * / % ^, parentheses and powmod(a,b,m), gcd(a,b), lcm(a,b), comb(n,k), factorial(n), sqrt(x)."
        }
    }

    private let characters: [Character]
    private var position = 0

    private init(characters: [Character]) { self.characters = characters }

    private mutating func skipSpaces() {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
    }

    private mutating func accept(_ c: Character) -> Bool {
        skipSpaces()
        guard position < characters.count, characters[position] == c else { return false }
        position += 1
        return true
    }

    private mutating func sum() throws -> Value {
        var left = try product()
        while true {
            if accept("+") { left = Self.combine(left, try product(), Int.addingReportingOverflow, +) }
            else if accept("-") { left = Self.combine(left, try product(), Int.subtractingReportingOverflow, -) }
            else { return left }
        }
    }

    private mutating func product() throws -> Value {
        var left = try power()
        while true {
            if accept("*") {
                left = Self.combine(left, try power(), Int.multipliedReportingOverflow, *)
            } else if accept("/") {
                let right = try power()
                guard right.double != 0 else { throw Failure.domain }
                if case .whole(let a) = left, case .whole(let b) = right, a % b == 0 { left = .whole(a / b) }
                else { left = .real(left.double / right.double) }
            } else if accept("%") {
                let right = try power()
                guard right.double != 0 else { throw Failure.domain }
                if case .whole(let a) = left, case .whole(let b) = right { left = .whole(a % b) }
                else { left = .real(left.double.truncatingRemainder(dividingBy: right.double)) }
            } else {
                return left
            }
        }
    }

    private mutating func power() throws -> Value {
        let base = try unary()
        guard accept("^") else { return base }
        let exponent = try power()
        if case .whole(let b) = base, case .whole(let e) = exponent, e >= 0 {
            var result = 1
            for _ in 0..<min(e, 4096) {
                let (next, overflow) = result.multipliedReportingOverflow(by: b)
                if overflow { return .real(pow(Double(b), Double(e))) }
                result = next
            }
            return .whole(result)
        }
        return .real(pow(base.double, exponent.double))
    }

    private mutating func unary() throws -> Value {
        if accept("-") {
            switch try unary() {
            case .whole(let i): return .whole(-i)
            case .real(let d): return .real(-d)
            }
        }
        return try primary()
    }

    private mutating func primary() throws -> Value {
        if accept("(") {
            let value = try sum()
            guard accept(")") else { throw Failure.syntax }
            return value
        }
        skipSpaces()
        let start = position
        while position < characters.count, characters[position].isNumber || characters[position] == "." { position += 1 }
        if position > start {
            let text = String(characters[start..<position])
            if let whole = Int(text) { return .whole(whole) }
            if let real = Double(text) { return .real(real) }
            throw Failure.syntax
        }
        while position < characters.count, characters[position].isLetter { position += 1 }
        guard position > start else { throw Failure.syntax }
        let name = String(characters[start..<position]).lowercased()
        guard accept("(") else { throw Failure.syntax }
        var arguments = [try sum()]
        while accept(",") { arguments.append(try sum()) }
        guard accept(")") else { throw Failure.syntax }
        return try Self.call(name, arguments)
    }

    private static func combine(_ a: Value, _ b: Value, _ exact: (Int) -> (Int) -> (partialValue: Int, overflow: Bool),
                                _ approximate: (Double, Double) -> Double) -> Value {
        if case .whole(let x) = a, case .whole(let y) = b {
            let (result, overflow) = exact(x)(y)
            if !overflow { return .whole(result) }
        }
        return .real(approximate(a.double, b.double))
    }

    private static func whole(_ value: Value) throws -> Int {
        if case .whole(let i) = value { return i }
        throw Failure.domain
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    private static func call(_ name: String, _ arguments: [Value]) throws -> Value {
        switch (name, arguments.count) {
        case ("sqrt", 1):
            guard arguments[0].double >= 0 else { throw Failure.domain }
            let root = arguments[0].double.squareRoot()
            return root == root.rounded() ? .whole(Int(root)) : .real(root)
        case ("gcd", 2):
            return .whole(gcd(try whole(arguments[0]), try whole(arguments[1])))
        case ("lcm", 2):
            let (a, b) = (try whole(arguments[0]), try whole(arguments[1]))
            guard a != 0, b != 0 else { return .whole(0) }
            return .whole(abs(a / gcd(a, b) * b))
        case ("factorial", 1):
            let n = try whole(arguments[0])
            guard (0...20).contains(n) else { throw Failure.domain }
            return .whole((1...max(n, 1)).reduce(1, *))
        case ("comb", 2):
            let (n, k) = (try whole(arguments[0]), try whole(arguments[1]))
            guard n >= 0, (0...n).contains(k) else { throw Failure.domain }
            var result = 1.0
            for i in 0..<min(k, n - k) { result = result * Double(n - i) / Double(i + 1) }
            return .whole(Int(result.rounded()))
        case ("powmod", 3):
            var (base, exponent, modulus) = (try whole(arguments[0]), try whole(arguments[1]), try whole(arguments[2]))
            guard exponent >= 0, modulus > 0 else { throw Failure.domain }
            func multiply(_ a: Int, _ b: Int) -> Int {
                let product = a.multipliedFullWidth(by: b)
                return modulus.dividingFullWidth(product).remainder
            }
            var result = 1 % modulus
            base = ((base % modulus) + modulus) % modulus
            while exponent > 0 {
                if exponent & 1 == 1 { result = multiply(result, base) }
                base = multiply(base, base)
                exponent >>= 1
            }
            return .whole(result)
        default:
            throw Failure.unknownFunction(name)
        }
    }
}
