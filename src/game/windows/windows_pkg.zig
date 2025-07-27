const std = @import("std");
const g = @import("../game_pkg.zig");

/// To hide a window something should be drawn inside its region.
/// The easiest way is drawing underlying layer again (for example the whole scene, or a window 
/// under the current),but it's on optimal way. Usually we have to particular options:
///  - `from_buffe` - redraw inside the region a content from the inner buffer of the render; 
///  - `fill_region` - draw inside the region an empty space.
/// The first one is actual when a window is above the scene, the second - when the window is above
/// another window.
pub const HideMode = enum { from_buffer, fill_region };

pub const ModalWindow = @import("ModalWindow.zig");
pub const OptionsWindow = @import("OptionsWindow.zig").OptionWindow;
pub const TextArea = @import("TextArea.zig");
pub const WindowWithTabs = @import("WindowWithTabs.zig");
