const std = @import("std");
const Type = std.builtin.Type;
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.event_bus);

pub const EntityMoved = struct {
    entity: g.Entity,
    is_player: bool,
    moved_from: p.Point,
    target: g.components.Action.Move.Target,

    pub fn movedTo(self: EntityMoved) p.Point {
        return switch (self.target) {
            .direction => |direction| self.moved_from.movedTo(direction),
            .new_place => |place| place,
        };
    }
};

pub const EntityDied = struct {
    entity: g.Entity,
    is_player: bool,
};

pub const Event = union(enum) {
    const Tag = @typeInfo(Event).Union.tag_type.?;

    entity_moved: EntityMoved,
    entity_died: EntityDied,

    pub fn get(self: Event, comptime tag: Tag) ?std.meta.TagPayload(Event, tag) {
        switch (self) {
            tag => |v| return v,
            else => return null,
        }
    }
};

pub const Subscriber = struct {
    context: *anyopaque,
    onEvent: *const fn (ptr: *anyopaque, event: Event) anyerror!void,
};

pub const EventBus = struct {
    const Ptr = usize;

    events: std.ArrayList(Event),
    subscribers: std.AutoHashMap(Event.Tag, std.AutoHashMap(Ptr, Subscriber)),

    pub fn init(self: *EventBus, arena: *std.heap.ArenaAllocator) !void {
        self.subscribers = std.AutoHashMap(Event.Tag, std.AutoHashMap(Ptr, Subscriber)).init(arena.allocator());
        self.events = std.ArrayList(Event).init(arena.allocator());
    }

    pub fn subscribeOn(self: *EventBus, event: Event.Tag, subscriber: Subscriber) !void {
        const gop = try self.subscribers.getOrPut(event);
        if (gop.found_existing) {
            try gop.value_ptr.put(@intFromPtr(subscriber.context), subscriber);
        } else {
            gop.value_ptr.* = std.AutoHashMap(Ptr, Subscriber).init(self.subscribers.allocator);
            try gop.value_ptr.put(@intFromPtr(subscriber.context), subscriber);
        }
    }

    pub fn unsubscribe(self: *EventBus, subscriber_context: *anyopaque, event: Event.Tag) bool {
        const gop = try self.subscribers.getOrPut(event);
        if (gop.found_existing) {
            _ = gop.value_ptr.remove(subscriber_context);
        }
    }

    pub fn sendEvent(self: *EventBus, event: Event) !void {
        log.debug("Event happened: {any}", .{event});
        try self.events.append(event);
    }

    pub fn notifySubscribers(self: *EventBus) !void {
        for (self.events.items) |event| {
            if (self.subscribers.get(event)) |subscribers| {
                var itr = subscribers.valueIterator();
                while (itr.next()) |subscriber| {
                    try subscriber.onEvent(subscriber.context, event);
                }
            }
            log.debug("Event handled: {any}", .{event});
        }
        self.events.clearRetainingCapacity();
    }
};

test "publish/consume" {
    // given:
    const TestSubscriber = struct {
        event: ?Event = null,

        pub fn subscriber(self: *@This()) Subscriber {
            return .{ .context = self, .onEvent = rememberEvent };
        }
        fn rememberEvent(ptr: *anyopaque, event: Event) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.event = event;
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var bus: EventBus = undefined;
    try bus.init(&arena);

    var subscriber = TestSubscriber{};
    const event = Event{
        .entity_moved = .{
            .entity = 1,
            .is_player = true,
            .moved_from = .{ .row = 1, .col = 1 },
            .target = .{ .new_place = .{ .row = 1, .col = 2 } },
        },
    };

    // when:
    try bus.subscribeOn(.entity_moved, subscriber.subscriber());
    try bus.sendEvent(event);

    // then:
    try std.testing.expectEqual(null, subscriber.event);

    // when:
    try bus.notifySubscribers();

    // then:
    try std.testing.expectEqualDeep(event, subscriber.event);
}
