const std = @import("std");
const Type = std.builtin.Type;
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.event_bus);

pub const EntityMoved = struct {
    entity: g.Entity,
    is_player: bool,
    from: p.Point,
    to: p.Point,
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
    subscribers: Subscribers = undefined,

    pub fn init(alloc: std.mem.Allocator) EventBus {
        var self = EventBus{};
        inline for (@typeInfo(Subscribers).Struct.fields) |field| {
            @field(self.subscribers, field.name) = field.type.init(alloc);
        }
        return self;
    }

    pub fn deinit(self: EventBus) void {
        inline for (@typeInfo(Subscribers).Struct.fields) |field| {
            @field(self.subscribers, field.name).deinit();
        }
    }

    pub fn subscribeOn(self: *EventBus, comptime Event: type, subscriber: Subscriber(Event)) !void {
        try @field(self.subscribers, @typeName(Event)).append(subscriber);
    }

    pub fn notify(self: EventBus, event: anytype) !void {
        for (@field(self.subscribers, @typeName(@TypeOf(event))).items) |subscriber| {
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
            .type = std.ArrayList(Subscriber(event_as_field.type)),
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
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();
    var subscriber = TestSubscriber{};
    const event = EntityMoved{
        .entity = 1,
        .is_player = true,
        .from = .{ .row = 1, .col = 1 },
        .to = .{ .row = 1, .col = 2 },
        .direction = .right,
    };

    // when:
    try bus.subscribeOn(EntityMoved, subscriber.subscriber());
    try bus.notify(event);

    // then:
    try std.testing.expectEqualDeep(event, subscriber.event);
}
