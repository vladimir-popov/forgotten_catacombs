pub fn AnyIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: *anyopaque,
        nextFn: *const fn (ptr: *anyopaque) ?T,

        pub fn next(self: *Self) ?T {
            return self.nextFn(self.ptr);
        }
    };
}

pub fn GenericIterator(
    comptime T: type,
    comptime Underlying: type,
    comptime nextFn: *const fn (underlying: *Underlying) ?T,
) type {
    return struct {
        const Self = @This();

        underlying: Underlying,

        pub fn any(self: *Self) AnyIterator(T) {
            return .{ .ptr = self, .nextFn = typeErasedNextFn };
        }

        fn typeErasedNextFn(underlying: *anyopaque) ?T {
            const ptr: *Underlying = @alignCast(@ptrCast(underlying));
            return nextFn(ptr);
        }
    };
}
