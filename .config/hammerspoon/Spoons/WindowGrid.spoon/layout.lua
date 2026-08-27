--- === WindowGrid.layout ===
---
--- Moving the focused window: onto a fraction of the screen it is on, or onto the screen
--- the pointer is on.
---
--- The window acted on is whatever had focus, and pressing a Stream Deck key does not
--- change that: the deck is read over USB rather than delivered as a keystroke, so no
--- app is activated by the press and hs.window.focusedWindow() still names the window
--- that was in front. This is the whole reason the page can act on "the window you are
--- looking at" without being told which one that is.
---
--- Nothing here paints. The only thing a press can report is that it did not happen, and
--- it says so through report() rather than by changing a key, because by the time the
--- answer is known the finger has left and the page may already be down.

return function(cfg)

local M = {}

--- Say that a press did nothing, and why.
---
--- An alert as well as the console line, because the failure cases all look identical
--- from the deck — a key that lights, clicks and leaves every window where it was. The
--- console is where the reason survives; the alert is what stops it reading as the deck
--- being broken. Set WindowGrid.alerts to false to keep only the console line.
local function report(message)
    hs.printf("[WindowGrid] %s", message)
    if cfg.alerts then
        hs.alert.show(message, cfg.alertDuration)
    end
end

--- Run fn against the focused window, having first got it out of full screen.
---
--- A window macOS has put in its own full-screen space cannot be moved or resized, and a
--- frame set on one is discarded without an error — the press would land, the window
--- would not move, and nothing would say why. Leaving the space is asked for first and
--- the move is made after it, on a timer, because setFullScreen() returns long before
--- the space animation it starts has finished and a frame set into the middle of that
--- animation is lost the same way. See WindowGrid.fullScreenDelay.
local function withWindow(fn)
    local win = hs.window.focusedWindow()
    if not win then
        report("no focused window")
        return
    end

    -- A window whose full-screen state cannot be read is treated as not being in one:
    -- the cost of guessing wrong that way is a move that does nothing, against a delay
    -- imposed on every ordinary window if it is guessed the other way.
    if win:isFullScreen() then
        win:setFullScreen(false)
        hs.timer.doAfter(cfg.fullScreenDelay, function()
            -- The window can be gone by the time this fires, and asking a dead window
            -- for its frame throws. There is nothing to recover here, only a callback
            -- that must not take the timer's caller down with it.
            local ok, err = pcall(fn, win)
            if not ok then report("could not place window: " .. tostring(err)) end
        end)
        return
    end

    local ok, err = pcall(fn, win)
    if not ok then report("could not place window: " .. tostring(err)) end
end

--- WindowGrid.layout.toUnit(unit)
--- Function
--- Put the focused window on the fraction of its screen given by an {x, y, w, h} in
--- screen fractions.
---
--- The fractions are of hs.screen:frame(), the part of the display left over once the
--- menu bar and the Dock have taken theirs, so a window sent to the full screen is the
--- largest one that is still entirely usable rather than one with its title bar behind
--- the menu bar.
function M.toUnit(unit)
    withWindow(function(win)
        win:moveToUnit({x = unit.x, y = unit.y, w = unit.w, h = unit.h}, cfg.animationDuration)
    end)
end

--- WindowGrid.layout.toPointerScreen()
--- Function
--- Move the focused window to the display the pointer is on, keeping its relative size
--- and position there.
---
--- The pointer is what says which screen is meant, because a Stream Deck press carries
--- no other clue: the deck sits on a desk in front of every monitor at once, and the
--- focused window is by definition on the screen you want it off. Point at where it
--- should go and press.
---
--- Moving it to the screen it is already on is left to happen rather than guarded
--- against. It resolves to the same relative frame, which is a window put back inside a
--- display it had been dragged half out of, and that is a better answer to a press than
--- nothing at all.
function M.toPointerScreen()
    local screen = hs.mouse.getCurrentScreen()
    if not screen then
        report("no screen under the pointer")
        return
    end

    withWindow(function(win)
        -- Resized to keep its share of the new screen, and held inside that screen's
        -- bounds: the two displays need not be the same size, and a window keeping its
        -- pixel dimensions across that is one that arrives too big to reach the corner
        -- of on the smaller of them.
        win:moveToScreen(screen, false, true, cfg.animationDuration)
    end)
end

--- WindowGrid.layout.screenCount() -> number
--- Function
--- How many displays are attached.
---
--- Asked by the surface, so that the key which moves a window between screens can say it
--- has nowhere to move one to.
function M.screenCount()
    return #hs.screen.allScreens()
end

return M

end
