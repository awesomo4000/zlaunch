# zlaunch — Specification

A minimal macOS application launcher. Press a global hotkey (default Cmd-Space), a borderless window appears over everything, you type, the list of matching applications filters live as you type, Enter launches the highlighted one. Escape dismisses.

Target: Zig 0.16.0, macOS (aarch64 + x86-64), no external dependencies beyond system frameworks.

## 1. Behavior

1. The binary launches and registers a global hotkey, then sits on the main run loop doing nothing visible.
2. On hotkey press, a borderless panel appears centered on the active screen, above all other windows, with a single-line text input at the top and a vertical list of application names below it.
3. The list initially shows all discovered applications (or a capped prefix of them — see §6).
4. As the user types, the list filters: an application is shown if its display name *contains* the typed string, case-insensitive. (Prefix-only is a config flag; default is substring, since it is more forgiving and costs nothing.)
5. One list row is always highlighted (the first matching row by default). Up/Down arrows move the highlight. Typing resets the highlight to the first row.
6. Enter launches the highlighted application via `open` and dismisses the window.
7. Escape dismisses the window without launching. Losing focus (clicking elsewhere) also dismisses.
8. The process keeps running after dismissal, ready for the next hotkey press.

Non-goals for v1: fuzzy ranking, frecency/usage history, calculator/web-search modes, plugins, multi-monitor cleverness beyond "use the screen with the mouse". These are deliberately out of scope to keep the first cut near 500 lines.

## 2. Architecture

Three concerns, kept separate:

- **Hotkey** — Carbon `RegisterEventHotKey`. Registration, not interception: the window server matches the chord and posts an event. Does not put the process in the input path, so it cannot cause the mouse/window stutter that an active `CGEventTap` causes.
- **Window + UI** — a borderless non-activating `NSPanel` driven through the Objective-C runtime (`objc_msgSend`) directly from Zig. No Swift, no nib, no Interface Builder. The panel hosts an `NSTextField` for input and a custom list view (or an `NSTableView`; see §5).
- **App discovery + launch** — enumerate `.app` bundles from the standard directories at startup, hold them in memory, filter in-process, launch the selection with `posix_spawn` of `/usr/bin/open`.

Everything runs on the main thread. AppKit requires UI on the main thread, and the Carbon hotkey handler fires on the run loop thread, so there is no threading to manage in v1.

## 3. Hotkey registration

Carbon's hotkey surface is a handful of C-ABI functions. `@cImport` is removed in 0.16.0; declare the externs by hand.

```zig
const OSStatus = i32;
const FourCharCode = u32;

const EventHotKeyID = extern struct { signature: FourCharCode, id: u32 };
const EventTypeSpec = extern struct { eventClass: FourCharCode, eventKind: u32 };

const EventTargetRef = ?*opaque {};
const EventHotKeyRef = ?*opaque {};
const EventHandlerRef = ?*opaque {};
const EventHandlerCallRef = ?*opaque {};
const EventRef = ?*opaque {};

const EventHandlerProc = *const fn (EventHandlerCallRef, EventRef, ?*anyopaque) callconv(.c) OSStatus;

extern "c" fn RegisterEventHotKey(u32, u32, EventHotKeyID, EventTargetRef, u32, *EventHotKeyRef) OSStatus;
extern "c" fn GetApplicationEventTarget() EventTargetRef;
extern "c" fn InstallEventHandler(EventTargetRef, EventHandlerProc, usize, [*]const EventTypeSpec, ?*anyopaque, ?*EventHandlerRef) OSStatus;
extern "c" fn GetEventParameter(EventRef, FourCharCode, FourCharCode, ?*FourCharCode, usize, ?*usize, ?*anyopaque) OSStatus;
```

Four-char-code helper and constants:

```zig
fn fourcc(comptime s: *const [4]u8) u32 {
    return std.mem.readInt(u32, s, .big);
}

const kEventClassKeyboard   = fourcc("keyb");
const kEventHotKeyPressed: u32 = 5;
const kEventParamDirectObject = fourcc("----");
const typeEventHotKeyID      = fourcc("hkid");

const cmdKey: u32  = 0x0100;
const kVK_Space: u32 = 0x31;
```

Registration at startup:

```zig
const target = GetApplicationEventTarget();
_ = InstallEventHandler(target, hotkeyHandler, 1,
    &[_]EventTypeSpec{.{ .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed }},
    null, null);

var ref: EventHotKeyRef = undefined;
_ = RegisterEventHotKey(kVK_Space, cmdKey,
    .{ .signature = fourcc("zlch"), .id = 1 }, target, 0, &ref);
```

The handler runs on the run loop thread; its only job is to show the panel:

```zig
fn hotkeyHandler(_: EventHandlerCallRef, _: EventRef, _: ?*anyopaque) callconv(.c) OSStatus {
    showLauncher();
    return 0; // noErr
}
```

**Cmd-Space conflict.** While Spotlight owns Cmd-Space, the system symbolic hotkey wins and `RegisterEventHotKey` will not receive it. The launcher must detect that its registration never fires (or simply document this) and instruct the user to unbind Spotlight: System Settings → Keyboard → Keyboard Shortcuts → Spotlight → uncheck "Show Spotlight search". After that the registration grabs Cmd-Space cleanly. Until the user is ready to do that, ship a non-conflicting default (e.g. Cmd-Alt-Space, modifiers `cmdKey | optionKey` where `optionKey = 0x0800`).

`EventHandlerUPP` is a plain function pointer on modern macOS — the PowerPC UPP indirection is gone — so passing the Zig fn directly is correct.

## 4. Objective-C runtime bridge

No Swift. Talk to AppKit through `objc_msgSend`. The pattern in Zig 0.16.0:

```zig
const objc = struct {
    const SEL = ?*opaque {};
    const Class = ?*opaque {};
    const id = ?*opaque {};

    extern "c" fn objc_getClass(name: [*:0]const u8) Class;
    extern "c" fn sel_registerName(name: [*:0]const u8) SEL;
    extern "c" fn objc_msgSend() void; // cast per-call signature

    fn cls(name: [*:0]const u8) Class { return objc_getClass(name); }
    fn sel(name: [*:0]const u8) SEL { return sel_registerName(name); }
};
```

Because `objc_msgSend` is variadic-by-ABI and must be called with the exact argument and return types of the target method, each call site casts it to a concrete function-pointer type:

```zig
fn msgSend(comptime Ret: type, comptime Args: type, recv: objc.id, op: objc.SEL, args: Args) Ret {
    const Fn = *const fn (objc.id, objc.SEL, ...) callconv(.c) Ret; // illustrative
    _ = Fn;
    const f: *const fn (objc.id, objc.SEL) callconv(.c) Ret = @ptrCast(&objc.objc_msgSend);
    _ = args;
    return f(recv, op);
}
```

> Implementation note: write small typed wrappers per signature rather than one variadic helper — e.g. `msgSend0`, `msgSend1`, `msgSendRect` — each `@ptrCast`-ing `objc_msgSend` to the precise prototype. This is verbose but the only ABI-correct way, and there are only ~15 distinct call signatures in the whole program. On aarch64 in particular, struct and float arguments must have the right prototype or they land in the wrong registers.

Link the frameworks in `build.zig`:

```zig
exe.root_module.linkFramework("Carbon", .{});
exe.root_module.linkFramework("Cocoa", .{});
exe.root_module.linkSystemLibrary("objc", .{});
```

The process must be a proper GUI app to show a window: call `[NSApplication sharedApplication]` and set activation policy to `NSApplicationActivationPolicyAccessory` (`1`) so it has no Dock icon and no menu bar but can still show panels and take key focus. Then `[NSApp run]` to drive the run loop (this replaces `CFRunLoopRun`; it pumps both AppKit events and the Carbon hotkey).

## 5. Window and UI

The window is an `NSPanel` created with:

- styleMask = `NSWindowStyleMaskBorderless` (`0`) combined with `NSWindowStyleMaskNonactivatingPanel` (`1 << 7`). Non-activating is what lets the panel take keystrokes without deactivating the app the user was in, which makes it feel instant.
- backing = `NSBackingStoreBuffered` (`2`), defer = false.
- level set above normal windows: `[panel setLevel: NSMainMenuWindowLevel + 1]` or `NSFloatingWindowLevel` (`3`). Use a high level so it floats over full-screen-ish content.
- `setOpaque:false`, a dark rounded background via the content view's layer, `setHidesOnDeactivate:true` so clicking away dismisses it.
- positioned centered horizontally and in the upper third of the screen that currently has the mouse (`NSScreen` enumeration; pick the screen whose frame contains `[NSEvent mouseLocation]`).

Content layout, top to bottom:

- An `NSTextField` (single line, large font, no border or a subtle one) as the input. The panel is made key and the text field made first responder on show, so typing goes straight in.
- A results list directly below. **Recommendation: a hand-drawn list, not `NSTableView`.** For v1 the list is short (cap visible rows at ~8) and a custom view that draws N rows of text with one highlighted is far less Obj-C surface than wiring up a table view's data source and delegate protocols from raw `objc_msgSend`. Each row is the app's display name; the highlighted row gets a filled background.

Input handling: rather than fight `NSTextField`'s delegate protocol over the runtime bridge, the cleanest path is to subclass nothing and instead install a local key event monitor with `[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^...]`. From Zig you cannot easily make an Obj-C block, so the practical alternatives are:

1. Register a custom Obj-C class at runtime (`objc_allocateClassPair` / `class_addMethod`) that implements `controlTextDidChange:`, `keyDown:`, etc., with Zig functions as IMPs. This is the robust approach and is recommended despite the boilerplate — it is a fixed, one-time cost.
2. Poll the text field's string value on a short timer. Simpler, hacky, fine for a first exploratory cut.

Use approach (1) for the keeper version: a single runtime-defined class `ZLDelegate` serving as the panel's delegate, the text field's delegate, and the window delegate. Its methods:

- `controlTextDidChange:` → read `[textField stringValue]`, run the filter (§6), tell the list view to redraw.
- `keyDown:` is not delivered to a delegate; instead intercept Up/Down/Return/Escape by making the text field's field editor forward via `control:textView:doCommandBySelector:`, which *is* a delegate method. Map `moveUp:`/`moveDown:` to highlight movement, `insertNewline:` to launch, `cancelOperation:` to dismiss. Return `true` from these to swallow them.
- `windowDidResignKey:` → dismiss.

This keeps every event flowing through one delegate object and avoids subclassing `NSTextField` or `NSPanel`.

## 6. Application discovery and filtering

At startup (and optionally refreshed on each show if cheap enough), enumerate `.app` bundles in:

- `/Applications`
- `/Applications/Utilities`
- `/System/Applications`
- `/System/Applications/Utilities`
- `~/Applications`

Use Zig's `std.fs` to read these directories; collect every entry ending in `.app`. The display name is the bundle name with `.app` stripped (sufficient for v1; reading `CFBundleDisplayName` from `Contents/Info.plist` is a later refinement). Store an array of structs:

```zig
const App = struct {
    name: []const u8,        // "Firefox"
    name_lower: []const u8,  // "firefox", precomputed for case-insensitive match
    path: []const u8,        // "/Applications/Firefox.app"
};
```

Filtering on each keystroke:

```zig
fn filter(apps: []const App, query: []const u8, out: *std.ArrayList(usize)) void {
    out.clearRetainingCapacity();
    var buf: [256]u8 = undefined;
    const q = std.ascii.lowerString(buf[0..query.len], query);
    for (apps, 0..) |app, i| {
        if (query.len == 0 or std.mem.indexOf(u8, app.name_lower, q) != null) {
            out.append(i) catch {};
        }
    }
}
```

`name_lower` is computed once at discovery so each keystroke is a pass of `indexOf` over the set — trivially fast for the few hundred apps a machine has. Highlight resets to index 0 of the filtered list on every change.

Substring vs prefix: the user's stated mental model is "type a letter, see apps starting with that letter". Honour that as the *default ordering* — sort matches so prefix matches come before interior matches — but still include interior matches below them. A single `std.sort` keying on `(indexOf == 0 ? 0 : 1, name)` gives prefix-first ordering without dropping anything.

## 7. Launching

The highlighted app's path is handed to `/usr/bin/open`:

```zig
fn launch(path: []const u8, gpa: std.mem.Allocator) void {
    var child = std.process.Child.init(&.{ "/usr/bin/open", path }, gpa);
    _ = child.spawnAndWait() catch {};
}
```

`open` with a `.app` path activates or launches the app correctly, handling already-running apps, LaunchServices registration, and so on — there is no reason to reimplement this. Immediately after spawning, dismiss the panel (`[panel orderOut:nil]`) and clear the input so the next invocation starts fresh.

## 8. Dismissal and lifecycle

- Escape (`cancelOperation:`) → `orderOut`, clear input.
- Resign key (`windowDidResignKey:`) → `orderOut`, clear input.
- After launch → `orderOut`, clear input.
- The process never exits on dismissal; only the panel is ordered out. The Carbon hotkey remains registered for the next press.
- On `showLauncher()`: rebuild/refresh the screen position, set string value to empty, run the filter with empty query (shows all, prefix-sorted), make the panel key and front (`[panel makeKeyAndOrderFront:nil]`, `[NSApp activateIgnoringOtherApps:true]`), make the text field first responder.

## 9. Configuration (optional, v1.1)

A plain text file at `~/.config/zlaunch/config` is enough:

```
hotkey = cmd-alt-space
match  = substring        # or "prefix"
rows   = 8
dirs   = /Applications, /System/Applications, ~/Applications
```

Parsing this is a later concern; v1 hardcodes the defaults named throughout this document.

## 10. Build

`build.zig` essentials:

```zig
const exe = b.addExecutable(.{
    .name = "zlaunch",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
exe.root_module.linkFramework("Carbon", .{});
exe.root_module.linkFramework("Cocoa", .{});
exe.root_module.linkSystemLibrary("objc", .{});
b.installArtifact(exe);
```

The result is a single static-ish binary linking only system frameworks. It can be run directly from the terminal for development; to make Cmd-Space binding behave well and to get proper activation, later wrap it in a minimal `.app` bundle with an `Info.plist` declaring `LSUIElement = true` (the bundle equivalent of the accessory activation policy).

## 11. Implementation order

1. Bare `NSApplication` accessory app that shows an empty borderless panel on launch and exits on Escape. Validates the Obj-C bridge and the per-signature `msgSend` wrappers.
2. Add Carbon hotkey; panel now shows on Cmd-Alt-Space instead of at launch.
3. App discovery; dump names to stdout to confirm enumeration.
4. Text field + custom list view; wire `controlTextDidChange:` to filter and redraw.
5. Arrow-key highlight movement and Enter-to-launch via `doCommandBySelector:`.
6. Dismissal paths (Escape, resign key, post-launch).
7. Prefix-first sort, row cap, screen-under-mouse positioning — the polish pass.

Each step is independently runnable, which suits incremental development and lets an assistant verify behavior at every stage before moving on.
