// SpaceSwitchKit.c
//
// The gesture-posting half of this file (rcs_post_space_switch and the helpers under
// "Instant swipe") is adapted from InstantSpaceSwitcher, Copyright (c) 2026 jurplel,
// MIT License: https://github.com/jurplel/InstantSpaceSwitcher
// See LICENSE-InstantSpaceSwitcher in this directory.

#include "SpaceSwitchKit.h"
#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <string.h>

// MARK: - Private CGS / SkyLight API
//
// Resolved at runtime with dlsym rather than linked, so a macOS that renames or drops a
// symbol cannot break the build or the launch: rcs_is_available() simply reports false.
// SkyLight exports both the historical CGS* names and the newer SLS* names; try both.

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

typedef CGSConnectionID (*RCSMainConnectionIDFn)(void);
typedef CFArrayRef (*RCSCopyManagedDisplaySpacesFn)(CGSConnectionID cid);
typedef CFArrayRef (*RCSCopySpacesForWindowsFn)(CGSConnectionID cid, int mask, CFArrayRef windowIDs);

static RCSMainConnectionIDFn CGSMainConnectionID = NULL;
static RCSCopyManagedDisplaySpacesFn CGSCopyManagedDisplaySpaces = NULL;
static RCSCopySpacesForWindowsFn CGSCopySpacesForWindows = NULL;
static bool symbolsResolved = false;

static void *rcs_symbol(const char *cgsName, const char *slsName) {
    void *symbol = dlsym(RTLD_DEFAULT, cgsName);
    if (!symbol) {
        symbol = dlsym(RTLD_DEFAULT, slsName);
    }
    return symbol;
}

static void rcs_resolve_symbols(void) {
    if (symbolsResolved) {
        return;
    }
    symbolsResolved = true;
    CGSMainConnectionID = (RCSMainConnectionIDFn)rcs_symbol("CGSMainConnectionID", "SLSMainConnectionID");
    CGSCopyManagedDisplaySpaces = (RCSCopyManagedDisplaySpacesFn)rcs_symbol("CGSCopyManagedDisplaySpaces", "SLSCopyManagedDisplaySpaces");
    CGSCopySpacesForWindows = (RCSCopySpacesForWindowsFn)rcs_symbol("CGSCopySpacesForWindows", "SLSCopySpacesForWindows");
}

// kCGSSpaceIncludesCurrent | kCGSSpaceIncludesOthers | kCGSSpaceIncludesUser
static const int kRCSAllSpacesMask = 7;

bool rcs_is_available(void) {
    rcs_resolve_symbols();
    return CGSMainConnectionID != NULL
        && CGSCopyManagedDisplaySpaces != NULL
        && CGSCopySpacesForWindows != NULL;
}

// MARK: - Window location

static bool rcs_space_id_of_window(CGSConnectionID cid, uint32_t windowID, CGSSpaceID *outSpace) {
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &windowID);
    if (!number) {
        return false;
    }
    const void *values[1] = { number };
    CFArrayRef windows = CFArrayCreate(NULL, values, 1, &kCFTypeArrayCallBacks);
    CFRelease(number);
    if (!windows) {
        return false;
    }

    CFArrayRef spaces = CGSCopySpacesForWindows(cid, kRCSAllSpacesMask, windows);
    CFRelease(windows);
    if (!spaces) {
        return false;
    }

    bool ok = false;
    // Exactly one Space means a normal window. Zero: not on any Space (e.g. a closed or
    // off-screen helper). Several: pinned to all desktops, so it is already visible.
    if (CFArrayGetCount(spaces) == 1) {
        const void *value = CFArrayGetValueAtIndex(spaces, 0);
        if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
            CGSSpaceID space = 0;
            if (CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &space) && space != 0) {
                *outSpace = space;
                ok = true;
            }
        }
    }
    CFRelease(spaces);
    return ok;
}

static bool rcs_space_id_from_dict(CFDictionaryRef dict, CGSSpaceID *out) {
    if (!dict || CFGetTypeID(dict) != CFDictionaryGetTypeID()) {
        return false;
    }
    const void *value = CFDictionaryGetValue(dict, CFSTR("id64"));
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return false;
    }
    return CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, out) && *out != 0;
}

bool rcs_locate_window(uint32_t windowID, RCSWindowLocation *out) {
    if (!out || !rcs_is_available()) {
        return false;
    }
    memset(out, 0, sizeof(*out));

    CGSConnectionID cid = CGSMainConnectionID();
    if (cid == 0) {
        return false;
    }

    CGSSpaceID windowSpace = 0;
    if (!rcs_space_id_of_window(cid, windowID, &windowSpace)) {
        return false;
    }

    CFArrayRef displays = CGSCopyManagedDisplaySpaces(cid);
    if (!displays) {
        return false;
    }

    bool found = false;
    const CFIndex displayCount = CFArrayGetCount(displays);
    for (CFIndex d = 0; d < displayCount && !found; d++) {
        const void *displayValue = CFArrayGetValueAtIndex(displays, d);
        if (!displayValue || CFGetTypeID(displayValue) != CFDictionaryGetTypeID()) {
            continue;
        }
        CFDictionaryRef display = (CFDictionaryRef)displayValue;

        const void *spacesValue = CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (!spacesValue || CFGetTypeID(spacesValue) != CFArrayGetTypeID()) {
            continue;
        }
        CFArrayRef spaces = (CFArrayRef)spacesValue;

        CGSSpaceID currentSpace = 0;
        const void *currentValue = CFDictionaryGetValue(display, CFSTR("Current Space"));
        if (currentValue) {
            (void)rcs_space_id_from_dict((CFDictionaryRef)currentValue, &currentSpace);
        }

        unsigned int count = 0;
        unsigned int windowIndex = 0;
        unsigned int currentIndex = 0;
        bool haveWindowIndex = false;
        bool haveCurrentIndex = false;

        const CFIndex spaceCount = CFArrayGetCount(spaces);
        for (CFIndex s = 0; s < spaceCount; s++) {
            CGSSpaceID id = 0;
            if (!rcs_space_id_from_dict((CFDictionaryRef)CFArrayGetValueAtIndex(spaces, s), &id)) {
                continue;
            }
            if (id == windowSpace) {
                windowIndex = count;
                haveWindowIndex = true;
            }
            if (id == currentSpace) {
                currentIndex = count;
                haveCurrentIndex = true;
            }
            count++;
        }

        if (!haveWindowIndex || !haveCurrentIndex || count == 0) {
            continue;
        }

        const void *identifier = CFDictionaryGetValue(display, CFSTR("Display Identifier"));
        if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)identifier, out->displayIdentifier,
                               sizeof(out->displayIdentifier), kCFStringEncodingUTF8);
        }
        out->spaceIndex = windowIndex;
        out->currentIndex = currentIndex;
        out->spaceCount = count;
        found = true;
    }

    CFRelease(displays);
    return found;
}

// MARK: - Displays and the pointer

static bool rcs_copy_display_identifier(CGDirectDisplayID display, char *buffer, size_t length) {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
    if (!uuid) {
        return false;
    }
    CFStringRef string = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    if (!string) {
        return false;
    }
    bool ok = CFStringGetCString(string, buffer, length, kCFStringEncodingUTF8);
    CFRelease(string);
    return ok;
}

static bool rcs_display_for_identifier(const char *identifier, CGDirectDisplayID *out) {
    if (!identifier || !out) {
        return false;
    }
    CGDirectDisplayID displays[16];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(16, displays, &count) != kCGErrorSuccess) {
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        char buffer[128] = {0};
        if (rcs_copy_display_identifier(displays[i], buffer, sizeof(buffer)) && strcmp(buffer, identifier) == 0) {
            *out = displays[i];
            return true;
        }
    }
    return false;
}

bool rcs_pointer_is_on_display(const char *identifier) {
    if (!identifier) {
        return false;
    }
    CGEventRef event = CGEventCreate(NULL);
    if (!event) {
        return false;
    }
    CGPoint location = CGEventGetLocation(event);
    CFRelease(event);

    CGDirectDisplayID display = 0;
    uint32_t count = 0;
    if (CGGetDisplaysWithPoint(location, 1, &display, &count) != kCGErrorSuccess || count == 0) {
        return false;
    }
    char buffer[128] = {0};
    return rcs_copy_display_identifier(display, buffer, sizeof(buffer)) && strcmp(buffer, identifier) == 0;
}

bool rcs_move_pointer_to_display(const char *identifier) {
    CGDirectDisplayID display = 0;
    if (!rcs_display_for_identifier(identifier, &display)) {
        return false;
    }
    CGRect bounds = CGDisplayBounds(display);
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGWarpMouseCursorPosition(center);
    CGAssociateMouseAndMouseCursorPosition(true);
    return true;
}

// MARK: - Instant swipe (from InstantSpaceSwitcher)

static const CGEventField kCGSEventTypeField = (CGEventField)55;
static const CGEventField kCGEventGestureHIDType = (CGEventField)110;
static const CGEventField kCGEventGestureSwipeMotion = (CGEventField)123;
static const CGEventField kCGEventGestureSwipeProgress = (CGEventField)124;
static const CGEventField kCGEventGestureSwipePositionX = (CGEventField)125;
static const CGEventField kCGEventGestureSwipeVelocityX = (CGEventField)129;
static const CGEventField kCGEventGestureSwipeVelocityY = (CGEventField)130;
static const CGEventField kCGEventGesturePhase = (CGEventField)132;
static const CGEventField kCGEventGesturePhaseAlias = (CGEventField)134;
static const CGEventField kCGEventGestureZoomDeltaY = (CGEventField)138;
static const CGEventField kCGEventSourceUnixProcessIDAlias = (CGEventField)169;

static const uint32_t kIOHIDEventTypeDockSwipe = 23;   // IOHIDEventType in IOHIDFamily
static const uint32_t kCGSEventGesture = 29;
static const uint32_t kCGSEventDockControl = 30;
static const uint16_t kCGGestureMotionHorizontal = 1;

typedef enum {
    kCGSGesturePhaseBegan = 1,
    kCGSGesturePhaseChanged = 2,
    kCGSGesturePhaseEnded = 4,
} CGSGesturePhase;

// Velocity that commits the switch before the slide animation can run (macOS <= 26).
static const double kGestureSpeed = 2000.0;
// On macOS 27 the fling on the ended phase commits the switch; the field is 16.16 fixed
// point (max ~32767), so a separate constant.
static const double kModernFlingVelocity = 9999.0;
// The smallest non-zero 16.16 value: nothing left to animate, but direction is kept.
static const double kMinimalProgress = 0.000016;

// On macOS 27 right is negative, and the Dock reads the posted sign through the natural
// scrolling preference, so it flips again with natural scrolling off.
static double rcs_modern_swipe_sign(RCSDirection direction) {
    Boolean valid = false;
    Boolean natural = CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"),
                                                      kCFPreferencesAnyApplication, &valid);
    const bool naturalScrolling = (!valid || natural);
    const double sign = (direction == RCSDirectionRight) ? -1.0 : 1.0;
    return naturalScrolling ? sign : -sign;
}

static bool rcs_post_modern_dock_swipe(CGSGesturePhase phase, RCSDirection direction) {
    const double sign = rcs_modern_swipe_sign(direction);

    CGEventRef event = CGEventCreate(NULL);
    if (!event) {
        return false;
    }
    CGEventSetIntegerValueField(event, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(event, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kCGEventGesturePhase, phase);
    CGEventSetIntegerValueField(event, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress, sign * kMinimalProgress);
    // Fields a real trackpad swipe carries.
    CGEventSetIntegerValueField(event, kCGEventGesturePhaseAlias, phase);
    CGEventSetDoubleValueField(event, kCGEventGestureZoomDeltaY, 3.0);
    CGEventSetDoubleValueField(event, kCGEventSourceUnixProcessIDAlias, (double)mach_absolute_time());
    CGEventSetDoubleValueField(event, kCGEventGestureSwipePositionX, 0.1);
    if (phase == kCGSGesturePhaseEnded) {
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX, sign * kModernFlingVelocity);
    }

    CGEventRef augmented = iss_augment_dock_swipe_event(event);
    CFRelease(event);
    if (!augmented) {
        return false;
    }

    // The Dock ignores a DockControl event without a companion gesture event.
    CGEventRef companion = CGEventCreate(NULL);
    if (!companion) {
        CFRelease(augmented);
        return false;
    }
    CGEventSetIntegerValueField(companion, kCGSEventTypeField, kCGSEventGesture);

    CGEventPost(kCGSessionEventTap, augmented);
    CGEventPost(kCGSessionEventTap, companion);
    CFRelease(augmented);
    CFRelease(companion);
    return true;
}

static bool rcs_post_dock_swipe(CGSGesturePhase phase, RCSDirection direction, double velocity) {
    if (iss_requires_event_augmentation()) {
        return rcs_post_modern_dock_swipe(phase, direction);
    }

    const bool isRight = (direction == RCSDirectionRight);
    const double progress = isRight ? kMinimalProgress : -kMinimalProgress;
    const double signedVelocity = isRight ? velocity : -velocity;

    CGEventRef event = CGEventCreate(NULL);
    if (!event) {
        return false;
    }
    CGEventSetIntegerValueField(event, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(event, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kCGEventGesturePhase, phase);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress, progress);
    CGEventSetIntegerValueField(event, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX, signedVelocity);
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityY, signedVelocity);
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
    return true;
}

bool rcs_post_space_switch(RCSDirection direction, unsigned int steps) {
    if (steps == 0) {
        return true;
    }
    // Faster multi-Space travel, as InstantSpaceSwitcher does for jump-to-index.
    const double velocity = kGestureSpeed * (double)steps;
    for (unsigned int i = 0; i < steps; i++) {
        // Began, changed and ended are all required; with only two the Dock ignores it.
        if (!rcs_post_dock_swipe(kCGSGesturePhaseBegan, direction, velocity)
            || !rcs_post_dock_swipe(kCGSGesturePhaseChanged, direction, velocity)
            || !rcs_post_dock_swipe(kCGSGesturePhaseEnded, direction, velocity)) {
            return false;
        }
    }
    return true;
}
