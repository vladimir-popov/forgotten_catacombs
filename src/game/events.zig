const std = @import("std");
const Type = std.builtin.Type;
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.events);

pub const EntityMoved = struct {
    entity: g.Entity,
    is_player: bool,
    moved_from: p.Point,
    target: g.Action.Move.Target,

    pub fn targetPlace(self: EntityMoved) p.Point {
        return switch (self.target) {
            .direction => |direction| self.moved_from.movedTo(direction),
            .new_place => |place| place,
        };
    }
};

pub const PlayerHit = struct { target: g.Entity };

pub const Event = union(enum) {
    const Tag = @typeInfo(Event).@"union".tag_type.?;

    entity_moved: EntityMoved,
    player_hit: PlayerHit,

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

    arena: *std.heap.ArenaAllocator,
    events: std.ArrayListUnmanaged(Event),
    subscribers: std.AutoHashMapUnmanaged(Ptr, Subscriber),

    pub fn init(arena: *std.heap.ArenaAllocator) EventBus {
        return .{
            .arena = arena,
            .subscribers = std.AutoHashMapUnmanaged(Ptr, Subscriber){},
            .events = std.ArrayListUnmanaged(Event){},
        };
    }

    pub inline fn subscribe(self: *EventBus, subscriber: Subscriber) !void {
        try self.subscribers.putNoClobber(self.arena.allocator(), @intFromPtr(subscriber.context), subscriber);
    }

    pub fn unsubscribe(self: *EventBus, subscriber_context: *anyopaque) bool {
        return self.subscribers.remove(@intFromPtr(subscriber_context));
    }

    pub fn sendEvent(self: *EventBus, event: Event) !void {
        log.debug("Event happened: {any}", .{event});
        try self.events.append(self.arena.allocator(), event);
    }

    pub fn notifySubscribers(self: *EventBus) !void {
        for (self.events.items) |event| {
            var itr = self.subscribers.valueIterator();
            while (itr.next()) |subscriber| {
                try subscriber.onEvent(subscriber.context, event);
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

    var bus: EventBus = EventBus.init(&arena);
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
    try bus.subscribe(subscriber.subscriber());
    try bus.sendEvent(event);

    // then:
    try std.testing.expectEqual(null, subscriber.event);

    // when:
    try bus.notifySubscribers();

    // then:
    try std.testing.expectEqualDeep(event, subscriber.event);
}
