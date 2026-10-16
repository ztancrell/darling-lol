#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

/* Exported by Darling's CoreGraphics but missing from its CGDirectDisplay.h. */
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID display, CFDictionaryRef options);

/* League passes CGDisplayCopyAllDisplayModes' result straight to
 * CFArrayGetCount; display id 0 comes from an off-screen window. */
static int check(CGDirectDisplayID display) {
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, NULL);
    if (!modes) {
        printf("DISPLAY_MODES display=%u result=NULL pass=0\n", display);
        return 0;
    }
    printf("DISPLAY_MODES display=%u count=%ld\n", display, (long)CFArrayGetCount(modes));
    CFRelease(modes);
    return 1;
}

int main(void) {
    int pass = check(CGMainDisplayID()) & check(0) & check(0xffff);
    printf("DISPLAY_MODES_CHECK pass=%d\n", pass);
    return !pass;
}
