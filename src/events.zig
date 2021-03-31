const std = @import("std");
const backend = @import("backend.zig");
usingnamespace @import("internal.zig");

pub const RedrawError = error {
    MissingPeer
};

pub fn Events(comptime T: type) type {
    return struct {
        pub const Callback       = fn(widget: *T) anyerror!void;
        pub const DrawCallback   = fn(ctx: backend.Canvas.DrawContext, widget: *T) anyerror!void;
        pub const ButtonCallback = fn(button: backend.MouseButton, pressed: bool, x: f64, y: f64, widget: *T) anyerror!void;
        pub const ScrollCallback = fn(dx: f64, dy: f64, widget: *T) anyerror!void;
        pub const HandlerList    = std.ArrayList(Callback);
        const DrawHandlerList    = std.ArrayList(DrawCallback);
        const ButtonHandlerList  = std.ArrayList(ButtonCallback);
        const ScrollHandlerList  = std.ArrayList(ScrollCallback);

        pub const Handlers = struct {
            clickHandlers: HandlerList,
            drawHandlers: DrawHandlerList,
            buttonHandlers: ButtonHandlerList,
            scrollHandlers: ScrollHandlerList
        };

        pub fn init_events(self: T) T {
            var obj = self;
            obj.handlers = .{
                .clickHandlers = HandlerList.init(lasting_allocator),
                .drawHandlers = DrawHandlerList.init(lasting_allocator),
                .buttonHandlers = ButtonHandlerList.init(lasting_allocator),
                .scrollHandlers = ScrollHandlerList.init(lasting_allocator)
            };
            return obj;
        }

        fn errorHandler(err: anyerror) void {
            std.log.err("{s}", .{@errorName(err)});
            var streamBuf: [16384]u8 = undefined;
            var stream = std.io.fixedBufferStream(&streamBuf);
            var writer = stream.writer();
            writer.print("Internal error: {s}.\n", .{@errorName(err)}) catch {};
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
                if (std.debug.getSelfDebugInfo()) |debug_info| {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    std.debug.writeStackTrace(trace.*, writer, &arena.allocator, debug_info, .no_color) catch {};
                } else |e| {}
            }
            writer.print("Please check the log.", .{}) catch {};
            backend.showNativeMessageDialog(.Error, "{s}", .{stream.getWritten()});
        }

        fn clickHandler(data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.clickHandlers.items) |func| {
                func(self) catch |err| errorHandler(err);
            }
        }

        fn drawHandler(ctx: backend.Canvas.DrawContext, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.drawHandlers.items) |func| {
                func(ctx, self) catch |err| errorHandler(err);
            }
        }

        fn buttonHandler(button: backend.MouseButton, pressed: bool, x: f64, y: f64, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.buttonHandlers.items) |func| {
                func(button, pressed, x, y, self) catch |err| errorHandler(err);
            }
        }

        fn scrollHandler(dx: f64, dy: f64, data: usize) void {
            const self = @intToPtr(*T, data);
            for (self.handlers.scrollHandlers.items) |func| {
                func(dx, dy, self) catch |err| errorHandler(err);
            }
        }

        pub fn show_events(self: *T) !void {
            self.peer.?.setUserData(self);
            try self.peer.?.setCallback(.Click      , clickHandler);
            try self.peer.?.setCallback(.Draw       , drawHandler);
            try self.peer.?.setCallback(.MouseButton, buttonHandler);
            try self.peer.?.setCallback(.Scroll     , scrollHandler);
        }

        pub fn addClickHandler(self: *T, handler: Callback) !void {
            try self.handlers.clickHandlers.append(handler);
        }

        pub fn addDrawHandler(self: *T, handler: DrawCallback) !void {
            try self.handlers.drawHandlers.append(handler);
        }

        pub fn addButtonHandler(self: *T, handler: ButtonCallback) !void {
            try self.handlers.buttonHandlers.append(handler);
        }

        pub fn addScrollHandler(self: *T, handler: ScrollCallback) !void {
            try self.handlers.scrollHandlers.append(handler);
        }

        pub fn requestDraw(self: *T) !void {
            if (self.peer) |*peer| {
                try peer.requestDraw();
            } else {
                return RedrawError.MissingPeer;
            }
        }
    };
}
