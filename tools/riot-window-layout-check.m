#import <AppKit/AppKit.h>
#import <QuartzCore/CALayer.h>
#include <stdio.h>

@interface ResizeOrderView : NSView {
@public
    NSSize nativeSizeDuringResize;
}
@end
@implementation ResizeOrderView
- (void)setFrame:(NSRect)frame {
    if ([self window])
        nativeSizeDuringResize = [(id)[[self window] platformWindow] frame].size;
    [super setFrame:frame];
}
@end

/* Browser compositors publish their new viewport from setFrameSize:, even
 * when AppKit or their parent sets a complete frame rectangle. */
@interface FrameSizeHookView : NSView {
@public
    NSUInteger sizeCallbacks;
    NSSize publishedSize;
}
@end
@implementation FrameSizeHookView
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    sizeCallbacks++;
    publishedSize = [self frame].size;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect rect = NSMakeRect(20, 20, 1280, 720);
        NSUInteger mask = NSTitledWindowMask | NSWindowStyleMaskFullSizeContentView;
        NSRect converted = [NSWindow contentRectForFrameRect:
            [NSWindow frameRectForContentRect:rect styleMask:mask] styleMask:mask];
        NSWindow *full = [[NSWindow alloc] initWithContentRect:rect
            styleMask:mask backing:NSBackingStoreBuffered defer:NO];
        [full setFrame:rect display:NO];
        NSSize size = [[full contentView] frame].size;
        BOOL pass = NSEqualRects(converted, rect) && NSEqualSizes(size, rect.size);
        NSWindow *ordinary = [[NSWindow alloc] initWithContentRect:rect
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
        pass &= NSEqualSizes([[ordinary contentView] frame].size, rect.size);
        [ordinary setStyleMask:mask];
        NSSize changed = [[ordinary contentView] frame].size;
        pass &= NSEqualSizes(changed, [ordinary frame].size);
        [full setFrame:NSMakeRect(20, 20, 900, 500) display:NO];
        pass &= NSEqualSizes([[full contentView] frame].size, NSMakeSize(900, 500));
        /* Layer geometry must be current before any coordinate conversion or
         * input event. Chromium submits compositor surfaces during resize. */
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720)];
        [view setWantsLayer:YES];
        [view setFrameSize:NSMakeSize(1600, 900)];
        NSSize layerSize = [[view layer] bounds].size;
        BOOL layers = NSEqualSizes(layerSize, NSMakeSize(1600, 900));
        [view setBounds:NSMakeRect(10, 20, 800, 450)];
        layers &= NSEqualRects([[view layer] bounds], NSMakeRect(10, 20, 800, 450));
        [view setFrameSize:NSMakeSize(1280, 720)];
        layers &= NSEqualSizes([[view layer] bounds].size, NSMakeSize(640, 360));
        NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(5, 6, 20, 30)];
        [view addSubview:child];
        [child setFrame:NSMakeRect(12, 18, 40, 50)];
        layers &= NSEqualRects([[child layer] frame], NSMakeRect(12, 18, 40, 50));
        printf("VIEW_LAYER_RESIZE initial=%.0fx%.0f pass=%d\n", layerSize.width, layerSize.height, layers);
        pass &= layers;
        NSWindow *native = [[NSWindow alloc] initWithContentRect:rect styleMask:NSBorderlessWindowMask
            backing:NSBackingStoreBuffered defer:NO];
        ResizeOrderView *content = [[ResizeOrderView alloc] initWithFrame:rect];
        [native setContentView:content];
        [native platformWindow];
        [native setFrame:NSMakeRect(20, 20, 1600, 900) display:NO];
        BOOL nativeOrder = NSEqualSizes(content->nativeSizeDuringResize, NSMakeSize(1600, 900));
        printf("NATIVE_RESIZE_ORDER size=%.0fx%.0f pass=%d\n", content->nativeSizeDuringResize.width,
            content->nativeSizeDuringResize.height, nativeOrder);
        pass &= nativeOrder;
        /* Chromium adds titlebar/overlay siblings after the actual content.
         * Frame layout must not mistake the last sibling for the content. */
        NSView *overlay = [[NSView alloc] initWithFrame:NSMakeRect(4, 5, 30, 20)];
        [[[native contentView] superview] addSubview:overlay];
        [native setContentSize:NSMakeSize(1280, 720)];
        BOOL siblings = NSEqualSizes([[native contentView] frame].size, NSMakeSize(1280, 720)) &&
            NSEqualSizes([overlay frame].size, NSMakeSize(30, 20));
        printf("CONTENT_SIBLING_RESIZE content=%.0fx%.0f overlay=%.0fx%.0f pass=%d\n",
            [[native contentView] frame].size.width, [[native contentView] frame].size.height,
            [overlay frame].size.width, [overlay frame].size.height, siblings);
        pass &= siblings;
        NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720)];
        FrameSizeHookView *viewport = [[FrameSizeHookView alloc]
            initWithFrame:NSMakeRect(0, 0, 1280, 720)];
        [viewport setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [host addSubview:viewport];
        [host setFrame:NSMakeRect(0, 0, 1600, 900)];
        BOOL hooks = viewport->sizeCallbacks == 1 &&
            NSEqualSizes(viewport->publishedSize, NSMakeSize(1600, 900));
        [host setFrame:NSMakeRect(0, 0, 1024, 576)];
        hooks &= viewport->sizeCallbacks == 2 &&
            NSEqualSizes(viewport->publishedSize, NSMakeSize(1024, 576));
        [viewport setFrame:NSMakeRect(3, 4, 800, 450)];
        hooks &= viewport->sizeCallbacks == 3 &&
            NSEqualSizes(viewport->publishedSize, NSMakeSize(800, 450));
        [viewport setFrameSize:NSMakeSize(640, 360)];
        hooks &= viewport->sizeCallbacks == 4 &&
            NSEqualSizes(viewport->publishedSize, NSMakeSize(640, 360));
        printf("FRAME_SIZE_HOOK callbacks=%lu published=%.0fx%.0f pass=%d\n",
            (unsigned long)viewport->sizeCallbacks, viewport->publishedSize.width,
            viewport->publishedSize.height, hooks);
        pass &= hooks;
        // League flips coordinates with screens[0] and sizes its first
        // window from the main screen, then its
        // fullscreen window from the display of that zero-size, possibly
        // off-screen window. XRandR's disconnected outputs are empty screens;
        // neither lookup may land on one or on nil (display 0, a 0x0 window).
        NSRect screenFrame = [[NSScreen mainScreen] frame];
        BOOL zeroSize = !NSIsEmptyRect(screenFrame) &&
            !NSIsEmptyRect([[[NSScreen screens] objectAtIndex:0] frame]);
        NSRect probes[] = { NSMakeRect(NSMidX(screenFrame), NSMidY(screenFrame), 0, 0), NSMakeRect(-50000, -50000, 0, 0) };
        for (int i = 0; i < 2; i++) {
            NSWindow *empty = [[NSWindow alloc] initWithContentRect:probes[i]
                styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
            zeroSize &= !NSIsEmptyRect([[empty screen] frame]);
            [empty release];
        }
        printf("ZERO_SIZE_WINDOW_SCREEN main=%.0fx%.0f pass=%d\n", screenFrame.size.width, screenFrame.size.height, zeroSize);
        pass &= zeroSize;
        [viewport release]; [host release];
        [overlay release];
        [content release]; [native release];
        [child release]; [view release];
        printf("WINDOW_LAYOUT_CHECK full=%.0fx%.0f changed=%.0fx%.0f pass=%d\n",
            size.width, size.height, changed.width, changed.height, pass);
        [ordinary release]; [full release];
        return pass ? 0 : 1;
    }
}
