// Пікер (Objective-C++ варіант): запускається на вимогу, читає історію з файлу,
// показує список, вставляє вибране й завершується. Дзеркало picker.swift.
//
// UI неминуче на AppKit — тут економити нема на чому; сенс експерименту у
// резидентному демоні. Пікер живе лише частку секунди, поки видно вікно.
//
// Лінкує: Cocoa (AppKit), ApplicationServices (CGEvent).

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString *historyPath(void) {
    NSString *base = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Application Support/ClipHistoryCpp/history.json"];
    return base;
}

static NSArray<NSString *> *loadHistory(void) {
    NSData *data = [NSData dataWithContentsOfFile:historyPath()];
    if (!data) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id x in (NSArray *)obj)
        if ([x isKindOfClass:[NSString class]]) [out addObject:x];
    return out;
}

static void sendCmdV(void) {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGKeyCode v = 0x09;
    CGEventRef down = CGEventCreateKeyboardEvent(src, v, true);
    CGEventRef up   = CGEventCreateKeyboardEvent(src, v, false);
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up,   kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    if (down) CFRelease(down);
    if (up)   CFRelease(up);
    if (src)  CFRelease(src);
}

// MARK: - Панель, що може стати key навіть будучи borderless

@interface KeyablePanel : NSPanel
@end
@implementation KeyablePanel
- (BOOL)canBecomeKeyWindow  { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

// MARK: - Таблиця з обробкою Enter/Esc

@interface KeyTableView : NSTableView
@property (nonatomic, copy) void (^onConfirm)(void);
@property (nonatomic, copy) void (^onCancel)(void);
@end
@implementation KeyTableView
- (void)keyDown:(NSEvent *)event {
    switch ((int)event.keyCode) {
        case 36: case 76: if (self.onConfirm) self.onConfirm(); break; // Enter / keypad Enter
        case 53:          if (self.onCancel)  self.onCancel();  break; // Esc
        default:          [super keyDown:event];
    }
}
@end

// MARK: - Пікер

@interface Picker : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@end

@implementation Picker {
    KeyablePanel *_panel;
    KeyTableView *_table;
    CGFloat _rowHeight;
    CGFloat _width;
    NSArray<NSString *> *_items;
    NSRunningApplication *_prevApp;
    BOOL _confirming;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rowHeight = 24;
        _width = 520;
        _confirming = NO;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    // Accessibility потрібен для авто-вставки ⌘V
    NSDictionary *opts = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    _prevApp = [[NSWorkspace sharedWorkspace] frontmostApplication]; // ДО активації
    _items = loadHistory();
    if (_items.count == 0) { NSBeep(); exit(0); }

    [self buildPanel];
    [self show];
}

- (void)buildPanel {
    _panel = [[KeyablePanel alloc] initWithContentRect:NSMakeRect(0, 0, _width, 200)
                                             styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    _panel.floatingPanel = YES;
    _panel.level = NSFloatingWindowLevel;
    _panel.hasShadow = YES;
    _panel.backgroundColor = [NSColor clearColor];
    _panel.opaque = NO;
    _panel.delegate = self;

    NSVisualEffectView *visual = [[NSVisualEffectView alloc] init];
    visual.material = NSVisualEffectMaterialPopover;
    visual.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    visual.state = NSVisualEffectStateActive;
    visual.wantsLayer = YES;
    visual.layer.cornerRadius = 10;
    visual.layer.masksToBounds = YES;

    _table = [[KeyTableView alloc] init];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    col.width = _width - 24;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.rowHeight = _rowHeight;
    _table.backgroundColor = [NSColor clearColor];
    _table.allowsEmptySelection = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.action = @selector(singleClick);
    __weak Picker *weakSelf = self;
    _table.onConfirm = ^{ [weakSelf confirm]; };
    _table.onCancel  = ^{ exit(0); };

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.autohidesScrollers = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [visual addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor  constraintEqualToAnchor:visual.leadingAnchor  constant:8],
        [scroll.trailingAnchor constraintEqualToAnchor:visual.trailingAnchor constant:-8],
        [scroll.topAnchor      constraintEqualToAnchor:visual.topAnchor      constant:8],
        [scroll.bottomAnchor   constraintEqualToAnchor:visual.bottomAnchor   constant:-8],
    ]];
    _panel.contentView = visual;
}

- (void)show {
    NSInteger rows = MIN((NSInteger)_items.count, 10);
    CGFloat h = rows * _rowHeight + 16;
    [_panel setContentSize:NSMakeSize(_width, h)];
    NSScreen *screen = [NSScreen mainScreen];
    if (screen) {
        NSRect f = screen.visibleFrame;
        [_panel setFrameOrigin:NSMakePoint(NSMidX(f) - _width / 2, NSMidY(f) - h / 2)];
    }
    [_table reloadData];
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [NSApp activateIgnoringOtherApps:YES];
    [_panel makeKeyAndOrderFront:nil];
    [_panel makeFirstResponder:_table];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    if (_confirming) return; // підтвердження саме ховає панель — не виходимо передчасно
    exit(0);
}

- (void)singleClick {
    if (_table.clickedRow >= 0) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:_table.clickedRow]
            byExtendingSelection:NO];
        [self confirm];
    }
}

- (void)confirm {
    NSInteger row = _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_items.count) return;
    _confirming = YES;
    NSString *chosen = _items[row];

    // Спочатку кладемо вибране у буфер, і лише потім ховаємо панель.
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:chosen forType:NSPasteboardTypeString];

    [_panel orderOut:nil];
    [_prevApp activateWithOptions:0];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        sendCmdV();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ exit(0); });
    });
}

- (NSString *)display:(NSString *)s {
    NSString *r = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    r = [r stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    return [r stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _items.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    NSString *id_ = @"cell";
    NSTextField *tf = [tableView makeViewWithIdentifier:id_ owner:self];
    if (!tf) {
        tf = [NSTextField labelWithString:@""];
        tf.identifier = id_;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        tf.font = [NSFont systemFontOfSize:13];
    }
    tf.stringValue = [self display:_items[row]];
    return tf;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        Picker *picker = [[Picker alloc] init];
        app.delegate = picker;
        [app run];
    }
    return 0;
}
