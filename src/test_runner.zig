const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .default, .level = .debug },
    },
};

const TestFn = std.builtin.TestFn;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer if (gpa.deinit() == .leak) unreachable;

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    // Get the name of the process:
    const process_name = args.next() orelse "?";
    // Parse optional test filter:
    const test_filter: ?[:0]const u8 = args.next();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    var arena_alloc = arena.allocator();

    var buffer: [2048]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&buffer);

    var tests: []const TestFn = builtin.test_functions;

    // Filter tests:
    if (test_filter) |filter| {
        try file_writer.interface.print("Run only tests contained \x1b[33m'{s}'\x1b[0m in the name.", .{filter});
        var arr = try arena_alloc.alloc(TestFn, builtin.test_functions.len);
        arr.len = 0;
        for (builtin.test_functions) |tst| {
            if (std.mem.containsAtLeast(u8, tst.name, 1, filter)) {
                arr.len += 1;
                arr[arr.len - 1] = tst;
            }
        }
        tests = arr;
    }

    if (try runAllTets(&arena, process_name, tests)) |report| {
        try writeReport(&arena, AnsiReporter{ .writer = &file_writer.interface }, report);
        try file_writer.interface.flush();
        if (report.failed_count != 0 or report.is_mem_leak) std.process.exit(1);
    }
}

/// Runs passed tests and builds the report. If the reporter is passed,
/// it's used to write the report on the fly.
/// Returns an aggregated report of the run tests.
fn runAllTets(arena: *std.heap.ArenaAllocator, process_name: []const u8, tests: []const TestFn) !?Report {
    const alloc = arena.allocator();
    if (tests.len == 0) {
        return null;
    }

    var report = Report{
        .process_name = process_name,
        .test_results = try alloc.alloc(TestResult, tests.len),
    };

    var total_timer: std.time.Timer = try std.time.Timer.start();
    var test_timer: std.time.Timer = try std.time.Timer.start();
    for (tests, 0..) |test_fn, idx| {
        const t = Test.wrap(test_fn);

        // ***** RUN TEST ***** //
        report.test_results[idx] = try t.run(arena, &test_timer);

        switch (report.test_results[idx]) {
            .passed => {
                report.passed_count += 1;
            },
            .failed => {
                report.failed_count += 1;
            },
            .skipped => {
                report.skipped_count += 1;
            },
        }
        report.is_mem_leak = report.is_mem_leak or report.test_results[idx].isMemoryLeak();
    }
    report.total_duration = Duration.fromNanos(total_timer.lap());

    return report;
}

fn writeReport(arena: *std.heap.ArenaAllocator, reporter: anytype, report: Report) !void {
    const alloc = arena.allocator();
    var grouped_tests: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(TestResult)) = .empty;
    for (report.test_results) |test_result| {
        const gop = try grouped_tests.getOrPut(alloc, test_result.tst().namespace);
        if (gop.found_existing) {
            try gop.value_ptr.append(alloc, test_result);
        } else {
            gop.value_ptr.* = .empty;
            try gop.value_ptr.append(alloc, test_result);
        }
    }

    try reporter.writeProcessName(report.process_name);
    var itr = grouped_tests.iterator();
    while (itr.next()) |group| {
        try reporter.writeNamespace(group.key_ptr.*);
        for (group.value_ptr.items) |test_result| {
            try reporter.writeTestName(test_result.tst().name);
            try reporter.writeTestResult(test_result);
        }
    }
    try reporter.writeSummary(
        report.passed_count,
        report.failed_count,
        report.skipped_count,
        report.total_duration,
        report.is_mem_leak,
    );
}

/// Meta information about a single test
const Test = struct {
    /// A name of the test
    name: []const u8 = undefined,
    /// A name of the module, where the test is created
    namespace: []const u8 = undefined,
    /// A builtin test representation, which contains a full name of the test,
    /// and a function with an implementation of the test.
    test_fn: TestFn,

    pub fn wrap(test_fn: TestFn) Test {
        var instance: Test = .{ .test_fn = test_fn };
        const names = getNames(test_fn);
        instance.namespace = names[0];
        instance.name = names[1];
        // instance.name = test_fn.name;
        return instance;
    }

    /// Runs the test and builds the report.
    fn run(self: Test, arena: *std.heap.ArenaAllocator, timer: *std.time.Timer) !TestResult {
        var test_result: TestResult = undefined;
        timer.reset();
        const result = self.test_fn.func();
        const duration = Duration.fromNanos(timer.read());

        const is_mem_leak = (std.testing.allocator_instance.deinit() == .leak);
        std.testing.allocator_instance = .{};

        if (result) |_| {
            test_result = .{
                .passed = Passed{ .tst = self, .duration = duration, .is_mem_leak = is_mem_leak },
            };
        } else |err| switch (err) {
            error.SkipZigTest => {
                test_result = TestResult{ .skipped = self };
            },
            else => {
                var str: []u8 = &.{};
                if (@errorReturnTrace()) |stack_trace| {
                    str = try arena.allocator().alloc(u8, 2048);
                    var fixed_writer = std.io.Writer.fixed(str);
                    // skip frame from the testing.zig:
                    const st = std.builtin.StackTrace{
                        .index = stack_trace.index - 1,
                        .instruction_addresses = stack_trace.instruction_addresses[1..],
                    };
                    try st.format(&fixed_writer);
                    try fixed_writer.flush();
                }
                test_result = TestResult{
                    .failed = .{
                        .tst = self,
                        .duration = duration,
                        .is_mem_leak = is_mem_leak,
                        .err = err,
                        .stack_trace = str,
                    },
                };
            },
        }
        return test_result;
    }
};

/// Split a full name of a test in two parts:
///  1. a namespace of the test;
///  2. a name of the test.
///
/// Possible templates of full test name are expected:
///  - "<namespace>.test.<test name>"
///  - "<namespace>.decltest.<test name>"
fn getNames(test_fn: TestFn) struct { []const u8, []const u8 } {
    if (std.mem.indexOf(u8, test_fn.name, ".test.")) |idx| {
        return .{ test_fn.name[0..idx], test_fn.name[idx + 6 ..] };
    } else if (std.mem.indexOf(u8, test_fn.name, ".decltest.")) |idx| {
        return .{ test_fn.name[0..idx], test_fn.name[idx + 10 ..] };
    } else {
        return .{ "", test_fn.name };
    }
}

/// Detailed information about a passed test
const Passed = struct {
    tst: Test,
    duration: Duration,
    is_mem_leak: bool,
};

/// Detailed information about a failed test
const Failed = struct {
    tst: Test,
    duration: Duration,
    err: anyerror,
    stack_trace: []const u8,
    is_mem_leak: bool,
};

/// The report about run a single test
pub const TestResult = union(enum) {
    passed: Passed,
    failed: Failed,
    skipped: Test,

    pub fn tst(self: TestResult) Test {
        return switch (self) {
            .passed => |result| result.tst,
            .failed => |result| result.tst,
            .skipped => |t| t,
        };
    }

    pub fn testDurationMs(self: TestResult) f64 {
        return switch (self) {
            .passed => |result| result.duration_ms,
            .failed => |result| result.duration_ms,
            .skipped => 0.0,
        };
    }

    pub fn isMemoryLeak(self: TestResult) bool {
        return switch (self) {
            .passed => |result| result.is_mem_leak,
            .failed => |result| result.is_mem_leak,
            .skipped => false,
        };
    }
};

/// The report about a tests run. Contains a name of the module with tests,
/// results for every run test, and counts of passed, failed, and skipped tests.
const Report = struct {
    process_name: []const u8,
    test_results: []TestResult,
    passed_count: u8 = 0,
    failed_count: u8 = 0,
    skipped_count: u8 = 0,
    total_duration: Duration = .zero,
    is_mem_leak: bool = false,
};

const Duration = struct {
    minutes: u6 = 0,
    seconds: u6 = 0,
    millis: u10 = 0,
    nanos: u30 = 0,

    pub const zero: Duration = .{};

    pub fn fromNanos(ns: u64) Duration {
        var result: Duration = .zero;
        result.addNs(ns);
        return result;
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        // try writer.print("{d}:{d}.{d}", .{ self.minutes, self.seconds, self.millis });
        if (self.minutes > 0) {
            try writer.print("{d}m ", .{self.minutes});
            if (self.seconds > 0)
                try writer.print("{d}s ", .{self.seconds});
            if (self.millis > 0)
                try writer.print("{d}ms ", .{self.millis});
            if (self.nanos > 0)
                try writer.print("{d}ns", .{self.nanos});

            return;
        }
        if (self.seconds > 0) {
            try writer.print("{d}.{d} seconds", .{ self.seconds, self.millis });
            return;
        }
        if (self.millis > 0) {
            try writer.print("{d} ms", .{self.millis});
            return;
        }

        try writer.print("> 1 ms", .{});
    }

    fn addNs(self: *Duration, count: u64) void {
        if (count == 0) return;
        self.nanos += @intCast(count % 1_000_000);
        self.addMillis(@intCast(count / 1_000_000));
    }

    fn addMillis(self: *Duration, count: u64) void {
        if (count == 0) return;
        self.millis += @intCast(count % 1_000);
        self.addSeconds(@intCast(count / 1_000));
    }

    fn addSeconds(self: *Duration, count: u64) void {
        if (count == 0) return;
        self.seconds += @intCast(count % 60);
        self.addMinutes(@intCast(count / 60));
    }

    fn addMinutes(self: *Duration, count: u6) void {
        if (count == 0) return;
        std.debug.assert(count < 60);
        self.minutes += count;
    }
};

/// Write the tests report as a colored text.
const AnsiReporter = struct {
    const Color = struct {
        const default = "";
        const red = "\x1b[31m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const purple = "\x1b[35m";
        const bold_green = "\x1b[1;32m";
        const bold_cyan = "\x1b[1;36m";
    };

    const esc = "\x1b[0m";

    writer: *std.io.Writer,

    pub fn writeProcessName(self: AnsiReporter, module_name: []const u8) anyerror!void {
        // move to the next line and cleanup output settings:
        const cleanup = "\r\n\x1b[0K";
        const border = "=" ** 60;
        try colorizeLine(self.writer, Color.bold_cyan, "{s}\n{s}\n{s}\n{s}", .{ cleanup, border, module_name, border });
    }

    pub fn writeNamespace(self: AnsiReporter, namespace: []const u8) anyerror!void {
        // cleanup output settings:
        const cleanup = "\x1b[0K";
        try colorizeLine(self.writer, Color.bold_cyan, "{s}{s}", .{
            cleanup,
            namespace,
        });
    }

    pub fn writeTestName(self: AnsiReporter, test_name: []const u8) anyerror!void {
        try colorize(self.writer, Color.bold_cyan, " - {s} ", .{test_name});
    }

    pub fn writeTestResult(self: AnsiReporter, test_result: TestResult) anyerror!void {
        switch (test_result) {
            .passed => |result| {
                try colorizeLine(
                    self.writer,
                    Color.green,
                    " PASSED in {f}",
                    .{result.duration},
                );
            },
            .failed => |result| {
                try colorizeLine(
                    self.writer,
                    Color.red,
                    " FAILED in {f}: {s}",
                    .{ result.duration, @errorName(result.err) },
                );
                try self.writer.writeAll(result.stack_trace);
            },
            .skipped => {
                try colorizeLine(self.writer, Color.yellow, " SKIPPED", .{});
            },
        }
        if (test_result.isMemoryLeak()) {
            try colorizeLine(self.writer, Color.purple, "   MEMORY LEAK DETECTED", .{});
        }
    }

    pub fn writeSummary(
        self: AnsiReporter,
        passed: u8,
        failed: u8,
        skipped: u8,
        total_duration: Duration,
        is_mem_leak: bool,
    ) anyerror!void {
        // move to the next line and cleanup output settings:
        const border = "=" ** 60;
        try colorize(
            self.writer,
            Color.bold_cyan,
            border ++ "\nTotal {d} tests were run in {f}: ",
            .{ passed + failed + skipped, total_duration },
        );
        if (passed > 0)
            try colorize(self.writer, Color.green, "{d} passed; ", .{passed});
        if (failed > 0)
            try colorize(self.writer, Color.red, "{d} failed; ", .{failed});
        if (skipped > 0)
            try colorize(self.writer, Color.yellow, "{d} skipped;", .{skipped});
        if (is_mem_leak)
            try colorize(self.writer, Color.purple, "MEMORY LEAK", .{});
        try colorizeLine(self.writer, Color.bold_cyan, "", .{});
    }

    fn colorize(
        writer: *std.io.Writer,
        comptime color: []const u8,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        try writer.writeAll(color);
        try writer.print(format, args);
        try writer.writeAll(esc);
    }

    inline fn colorizeLine(
        writer: *std.io.Writer,
        comptime color: []const u8,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        try colorize(writer, color, format, args);
        _ = try writer.write("\n");
    }
};
