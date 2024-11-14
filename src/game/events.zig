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
    moved_to: p.Point,
    direction: p.Direction,
};

pub const Events = struct { EntityMoved };

pub fn Subscriber(comptime Event: type) type {
    return struct {
        context: *anyopaque,
        onEvent: *const fn (ptr: *anyopaque, event: Event) anyerror!void,
    };
}

pub const EventBus = struct {
    alloc: std.mem.Allocator,
    subscribers: *Subscribers,

    pub fn init(alloc: std.mem.Allocator) !EventBus {
        var self = EventBus{ .alloc = alloc, .subscribers = try alloc.create(Subscribers) };
        inline for (@typeInfo(Subscribers).Struct.fields) |field| {
            @field(self.subscribers, field.name) = field.type.init(alloc);
        }
        return self;
    }

    pub fn deinit(self: *EventBus) void {
        inline for (@typeInfo(Subscribers).Struct.fields) |field| {
            @field(self.subscribers, field.name).deinit();
        }
        self.alloc.destroy(self.subscribers);
    }

    pub fn subscribeOn(self: EventBus, comptime Event: type, subscriber: Subscriber(Event)) !void {
        const gop = try @field(self.subscribers, @typeName(Event)).getOrPut(@intFromPtr(subscriber.context));
        gop.value_ptr.* = subscriber;
    }

    pub fn unsubscribe(self: EventBus, subscriber_context: *anyopaque, comptime Event: type) bool {
        return @field(self.subscribers, @typeName(Event)).remove(subscriber_context);
    }

    pub fn notify(self: EventBus, event: anytype) !void {
        var itr = @field(self.subscribers, @typeName(@TypeOf(event))).valueIterator();
        while (itr.next()) |subscriber| {
            try subscriber.onEvent(subscriber.context, event);
        }
    }
};

const Subscribers = blk: {
    const type_info = @typeInfo(Events);
    const events_as_fields = type_info.Struct.fields;

    var fields: [events_as_fields.len]Type.StructField = undefined;
    // every field inside the ComponentsStruct should be optional, but we need their child types
    for (events_as_fields, 0..) |event_as_field, i| {
        fields[i] = .{
            .name = @typeName(event_as_field.type),
            .type = std.AutoHashMap(usize, Subscriber(event_as_field.type)),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }
    break :blk @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
};

test "publish/consume" {
    // given:
    const TestSubscriber = struct {
        event: ?EntityMoved = null,

        pub fn subscriber(self: *@This()) Subscriber(EntityMoved) {
            return .{ .context = self, .onEvent = rememberEvent };
        }
        fn rememberEvent(ptr: *anyopaque, event: EntityMoved) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.event = event;
        }
    };
    var bus = try EventBus.init(std.testing.allocator);
    defer bus.deinit();
    var subscriber = TestSubscriber{};
    const event = EntityMoved{
        .entity = 1,
        .is_player = true,
        .moved_from = .{ .row = 1, .col = 1 },
        .moved_to = .{ .row = 1, .col = 2 },
        .direction = .right,
    };

    // when:
    try bus.subscribeOn(EntityMoved, subscriber.subscriber());
    try bus.notify(event);

    // then:
    try std.testing.expectEqualDeep(event, subscriber.event);
}
