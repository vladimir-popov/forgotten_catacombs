# Window System

The window system is built around two concepts: **areas** and **windows**.

Areas manage content and input. Windows place areas on the screen and provide visual structure. The system uses
composition and structural interfaces rather than a single base window type.

## Areas

An area is a concrete type that provides the following operations:

```zig
totalLines()
selectedLine()
handleButton()
drawContent()
leftButton()
rightButton()
```


The main area implementations are:

- `TextArea` — stores and draws lines of text.
- `OptionsArea(Item)` — stores selectable items and invokes an item-specific button handler. Its handlers receive 
   the area context, the selected line, and the selected item. A handler returns `HandleButtonResult`, which tells
   the owning window whether it should remain open or close.
- `ScrollablePanel(Area)` — wraps an area with scrolling, a scrollbar, and optional button overrides.


## Scrollable panels

`ScrollablePanel(Area)` is an adapter between an area and a window. It owns:

- the concrete area;
- the drawing region;
- the current scroll position;
- optional overrides for the left and right buttons.

Input is processed in this order:

```text
button
  ↓
ScrollablePanel
  ├─ matching button override → invoke the override
  └─ otherwise → forward the button to the area
```

The panel handles `up` and `down` by changing its scroll position. It clamps scrolling to the number of lines that
cannot fit in the visible region. When the content is larger than the region, it draws a scrollbar and reserves one
column for it.

Button overrides are useful when the surrounding window needs to replace the area's default behavior. For example, an
options modal overrides the left button with a `Close` action.

## Modal windows

`ModalWindow(Area)` adds a visual container around a scrollable panel. It provides:

- a title;
- a screen region;
- a border;
- the panel's content;
- the panel's buttons.

Its structure is:

```text
ModalWindow
  └─ ScrollablePanel
       └─ TextArea / OptionsArea(Item)
```

The constructors in `modal_window.zig` create common modal types:

- `withText` — an empty text modal;
- `withOptions` — a selectable options modal;
- `notification` — a centered multiline notification;
- `entityDescription` — a description of a player, enemy, or item.

The modal window does not contain the selection logic itself. It delegates input and content drawing to its panel.

## Tabbed windows

`TabbedWindow(Areas)` is a full-screen window with a fixed, heterogeneous set of tabs. The tab types are known at
compile time, while the number of initialized tabs is tracked at runtime.

Each tab contains:

```text
title
ScrollablePanel(Area)
```

The tabbed window:

- delegates input to the active tab;
- switches tabs with `left` and `right`;
- draws the tab titles and active-tab border;
- draws the active panel and its buttons;
- supplies a default `Close` button when the active area does not provide one.

The input flow is:

```text
TabbedWindow
  ↓
active tab
  ↓
ScrollablePanel
  ↓
Area
```

If the active panel does not close the window, the tabbed window handles tab navigation. Pressing `b` closes the tabbed
window when the active tab does not provide its own left button.

## Window compositor

`WindowCompositor` combines one borrowed main window with a stack of owned modal windows:

```text
main_window
  + modal 0
  + modal 1
  + modal 2
```

The main window is borrowed. Its owner must keep it at a stable address and deinitialize it separately. The compositor
owns the modal windows.

The compositor currently has three reusable modal slots. Each slot owns an arena and optionally contains one concrete
modal window. The concrete type is erased through a pointer and a vtable, so the compositor can store text modals and
options modals in the same array.

The `show*` methods create and push modal windows:

```zig
showModalWindowWithText(...)
showModalWindowWithOptions(...)
showNotification(...)
showEntityDescription(...)
```

The returned pointer is borrowed. The compositor owns the object and deinitializes it when the modal closes or when the
compositor is deinitialized. The caller must not call `deinit` on that object.

Input and drawing use opposite traversal orders.

Input is sent only to the topmost modal window:

```text
button
  ↓
topmost modal window
```

If no modal exists, the button is sent to the main window. A modal returning `.close_window` is unwrapped and removed
from the stack.

Drawing starts with the main window and then draws modals from bottom to top:

```text
draw main window
draw modal 0
draw modal 1
draw modal 2
```

This makes each later modal visually cover the windows below it.

When a modal creates another modal while handling a button and then requests closing, the compositor removes the old
modal and shifts the newly created modal down. `std.mem.swap` is used during this operation so that arena ownership is
not duplicated accidentally.

### Type erasure and ownership

The compositor stores type-erased windows as:

```zig
ptr: *anyopaque
vtable: VTable
```

The vtable contains functions for:

- handling a button;
- drawing;
- deinitializing.

The original concrete type is restored inside the vtable callback with `@ptrCast` and `@alignCast`.

There are two related type-erased wrappers in the source:

- `GenericWindow` inside `WindowCompositor.zig`, used by the compositor;
- `GenericModalWindow.zig`, used as a separate generic area wrapper.

They serve different roles even though their names are similar.

## Wizard windows

`WizardWindow` is a separate navigation mechanism. Unlike `WindowCompositor`, it does not use a modal stack.

It stores a union of possible steps and initializes only the current step. A dedicated arena owns the current step's
allocations. When the wizard moves to another step, the current step is committed or rolled back, the arena is reset,
and the next step is initialized.

The usual navigation is:

- `a` — complete the current step and move forward;
- `b` — roll back the current step and move backward;
- completing the final step — close the wizard.

Some wizard steps also contain an optional description window directly. This is local nesting inside a step and is
separate from the compositor's modal stack.

## Overall structure

The common composition looks like this:

```text
GameMode
  └─ WindowCompositor
       ├─ main window
       │    └─ TabbedWindow / another window type
       │         └─ ScrollablePanel
       │              └─ Area
       └─ modal windows
            └─ ModalWindow
                 └─ ScrollablePanel
                      └─ Area
```

Button handling travels from the game mode down to the currently visible content. Drawing travels from the base window
upward through the modal stack.

## Important contracts

- The main window passed to `WindowCompositor.init` must outlive the compositor and remain at a stable address.
- Modal windows returned by `show*` are borrowed and must not be manually deinitialized.
- `topModalWindowArea` requires the exact concrete area type stored in the top modal window.
- The compositor can hold at most three modal windows at once.
- The compositor and wizard use different ownership and nesting models.
