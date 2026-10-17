#ifndef SPACE_SWITCH_KIT_H
#define SPACE_SWITCH_KIT_H

#include <stdbool.h>
#include <stdint.h>

/*
 * SpaceSwitchKit: locate the Space a window lives on and jump there without the slide
 * animation. The jump technique is from InstantSpaceSwitcher (MIT, jurplel): a synthetic
 * Dock swipe with near-zero travel and a very high fling velocity, which the Dock
 * commits instantly. Space discovery uses the private CGS/SkyLight API; every symbol is
 * weak-imported and `rcs_is_available()` reports whether they resolved, so the caller
 * can fall back to ordinary activation on a macOS that removes them.
 */

/** Where a window sits relative to its display's Spaces. Indices are zero-based,
 *  left-to-right in Mission Control order, and include full-screen Spaces. */
typedef struct {
    char displayIdentifier[128]; /**< UUID string of the display the window's Space belongs to */
    unsigned int spaceIndex;     /**< Index of the window's Space on that display */
    unsigned int currentIndex;   /**< Index of that display's currently active Space */
    unsigned int spaceCount;     /**< Number of Spaces on that display */
} RCSWindowLocation;

typedef enum {
    RCSDirectionLeft = 0,  /**< Towards lower indices */
    RCSDirectionRight = 1  /**< Towards higher indices */
} RCSDirection;

/** True when the private CGS symbols resolved at load time. */
bool rcs_is_available(void);

/** Locates `windowID` (a CGWindowID). Returns false if CGS is unavailable, the window is
 *  on no Space, or it is on several (e.g. assigned to all desktops, hence always visible). */
bool rcs_locate_window(uint32_t windowID, RCSWindowLocation *out);

/** True when the pointer is currently on the display with this identifier. The Dock applies
 *  a swipe to the display under the pointer, so callers check this before switching. */
bool rcs_pointer_is_on_display(const char *displayIdentifier);

/** Moves the pointer to the centre of the display with this identifier. */
bool rcs_move_pointer_to_display(const char *displayIdentifier);

/** Posts `steps` instant swipes in `direction`. Each is a began/changed/ended triple, as
 *  the Dock requires. Returns false if any event could not be created or posted. */
bool rcs_post_space_switch(RCSDirection direction, unsigned int steps);

#endif /* SPACE_SWITCH_KIT_H */
