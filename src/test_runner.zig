const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .default, .level = .debug },
    },
};

const TestFn = std.builtin.TestFn;

// TODO: add doc about how to use it, and how to filter tests
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer if (gpa.deinit() == .leak) unreachable;

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    // skip the program name:
    _ = args.next();
    // Parse optional test filter:
    const test_filter: ?[:0]const u8 = args.next();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    var arena_alloc = arena.allocator();

    var writer = std.io.getStdOut().writer();
    var any_writer = writer.any();
    const reporter = TxtReporter.reporter(&any_writer);
    var tests: []const TestFn = builtin.test_functions;

    // Filter tests:
    if (test_filter) |filter| {
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

    const print_report_on_run_tests = true;
    if (print_report_on_run_tests) {
        if (try Report.build(arena_alloc, tests, reporter)) |report| {
            if (report.failed_count != 0 or report.is_mem_leak) std.process.exit(1);
        }
    } else {
        if (try Report.build(arena_alloc, tests, null)) |report| {
            try reporter.write(report);
            if (report.failed_count != 0 or report.is_mem_leak) std.process.exit(1);
        }
    }
}

/// Meta information about a single test
const Test = struct {
    /// The name of the test
    name: []const u8 = undefined,
    /// The name of the module, where the test is created
    module_name: []const u8 = undefined,
    /// The builtin test representation, which contains the full name of the test,
    /// and the function with its implementation
    test_fn: TestFn,

    pub fn wrap(test_fn: TestFn) Test {
        var instance: Test = .{ .test_fn = test_fn };
        const names = get_names(test_fn);
        instance.module_name = names[0];
        instance.name = names[1];
        // instance.name = test_fn.name;
        return instance;
    }

    /// Runs the test and builds the report.
    fn run(self: Test, alloc: std.mem.Allocator, timer: *std.time.Timer) !TestResult {
        var report: TestResult = undefined;
        timer.reset();
        const result = self.test_fn.func();
        const duration_ms = nanos2ms(timer.read());

        const is_mem_leak = (std.testing.allocator_instance.deinit() == .leak);
        std.testing.allocator_instance = .{};

        if (result) |_| {
            report = TestResult{
                .passed = Passed{ .tst = self, .duration_ms = duration_ms, .is_mem_leak = is_mem_leak },
            };
        } else |err| switch (err) {
            error.SkipZigTest => {
                report = TestResult{ .skipped = self };
            },
            else => {
                var str: []u8 = &.{};
                if (@errorReturnTrace()) |stack_trace| {
                    str = try alloc.alloc(u8, 2048);
                    var buf_writer = std.io.fixedBufferStream(str);
                    // skip frame from the testing.zig:
                    const st = std.builtin.StackTrace{
                        .index = stack_trace.index - 1,
                        .instruction_addresses = stack_trace.instruction_addresses[1..],
                    };
                    try st.format("", .{}, buf_writer.writer());
                }
                report = TestResult{
                    .failed = .{
                        .tst = self,
                        .duration_ms = duration_ms,
                        .is_mem_leak = is_mem_leak,
                        .err = err,
                        .stack_trace = str,
                    },
                };
            },
        }
        return report;
    }
};

inline fn get_names(test_fn: TestFn) struct { []const u8, []const u8 } {
    if (std.mem.indexOf(u8, test_fn.name, ".test.")) |idx| {
        return .{ test_fn.name[0..idx], test_fn.name[idx + 6 ..] };
    } else if (std.mem.indexOf(u8, test_fn.name, ".decltest.")) |idx| {
        return .{ test_fn.name[0..idx], test_fn.name[idx + 10 ..] };
    } else if (std.mem.indexOfScalar(u8, test_fn.name, '.')) |idx| {
        return .{ test_fn.name[0..idx], test_fn.name[idx + 1 ..] };
    } else {
        return .{ "TESTS", test_fn.name };
    }
}

/// Detailed information about a passed test
const Passed = struct {
    tst: Test,
    duration_ms: f64,
    is_mem_leak: bool,
};

/// Detailed information about a failed test
const Failed = struct {
    tst: Test,
    duration_ms: f64,
    err: anyerror,
    stack_trace: []const u8,
    is_mem_leak: bool,
};

/// The report about run a single test
pub const TestResult = union(enum) {
    passed: Passed,
    failed: Failed,
    skipped: Test,

    pub inline fn testName(self: TestResult) []const u8 {
        return switch (self) {
            .passed => |result| result.tst.name,
            .failed => |result| result.tst.name,
            .skipped => |tst| tst.name,
        };
    }

    pub inline fn testDurationMs(self: TestResult) f64 {
        return switch (self) {
            .passed => |result| result.duration_ms,
            .failed => |result| result.duration_ms,
            .skipped => 0.0,
        };
    }

    pub inline fn isMemoryLeak(self: TestResult) bool {
        return switch (self) {
            .passed => |result| result.is_mem_leak,
            .failed => |result| result.is_mem_leak,
            .skipped => false,
        };
    }
};

/// The report about tests run. Contains the name of the module with tests,
/// test reports for every run test, and counts of passed, failed, and skipped tests.
const Report = struct {
    alloc: std.mem.Allocator,
    module_name: []const u8,
    test_results: []TestResult,
    passed_count: u8 = 0,
    failed_count: u8 = 0,
    skipped_count: u8 = 0,
    total_duration_ms: f64 = 0.0,
    is_mem_leak: bool = false,

    /// Runs passed tests and builds the report. If the reporter is passed,
    /// used it to build the report on the fly, or just collects the information.
    pub fn build(alloc: std.mem.Allocator, tests: []const TestFn, reporter: ?AnyReporter) !?Report {
        if (tests.len == 0) {
            return null;
        }

        const names = get_names(tests[0]);
        var report = Report{
            .alloc = alloc,
            .module_name = names[0],
            .test_results = try alloc.alloc(TestResult, tests.len),
        };

        if (reporter) |r| {
            try r.writeModuleName(report.module_name);
        }

        var total_timer: std.time.Timer = try std.time.Timer.start();
        var test_timer: std.time.Timer = try std.time.Timer.start();
        for (tests, 0..) |test_fn, idx| {
            const t = Test.wrap(test_fn);

            if (reporter) |r| {
                try r.writeTestName(t.name);
            }

            // ***** RUN TEST ***** //
            report.test_results[idx] = try t.run(alloc, &test_timer);

            if (reporter) |r| {
                try r.writeTestResult(report.test_results[idx]);
            }

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
        report.total_duration_ms = nanos2ms(total_timer.lap());

        if (reporter) |r| {
            try r.writeSummary(
                report.passed_count,
                report.failed_count,
                report.skipped_count,
                report.total_duration_ms,
                report.is_mem_leak,
            );
        }
        return report;
    }
};

/// Abstract report to write result of tests run.
const AnyReporter = struct {
    ptr: *anyopaque,
    writeModuleNameFn: *const fn (ptr: *anyopaque, module_name: []const u8) anyerror!void,
    writeTestNameFn: *const fn (ptr: *anyopaque, test_name: []const u8) anyerror!void,
    writeTestResultFn: *const fn (ptr: *anyopaque, result: TestResult) anyerror!void,
    writeSummaryFn: *const fn (
        ptr: *anyopaque,
        passed: u8,
        failed: u8,
        skipped: u8,
        total_duration_ms: f64,
        is_mem_leak: bool,
    ) anyerror!void,

    pub fn write(self: AnyReporter, report: Report) !void {
        try self.writeModuleName(report.module_name);
        for (report.test_results) |test_result| {
            try self.writeTestName(test_result.testName());
            try self.writeTestResult(test_result);
        }
        try self.writeSummary(
            report.passed_count,
            report.failed_count,
            report.skipped_count,
            report.total_duration_ms,
            report.is_mem_leak,
        );
    }

    pub fn writeModuleName(self: AnyReporter, module_name: []const u8) anyerror!void {
        try self.writeModuleNameFn(self.ptr, module_name);
    }

    pub fn writeTestName(self: AnyReporter, test_name: []const u8) anyerror!void {
        try self.writeTestNameFn(self.ptr, test_name);
    }

    pub fn writeTestResult(self: AnyReporter, result: TestResult) anyerror!void {
        try self.writeTestResultFn(self.ptr, result);
    }

    pub fn writeSummary(
        self: AnyReporter,
        passed: u8,
        failed: u8,
        skipped: u8,
        total_duration_ms: f64,
        is_mem_leak: bool,
    ) anyerror!void {
        try self.writeSummaryFn(self.ptr, passed, failed, skipped, total_duration_ms, is_mem_leak);
    }
};

inline fn nanos2ms(nanos: u64) f64 {
    return @as(f64, @floatFromInt(nanos)) / 1000_000.0;
}

/// Write the tests report as a colored text.
const TxtReporter = struct {
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

    const border = "=" ** 60;

    pub fn reporter(writer: *std.io.AnyWriter) AnyReporter {
        return .{
            .ptr = writer,
            .writeModuleNameFn = TxtReporter.writeHeader,
            .writeTestNameFn = TxtReporter.writeTestName,
            .writeTestResultFn = TxtReporter.writeTestResult,
            .writeSummaryFn = TxtReporter.writeSummary,
        };
    }

    fn writeHeader(ptr: *anyopaque, module_name: []const u8) anyerror!void {
        const writer: *std.io.AnyWriter = @ptrCast(@alignCast(ptr));
        // move to the next line and cleanup output settings:
        const cleanup = "\r\n\x1b[0K";
        try colorizeLine(writer, Color.bold_cyan, "{s}\n{s}\n\t\t{s}\n{s}", .{ cleanup, border, module_name, border });
    }

    fn writeTestName(ptr: *anyopaque, test_name: []const u8) anyerror!void {
        const writer: *std.io.AnyWriter = @ptrCast(@alignCast(ptr));
        try colorize(writer, Color.bold_cyan, " - {s} \n", .{test_name});
    }

    fn writeTestResult(ptr: *anyopaque, test_result: TestResult) anyerror!void {
        const writer: *std.io.AnyWriter = @ptrCast(@alignCast(ptr));
        switch (test_result) {
            .passed => |result| {
                try colorizeLine(
                    writer,
                    Color.green,
                    "   PASSED in {d} ms",
                    .{result.duration_ms},
                );
            },
            .failed => |result| {
                try colorizeLine(
                    writer,
                    Color.red,
                    "   FAILED in {d} ms: {s}",
                    .{ result.duration_ms, @errorName(result.err) },
                );
                try writer.writeAll(result.stack_trace);
            },
            .skipped => {
                try colorizeLine(writer, Color.yellow, "   SKIPPED", .{});
            },
        }
        if (test_result.isMemoryLeak()) {
            try colorizeLine(writer, Color.purple, "   MEMORY LEAK DETECTED", .{});
        }
    }

    fn writeSummary(
        ptr: *anyopaque,
        passed: u8,
        failed: u8,
        skipped: u8,
        total_duration_ms: f64,
        is_mem_leak: bool,
    ) anyerror!void {
        const writer: *std.io.AnyWriter = @ptrCast(@alignCast(ptr));
        try colorize(
            writer,
            Color.bold_cyan,
            "Total {d} tests were run in {d} ms: ",
            .{ passed + failed + skipped, total_duration_ms },
        );
        if (passed > 0)
            try colorize(writer, Color.green, "{d} passed; ", .{passed});
        if (failed > 0)
            try colorize(writer, Color.red, "{d} failed; ", .{failed});
        if (skipped > 0)
            try colorize(writer, Color.yellow, "{d} skipped;", .{skipped});
        if (is_mem_leak)
            try colorize(writer, Color.purple, "MEMORY LEAK", .{});
        try colorizeLine(writer, Color.bold_cyan, "", .{});
    }

    fn colorize(
        writer: *std.io.AnyWriter,
        comptime color: []const u8,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        try writer.writeAll(color);
        try std.fmt.format(writer.*, format, args);
        try writer.writeAll(esc);
    }

    inline fn colorizeLine(
        writer: *std.io.AnyWriter,
        comptime color: []const u8,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        try colorize(writer, color, format, args);
        _ = try writer.write("\n");
    }
};
