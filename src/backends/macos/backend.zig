const std = @import("std");
const shared = @import("../shared.zig");
const lib = @import("../../main.zig");
const objc = @import("objc");
const AppKit = @import("AppKit.zig");
const trait = @import("../../trait.zig");

const EventFunctions = shared.EventFunctions(@This());
const EventType = shared.BackendEventType;
const BackendError = shared.BackendError;
const MouseButton = shared.MouseButton;

// pub const PeerType = *opaque {};
pub const PeerType = objc.Object;

const atomicValue = if (@hasDecl(std.atomic, "Value")) std.atomic.Value else std.atomic.Atomic; // support zig 0.11 as well as current master
var activeWindows = atomicValue(usize).init(0);
var hasInit: bool = false;
var finishedLaunching = false;

pub fn init() BackendError!void {
    if (!hasInit) {
        hasInit = true;
        const NSApplication = objc.getClass("NSApplication").?;
        const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
        app.msgSend(void, "setActivationPolicy:", .{AppKit.NSApplicationActivationPolicy.Regular});
        app.msgSend(void, "activateIgnoringOtherApps:", .{@as(u8, @intFromBool(true))});
        std.log.info("the app is {}", .{app});
    }
}

pub fn showNativeMessageDialog(msgType: shared.MessageType, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(lib.internal.scratch_allocator, fmt, args) catch {
        std.log.err("Could not launch message dialog, original text: " ++ fmt, args);
        return;
    };
    defer lib.internal.scratch_allocator.free(msg);
    _ = msgType;
    @panic("TODO: message dialogs on macOS");
}

/// user data used for handling events
pub const EventUserData = struct {
    user: EventFunctions = .{},
    class: EventFunctions = .{},
    userdata: usize = 0,
    classUserdata: usize = 0,
    peer: PeerType,
    focusOnClick: bool = false,
};

var test_data = EventUserData{ .peer = undefined };
pub inline fn getEventUserData(peer: PeerType) *EventUserData {
    _ = peer;
    return &test_data;
    //return @ptrCast(*EventUserData, @alignCast(@alignOf(EventUserData), c.g_object_get_data(@ptrCast(*c.GObject, peer), "eventUserData").?));
}

pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn setUserData(self: *T, data: anytype) void {
            comptime {
                if (!trait.isSingleItemPtr(@TypeOf(data))) {
                    @compileError(std.fmt.comptimePrint("Expected single item pointer, got {s}", .{@typeName(@TypeOf(data))}));
                }
            }

            getEventUserData(self.peer).userdata = @intFromPtr(data);
        }

        pub inline fn setCallback(self: *T, comptime eType: EventType, cb: anytype) !void {
            const data = &getEventUserData(self.peer).user;
            switch (eType) {
                .Click => data.clickHandler = cb,
                .Draw => data.drawHandler = cb,
                .MouseButton => data.mouseButtonHandler = cb,
                .MouseMotion => data.mouseMotionHandler = cb,
                .Scroll => data.scrollHandler = cb,
                .TextChanged => data.changedTextHandler = cb,
                .Resize => data.resizeHandler = cb,
                .KeyType => data.keyTypeHandler = cb,
                .KeyPress => data.keyPressHandler = cb,
                .PropertyChange => data.propertyChangeHandler = cb,
            }
        }

        pub fn setOpacity(self: *const T, opacity: f32) void {
            _ = opacity;
            _ = self;
        }

        pub fn getWidth(self: *const T) u32 {
            _ = self;
            return 100;
        }

        pub fn getHeight(self: *const T) u32 {
            _ = self;
            return 100;
        }

        pub fn deinit(self: *const T) void {
            _ = self;
        }
    };
}

pub const Window = struct {
    source_dpi: u32 = 96,
    scale: f32 = 1.0,
    peer: objc.Object,

    pub usingnamespace Events(Window);

    pub fn create() BackendError!Window {
        const NSWindow = objc.getClass("NSWindow").?;
        const rect = AppKit.NSRect.make(0, 0, 800, 600);
        const style = AppKit.NSWindowStyleMask.Titled | AppKit.NSWindowStyleMask.Closable | AppKit.NSWindowStyleMask.Resizable;
        const flag: u8 = @intFromBool(false);

        const window = NSWindow.msgSend(objc.Object, "alloc", .{});
        _ = window.msgSend(
            objc.Object,
            "initWithContentRect:styleMask:backing:defer:",
            .{ rect, style, AppKit.NSBackingStore.Buffered, flag },
        );

        return Window{
            .peer = window,
        };
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        _ = height;
        _ = width;
        _ = self;
        // const frame = objc.NSRect.make(
        //     100,
        //     100,
        //     @as(objc.CGFloat, @floatFromInt(width)),
        //     @as(objc.CGFloat, @floatFromInt(height)),
        // );
        // // TODO: resize animation can be handled using a DataWrapper on the user-facing API
        // _ = objc.msgSendByName(void, self.peer, "setFrame:display:", .{ frame, true }) catch unreachable;
    }

    pub fn setTitle(self: *Window, title: [*:0]const u8) void {
        _ = self;
        _ = title;
    }

    pub fn setChild(self: *Window, peer: ?PeerType) void {
        _ = self;
        _ = peer;
    }

    pub fn setSourceDpi(self: *Window, dpi: u32) void {
        self.source_dpi = 96;
        // TODO
        const resolution = @as(f32, 96.0);
        self.scale = resolution / @as(f32, @floatFromInt(dpi));
    }

    pub fn show(self: *Window) void {
        std.log.info("show window", .{});
        self.peer.msgSend(void, "makeKeyAndOrderFront:", .{self.peer.value});
        // objc.msgSendByName(void, self.peer, "setIsVisible:", .{ @as(objc.id, self.peer), @as(u8, @intFromBool(true)) }) catch unreachable;
        // objc.msgSendByName(void, self.peer, "makeKeyAndOrderFront:", .{@as(objc.id, self.peer)}) catch unreachable;
        std.log.info("showed window", .{});
        _ = activeWindows.fetchAdd(1, .Release);
    }

    pub fn close(self: *Window) void {
        _ = self;
        @panic("TODO: close window");
    }
};

pub const Container = struct {
    peer: objc.Object,

    pub usingnamespace Events(Container);

    pub fn create() BackendError!Container {
        return Container{ .peer = undefined };
    }

    pub fn add(self: *const Container, peer: PeerType) void {
        _ = peer;
        _ = self;
    }

    pub fn remove(self: *const Container, peer: PeerType) void {
        _ = peer;
        _ = self;
    }

    pub fn move(self: *const Container, peer: PeerType, x: u32, y: u32) void {
        _ = y;
        _ = x;
        _ = peer;
        _ = self;
    }

    pub fn resize(self: *const Container, peer: PeerType, w: u32, h: u32) void {
        _ = h;
        _ = w;
        _ = peer;
        _ = self;
    }

    pub fn setTabOrder(self: *const Container, peers: []const PeerType) void {
        _ = peers;
        _ = self;
    }
};

pub const Canvas = struct {
    pub usingnamespace Events(Canvas);

    pub const DrawContext = struct {};
};

pub fn postEmptyEvent() void {
    @panic("TODO: postEmptyEvent");
}

pub fn runStep(step: shared.EventLoopStep) bool {
    if (!finishedLaunching) {
        finishedLaunching = true;
        const NSApplication = objc.getClass("NSApplication").?;
        const app = NSApplication.msgSend(objc.Object, "sharedApplication", .{});
        app.msgSend(void, "finishLaunching", .{});
        if (step == .Blocking) {
            app.msgSend(void, "run", .{});
        }
    }
    return activeWindows.load(.Acquire) != 0;
}
