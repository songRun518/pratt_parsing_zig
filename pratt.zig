const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var input = std.ArrayList(u8).init(allocator);
    defer input.deinit();

    try std.io.getStdIn().reader()
        .readUntilDelimiterArrayList(
        &input,
        '\n',
        std.math.maxInt(usize),
    );
    _ = input.pop();

    const result = try pratt_parsing(allocator, input.items);
    std.debug.print("{d}", .{result});
}

fn pratt_parsing(allocator: Allocator, input: []u8) !f64 {
    const tokens = try tokenize(input, allocator);
    var parser = Parser{
        .tokens = tokens,
        .allocator = allocator,
    };

    const ast = try parser.parse();
    const result = ast.eval();
    return result;
}

const TokenType = enum {
    number,
    plus,
    minus,
    star,
    slash,
    lparen,
    rparen,
    eof,
};

const Token = struct {
    type: TokenType,
    value: f64 = 0,
};

const Node = union(enum) {
    number: f64,
    prefix: struct {
        op: TokenType,
        right: *Node,
    },
    infix: struct {
        left: *Node,
        op: TokenType,
        right: *Node,
    },

    fn eval(self: *Node) f64 {
        return switch (self.*) {
            .number => |n| n,
            .prefix => |p| switch (p.op) {
                .minus => -p.right.eval(),
                else => unreachable,
            },
            .infix => |i| switch (i.op) {
                .plus => i.left.eval() + i.right.eval(),
                .minus => i.left.eval() - i.right.eval(),
                .star => i.left.eval() * i.right.eval(),
                .slash => i.left.eval() / i.right.eval(),
                else => unreachable,
            },
        };
    }
};

const Parser = struct {
    tokens: []Token,
    pos: usize = 0,
    allocator: Allocator,

    fn current(self: *Parser) Token {
        return if (self.pos < self.tokens.len) self.tokens[self.pos] else Token{ .type = .eof };
    }

    fn advance(self: *Parser) void {
        self.pos += 1;
    }

    fn expect(self: *Parser, expected: TokenType) !void {
        if (self.current().type != expected) {
            return error.UnexpectedToken;
        }
        self.advance();
    }

    fn parsePrefix(self: *Parser) !*Node {
        const token = self.current();
        switch (token.type) {
            .number => {
                self.advance();
                const node = try self.allocator.create(Node);
                node.* = .{ .number = token.value };
                return node;
            },
            .lparen => {
                self.advance();
                const expr = try self.parseExpression(0);
                try self.expect(.rparen);
                return expr;
            },
            .minus => {
                self.advance();
                const node = try self.allocator.create(Node);
                node.* = .{
                    .prefix = .{
                        .op = .minus,
                        .right = try self.parseExpression(70),
                    },
                };
                return node;
            },
            else => return error.UnexpectedToken,
        }
    }

    fn parseInfix(self: *Parser, left: *Node, token: Token) !*Node {
        self.advance();
        const node = try self.allocator.create(Node);
        node.* = .{
            .infix = .{
                .left = left,
                .op = token.type,
                .right = try self.parseExpression(self.getBindingPower(token.type).?.right),
            },
        };
        return node;
    }

    fn getBindingPower(self: *Parser, op: TokenType) ?struct { left: u8, right: u8 } {
        _ = self;
        return switch (op) {
            .plus, .minus => .{ .left = 50, .right = 51 },
            .star, .slash => .{ .left = 60, .right = 61 },
            .lparen => .{ .left = 80, .right = 0 },
            else => null,
        };
    }

    fn parseExpression(self: *Parser, rbp: u8) anyerror!*Node {
        var left = try self.parsePrefix();

        while (true) {
            const token = self.current();
            const bp = self.getBindingPower(token.type) orelse break;
            if (rbp >= bp.left) break;

            left = try self.parseInfix(left, token);
        }

        return left;
    }

    fn parse(self: *Parser) !*Node {
        return self.parseExpression(0);
    }
};

fn tokenize(input: []const u8, allocator: Allocator) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    var i: usize = 0;

    while (i < input.len) {
        const c = input[i];
        switch (c) {
            ' ' => i += 1,
            '+' => {
                try tokens.append(.{ .type = .plus });
                i += 1;
            },
            '-' => {
                try tokens.append(.{ .type = .minus });
                i += 1;
            },
            '*' => {
                try tokens.append(.{ .type = .star });
                i += 1;
            },
            '/' => {
                try tokens.append(.{ .type = .slash });
                i += 1;
            },
            '(' => {
                try tokens.append(.{ .type = .lparen });
                i += 1;
            },
            ')' => {
                try tokens.append(.{ .type = .rparen });
                i += 1;
            },
            '0'...'9', '.' => {
                const start = i;
                while (i < input.len and (std.ascii.isDigit(input[i]) or input[i] == '.')) : (i += 1) {}
                const num_str = input[start..i];
                const value = try std.fmt.parseFloat(f64, num_str);
                try tokens.append(.{ .type = .number, .value = value });
            },
            else => return error.InvalidCharacter,
        }
    }

    try tokens.append(.{ .type = .eof });
    return tokens.toOwnedSlice();
}
