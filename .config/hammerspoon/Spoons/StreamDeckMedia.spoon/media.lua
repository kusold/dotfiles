--- === StreamDeckMedia.media ===
---
--- Media transport on a Stream Deck Plus knob: turn it right for the next track,
--- left for the previous one, and press it to play or pause. The strip segment above
--- it shows those same three controls, with the middle glyph following the play
--- state, and tapping the segment opens a full-width view of the track — artwork,
--- title, artist, album and progress — across the whole strip.
---
--- Like the volume knob, this posts the same media-key events the keyboard's
--- transport keys post rather than driving a particular player. That is what lets
--- it follow whatever macOS currently considers the media app — Music, Spotify, a
--- browser tab — without knowing that any of them exist, and it inherits the
--- system's own answer to "which one" when several are open. The readout comes from
--- that same session, via the nowplaying module, so the two always agree about what
--- they mean.
---
--- The one thing a transport knob needs that a volume knob does not is a brake. A
--- volume detent is worth a small change and a spin of them is worth a large one,
--- so the volume knob can act on every detent; a track skip does not subdivide that
--- way, and one flick of the wrist reports enough detents to walk off the end of an
--- album. So turns here are rate limited rather than accumulated: the detent that
--- opens a turn acts at once, and the ones arriving behind it are dropped until
--- the cooldown is up. Keeping the knob moving still skips repeatedly, at a pace
--- you can follow.

return function(cfg, deck, draw, nowplaying)

local M = {}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local lastSkip = nil     -- secondsSinceEpoch of the skip we last let through
local lastDir = nil      -- direction of that skip
local token = nil        -- our nowplaying.subscribe() token
local catchUp = nil      -- debounced post-command refresh
local viewTimer = nil    -- repaints the view while it is up
local viewExpiry = nil   -- releases the strip when the view times out
local started = false

-- ---------------------------------------------------------------------------
-- Transport
-- ---------------------------------------------------------------------------

local function press(key)
    -- Both halves or nothing: a down with no up does not repeat the key, it holds
    -- it, and a held transport key is stuck rather than fast.
    for _, isDown in ipairs({true, false}) do
        hs.eventtap.event.newSystemKeyEvent(key, isDown):post()
    end
end

-- A command changes the session a moment after it lands, and the poll that would
-- notice is up to the poll interval away. Debounced rather than fired per command,
-- so walking through five tracks costs one catch-up poll and not five.
local function scheduleCatchUp()
    if catchUp then catchUp:stop() end
    catchUp = hs.timer.doAfter(0.5, function() nowplaying.refresh() end)
end

--- StreamDeckMedia.media.skip(forward) -> boolean
--- Function
--- Send one track skip, unless the cooldown swallows it. Returns whether it went.
---
--- Reversing is exempt from the cooldown: a change of direction is a new gesture,
--- usually a correction of the skip that just happened, and making that one wait
--- reads as a dropped input rather than as a brake.
function M.skip(forward)
    local now = hs.timer.secondsSinceEpoch()
    local since = lastSkip and (now - lastSkip) or nil
    local go = since == nil or forward ~= lastDir or since >= cfg.mediaCooldown

    if cfg.mediaDebug then
        hs.printf("[StreamDeckMedia] media %-4s since=%-7s -> %s",
                  forward and "next" or "prev",
                  since and string.format("%.0fms", since * 1000) or "first",
                  go and "skip" or "swallowed")
    end
    if not go then return false end

    lastSkip, lastDir = now, forward
    press(forward and "NEXT" or "PREVIOUS")
    scheduleCatchUp()
    return true
end

--- StreamDeckMedia.media.togglePlay()
--- Function
--- Play or pause, by the same key the keyboard's play key sends.
---
--- One key for both directions is the system's design, not a shortcut taken here:
--- there is no separate pause event to send, and the player being toggled is the
--- one macOS would have toggled anyway.
function M.togglePlay()
    press("PLAY")
    scheduleCatchUp()
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Nothing to show covers two different situations, and neither is worth a different
-- readout: nothing is playing, or nowplaying cannot read the session at all. The knob
-- works either way, so both come out as the same absence of a track; the reason is
-- logged, which is where a reason belongs.
local function blank(s)
    return s.idle or s.unavailable or not (s.title or s.artist)
end

-- The transport glyphs, drawn as paths rather than set as text. Neither the triangles
-- nor the pause bars are in Menlo, so as text they land in whatever face the system
-- falls back to, which is free to be metrically unlike the rest of the strip and to
-- change out from under this. A triangle and an upright are not worth a font.
--
-- Each glyph is centred on (cx, cy) inside a box ICON_W by ICON_H and comes back as a
-- list of canvas elements carrying no fillColor, since the caller inks the row.
local ICON_W, ICON_H = 30, 26
local ICON_GAP = 16   -- between glyph boxes; the row is centred, not spread
local BAR_W = 4       -- the upright the prev and next glyphs skip off
local PAUSE_W = 7     -- the pause uprights, wider because they are the whole glyph

local function bar(x, cy, w)
    return {type = "rectangle", action = "fill",
            frame = {x = x, y = cy - ICON_H / 2, w = w, h = ICON_H}}
end

-- A filled triangle standing on its base edge at baseX and pointing at apexX, so one
-- helper draws it either way round.
local function wedge(apexX, baseX, cy)
    return {type = "segments", action = "fill", closed = true, coordinates = {
        {x = baseX, y = cy - ICON_H / 2},
        {x = baseX, y = cy + ICON_H / 2},
        {x = apexX, y = cy},
    }}
end

-- Skip glyphs get the upright rather than a second triangle: these send NEXT and
-- PREVIOUS, which land on a track boundary, and a double triangle is the icon for
-- scrubbing through one.
local function glyph(kind, cx, cy)
    local half = ICON_W / 2
    if kind == "prev" then
        return {bar(cx - half, cy, BAR_W),
                wedge(cx - half + BAR_W + 2, cx + half, cy)}
    elseif kind == "next" then
        return {wedge(cx + half - BAR_W - 2, cx - half, cy),
                bar(cx + half - BAR_W, cy, BAR_W)}
    elseif kind == "pause" then
        return {bar(cx - half + 4, cy, PAUSE_W),
                bar(cx + half - 4 - PAUSE_W, cy, PAUSE_W)}
    end
    return {wedge(cx + half - 4, cx - half + 4, cy)}   -- play
end

--- StreamDeckMedia.media.screenImage([snapshot]) -> hs.image
--- Function
--- The segment artwork: previous, play/pause and next, laid out in the order the
--- knob reads — turn left, press, turn right.
---
--- A legend for the knob, not three buttons: a press anywhere on this segment opens
--- the full-width view rather than working the transport under the finger. The knob
--- is already the faster way to skip a track, and the detail the view carries is the
--- one thing a segment this size cannot show at a size worth reading.
---
--- Public so it can be previewed with no deck connected: hs.canvas has no way to
--- show what it drew other than handing back the image.
function M.screenImage(snapshot)
    local s = snapshot or nowplaying.state()
    local W, H = deck().SEGMENT_W, deck().SEGMENT_H

    -- One ink for the whole row. The middle glyph already carries the play state, so
    -- the colour is left to carry whether there is a session behind it at all.
    local ink = blank(s) and draw.DIM or draw.FG
    local elements = {draw.background(W, H)}

    for i, kind in ipairs({"prev", s.playing and "pause" or "play", "next"}) do
        -- Sat around the centre at a fixed pitch rather than one to a third of the
        -- segment: spread that wide they read as three readouts, and they are one
        -- control with the knob under it.
        for _, element in ipairs(glyph(kind, W / 2 + (i - 2) * (ICON_W + ICON_GAP), H / 2)) do
            element.fillColor = ink
            elements[#elements + 1] = element
        end
    end
    return draw.render(W, H, elements)
end

-- ---------------------------------------------------------------------------
-- Full-width view
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.media.viewImage([snapshot]) -> hs.image
--- Function
--- The whole strip as one image: artwork, title, artist, album, progress.
---
--- Rendered whole and sliced by viewImages() rather than composed segment by
--- segment, so the layout is written once, in the coordinates it is read in.
function M.viewImage(snapshot)
    local sd = deck()
    local fullW = sd.SEGMENT_W * sd.SEGMENTS
    local H = sd.SEGMENT_H
    local s = snapshot or nowplaying.state()

    if blank(s) then
        return draw.render(fullW, H, {
            draw.background(fullW, H),
            {
                type = "text",
                text = s.unavailable and "No now-playing data" or "Nothing playing",
                frame = {x = 0, y = 38, w = fullW, h = 30},
                textColor = draw.DIM, textSize = 20,
                textAlignment = "center", textFont = draw.TITLE_FONT,
            },
        })
    end

    local elements = {draw.background(fullW, H)}

    -- Artwork square on the left, full bleed: the strip is 100 tall, so the art is
    -- 100x100 and everything else lives to the right of it.
    local art = nowplaying.artwork(s)
    table.insert(elements, art
        and {type = "image", image = art, frame = {x = 0, y = 0, w = H, h = H},
             imageScaling = "scaleToFit"}
        or {type = "rectangle", frame = {x = 0, y = 0, w = H, h = H},
            fillColor = draw.TRACK, action = "fill"})

    local left = H + 16
    local right = fullW - 16
    local textW = right - left

    local title, titleSize = draw.fitText(s.title or "", draw.TITLE_FONT, 30, 14, textW, 1)
    table.insert(elements, {
        type = "text", text = title,
        frame = {x = left, y = 6, w = textW, h = 40},
        textColor = draw.FG, textSize = titleSize, textFont = draw.TITLE_FONT,
    })

    -- Artist and album share a line. The album is the more expendable of the two, so
    -- it is what hangs off the separator rather than getting a line of its own.
    local byline = s.artist or ""
    if s.album and s.album ~= "" and s.album ~= s.title then
        byline = byline ~= "" and (byline .. "  ·  " .. s.album) or s.album
    end
    local line, lineSize = draw.fitText(byline, draw.BODY_FONT, 16, 11, textW, 1)
    table.insert(elements, {
        type = "text", text = line,
        frame = {x = left, y = 44, w = textW, h = 24},
        textColor = draw.DIM, textSize = lineSize, textFont = draw.BODY_FONT,
    })

    -- Progress. The clock gets a fixed column so the bar does not change length as
    -- the digits roll over.
    local position = nowplaying.position(s)
    local clockW = 108
    local barW = textW - clockW - 12
    local fraction = 0
    if s.duration and s.duration > 0 and position then
        fraction = math.max(0, math.min(1, position / s.duration))
    end

    table.insert(elements, {
        type = "rectangle", frame = {x = left, y = 78, w = barW, h = 8},
        fillColor = draw.TRACK, action = "fill",
        roundedRectRadii = {xRadius = 4, yRadius = 4},
    })
    if fraction > 0 then
        table.insert(elements, {
            type = "rectangle", frame = {x = left, y = 78, w = barW * fraction, h = 8},
            fillColor = s.playing and draw.BAR or draw.DIM, action = "fill",
            roundedRectRadii = {xRadius = 4, yRadius = 4},
        })
    end
    table.insert(elements, {
        type = "text", text = draw.clock(position) .. " / " .. draw.clock(s.duration),
        frame = {x = right - clockW, y = 72, w = clockW, h = 22},
        textColor = draw.DIM, textSize = 14,
        textAlignment = "right", textFont = draw.BODY_FONT,
    })

    return draw.render(fullW, H, elements)
end

--- StreamDeckMedia.media.viewImages() -> table
--- Function
--- The full-width view sliced into one image per strip segment.
---
--- setScreenImage() takes one segment at a time, so a view spanning the strip has to
--- arrive as one image per segment. Slicing a single render is what keeps the seams
--- invisible.
function M.viewImages()
    local sd = deck()
    local whole = M.viewImage()
    local images = {}
    for segment = 1, sd.SEGMENTS do
        images[segment] = whole:croppedCopy({
            x = (segment - 1) * sd.SEGMENT_W, y = 0,
            w = sd.SEGMENT_W, h = sd.SEGMENT_H,
        })
    end
    return images
end

local function stopViewTimers()
    if viewTimer then viewTimer:stop() end
    if viewExpiry then viewExpiry:stop() end
    viewTimer, viewExpiry = nil, nil
end

--- StreamDeckMedia.media.hideView()
--- Function
--- Dismiss the full-width view and give the strip back.
function M.hideView()
    stopViewTimers()
    deck():releaseStrip()
end

--- StreamDeckMedia.media.showView()
--- Function
--- Take the whole strip for the full-width view of the current track.
---
--- Refreshes the session on the way up: the view shows a position, and the snapshot
--- it would otherwise open with can be a whole poll interval stale.
function M.showView()
    local sd = deck()
    stopViewTimers()
    nowplaying.refresh()

    sd:holdStrip({
        paint = M.viewImages,
        -- Anywhere on the strip, any gesture: while this is up the strip has one
        -- meaning, and the way out of it should not be a target you have to find.
        touch = function() M.hideView() end,
    })

    viewTimer = hs.timer.doEvery(cfg.viewRefresh, function()
        -- Something else may have taken the strip in the meantime; the timer stops
        -- itself rather than repainting over whatever that was.
        if not sd:stripHeld() then return stopViewTimers() end
        -- A paused track has nothing to animate, and the subscription already
        -- repaints on a change of play state or track, so sitting on a paused view
        -- costs no writes however long it sits there.
        if not nowplaying.state().playing then return end
        sd:refreshHold()
    end)

    -- No expiry unless one is configured: the tap that opened this is the only thing
    -- that closes it, so hideView() has to be reachable from the strip itself. That
    -- is what the hold's touch handler above is for.
    if cfg.viewSeconds then
        viewExpiry = hs.timer.doAfter(cfg.viewSeconds, function() M.hideView() end)
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- StreamDeckMedia.media.start()
--- Function
--- Claim the knob and the strip segment above it, and follow the session.
function M.start()
    if started then return M end
    started = true
    local sd = deck()

    if cfg.mediaShowStrip then
        sd:addStrip(cfg.mediaEncoder, {
            paint = function() return M.screenImage() end,
            touch = function(kind)
                -- A swipe that begins here is not a tap on it: only presses open the
                -- view, which leaves strip-wide gestures free for something else.
                if kind == "shortPress" or kind == "longPress" then M.showView() end
            end,
        })
    end

    sd:addEncoder(cfg.mediaEncoder, function(pressed, left, right)
        if left or right then
            M.skip(right)
        elseif pressed then
            -- Presses report twice, once down and once up; acting on both would
            -- pause and immediately resume.
            M.togglePlay()
        end
    end)

    if not token then
        token = nowplaying.subscribe(function()
            sd:paintStrip(cfg.mediaEncoder)
            -- The view reads the same snapshot, and a track change under it should
            -- not have to wait for the next repaint tick to show.
            if sd:stripHeld() then sd:refreshHold() end
        end)
    end
    return M
end

--- StreamDeckMedia.media.stop()
--- Function
--- Release the knob and the strip segment, and stop following the session.
function M.stop()
    if not started then return M end
    started = false
    local sd = deck()
    M.hideView()
    sd:addEncoder(cfg.mediaEncoder, nil)
    sd:addStrip(cfg.mediaEncoder, nil)
    sd:blankStrip(cfg.mediaEncoder)

    if token then
        nowplaying.unsubscribe(token)
        token = nil
    end
    if catchUp then catchUp:stop() end
    catchUp = nil
    lastSkip, lastDir = nil, nil
    return M
end

return M

end
