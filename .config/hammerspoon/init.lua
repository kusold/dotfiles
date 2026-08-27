require("hs.ipc")

-- The Stream Deck is one device with process-wide singletons hanging off it —
-- discovery, the button callback, the encoder callback, the screen callback — so
-- nothing claims it directly. The StreamDeck spoon owns those and hands out keys,
-- knobs, strip segments and the device itself; every other spoon here claims what it
-- wants from that broker.
--
-- Hammerspoon claims the deck exclusively over USB, so Elgato's own Stream Deck app
-- must not be running for any of this to attach.
hs.loadSpoon("StreamDeck")
hs.loadSpoon("StreamDeckMedia")
hs.loadSpoon("ClaudeUsage")
hs.loadSpoon("NextEvent")
hs.loadSpoon("Amphetamine")
hs.loadSpoon("SlackStatus")
hs.loadSpoon("WindowGrid")
hs.loadSpoon("SystemState")
hs.loadSpoon("InputLevel")

-- Every key surface is handed the deck, because painting a key needs it. What they are
-- handed is the broker's stand-in rather than the device itself, which changes nothing
-- for them: it forwards everything, and only withholds key writes while a full-deck page
-- is up. Painting is still not arbitrated *between* surfaces, so they stay off each other
-- only by being configured onto different keys — one surface per key, and the addKey()
-- claims below are where to read which.
--
-- Presses are the opposite. hs.streamdeck:buttonCallback() is per-device and reports
-- every key, so the broker owns the one callback and hands out keys individually, the
-- way it already does knobs and strip segments. ClaudeUsage can install that callback
-- itself and does by default, which would make it answer for NextEvent's key as well
-- as its own; manageButtonCallback is how it is told not to, leaving each key's press
-- to the claim below.
spoon.ClaudeUsage.manageButtonCallback = false

spoon.StreamDeck:addSurface(function(dev) spoon.ClaudeUsage:setStreamDeckDevice(dev) end)
spoon.StreamDeck:addSurface(function(dev) spoon.NextEvent:setStreamDeckDevice(dev) end)
spoon.StreamDeck:addSurface(function(dev) spoon.Amphetamine:setStreamDeckDevice(dev) end)
spoon.StreamDeck:addSurface(function(dev) spoon.SlackStatus:setStreamDeckDevice(dev) end)
spoon.StreamDeck:addSurface(function(dev) spoon.WindowGrid:setStreamDeckDevice(dev) end)
spoon.StreamDeck:addSurface(function(dev) spoon.SystemState:setStreamDeckDevice(dev) end)

-- SlackStatus, WindowGrid, Amphetamine and SystemState take a second claim the others do
-- not, because each opens a page over the whole deck rather than changing its own key.
-- Covering keys that belong to other spoons means holding those still for as long as
-- the page is up, and the broker is the only thing that can. See StreamDeck:holdKeys().
--
-- Only one page can be up at a time, and that arbitration is the broker's: holdKeys()
-- replaces whatever page was there rather than stacking behind it.
spoon.SlackStatus:setBroker(spoon.StreamDeck)
spoon.WindowGrid:setBroker(spoon.StreamDeck)
spoon.Amphetamine:setBroker(spoon.StreamDeck)
spoon.SystemState:setBroker(spoon.StreamDeck)

-- Each spoon exposes the action and the config decides which key reaches it, since
-- which key is free is a fact about the deck rather than about either spoon. `pressed`
-- is false on the release, and acting on both would fire twice per tap.
spoon.StreamDeck:addKey(1, function(pressed) if pressed then spoon.ClaudeUsage:openUsage() end end)
spoon.StreamDeck:addKey(2, function(pressed) if pressed then spoon.NextEvent:toggleCalendar() end end)

-- Amphetamine is the exception to the `pressed` test above, and gets both edges: it
-- tells a tap from a hold by how long the key is down, so the release is half of its
-- input rather than a duplicate of the press. Tap toggles, hold opens the session-length
-- page across the deck.
spoon.StreamDeck:addKey(3, function(pressed) spoon.Amphetamine:handlePress(pressed) end)

-- SlackStatus splits a press the same way and for the same reason: a tap goes to Slack, a
-- hold opens the status presets across the deck.
spoon.StreamDeck:addKey(4, function(pressed) spoon.SlackStatus:handlePress(pressed) end)

-- WindowGrid's page opens on a plain tap, where SlackStatus's needs a hold: a key with
-- something else to do has to tell the two presses apart, and this one has nothing else to
-- do — reaching for it is reaching for the layouts. It goes on the second row, under the
-- first key, which the claims above leave free.
spoon.StreamDeck:addKey(5, function(pressed) if pressed then spoon.WindowGrid:openPage() end end)

-- SystemState opens on a plain tap too, for the same reason WindowGrid's does: nothing
-- else is reached for through this key. It goes on the second row, leaving keys 7 and 8
-- free.
spoon.StreamDeck:addKey(6, function(pressed) if pressed then spoon.SystemState:openPage() end end)

spoon.StreamDeck:start()

-- The poller runs headless; each surface it feeds is claimed explicitly.
spoon.ClaudeUsage:start()
spoon.ClaudeUsage:startMenubar()

-- Reads the calendar out of process, through a helper bundle that holds the calendar
-- permission Hammerspoon itself cannot be granted. See NextEvent's init.lua.
spoon.NextEvent:start()

-- Starts the poll loop, not a session. Amphetamine is driven over AppleScript, so the
-- first read raises the prompt to let Hammerspoon control it; until that is granted the
-- key shows "allow access".
spoon.Amphetamine:start()

-- Reads Slack's unread count off its Dock badge, which is the only count available
-- without a workspace token, and needs Slack kept in the Dock to have one. Setting a
-- status types Slack's own /status command into Slackbot's conversation — read
-- SlackStatus/status.lua before changing where it types.
spoon.SlackStatus:start()

-- WindowGrid and SystemState have no start() to call and are left out of this run of
-- them deliberately: neither polls anything or keeps state between presses, so being
-- handed a device above is the whole of their setup. See their init.lua files.

-- Volume on the leftmost knob, transport on the third knob, each with the strip
-- segment above it. Ordering inside start() is the spoon's problem now.
spoon.StreamDeckMedia:start()

-- Mic peak level and clipping on the middle knob, with the strip segment above it.
-- Claims that knob and segment directly against the broker; needs no addSurface()
-- since it never touches a key. See InputLevel.spoon for the helper app this leans on.
spoon.InputLevel:start()
