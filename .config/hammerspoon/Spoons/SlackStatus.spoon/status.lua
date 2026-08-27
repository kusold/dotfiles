--- === SlackStatus.status ===
---
--- Setting the status, by typing Slack's own /status command into Slack.
---
--- There is no quieter way in. Slack ships no AppleScript dictionary — `sdef` against the
--- app reports no commands at all — so there is nothing to send it an Apple Event about,
--- the way Amphetamine is driven. Its Web API would do this properly, but wants an OAuth
--- token, and a token is what this config was deliberately built without. What is left is
--- the command Slack already offers its own users, driven the way a user drives it.
---
--- That is the whole risk of this approach, and it is worth stating plainly: these are
--- keystrokes, and keystrokes go wherever the focus is. A slash command typed into a
--- composer that does not recognise it is not a failed command — it is a message, sent to
--- whoever is on the other end of that conversation.
---
--- Three things keep that from mattering.
---
---  * The command is typed into a conversation chosen here rather than into whatever
---    Slack happened to have open. The default is Slackbot's, where the worst a misfire
---    can do is leave a line in a conversation with a bot that nobody else can see.
---  * Slack is brought to the front first and the keystrokes are only sent once it is
---    actually frontmost, so they cannot be delivered to the app the user was using.
---  * Whatever was in front comes back afterwards, on the failing paths as well as the
---    working one: a run that gave up halfway has still taken the screen.
---
--- The emoji is typed in its `:name:` form, closing colon included. Slack opens an
--- autocomplete list part way through typing one of those and closes it again on the
--- closing colon, and settleDelay is the pause that lets it: a Return arriving while that
--- list is still open picks from the list instead of sending the line.

return function(cfg)

local M = {}

-- One run at a time. Two overlapping runs would interleave their keystrokes into the same
-- composer, and the line that came out would be neither of the two statuses asked for.
local busy = false

local function slackApp()
    return hs.application.get(cfg.bundleID) or hs.application.find("Slack")
end

--- SlackStatus.status.command(preset) -> string
--- Function
--- The command line a preset sends. A preset with `clear = true` clears the status.
function M.command(preset)
    if preset.clear then return cfg.command .. " clear" end

    local parts = {cfg.command}
    if preset.emoji then table.insert(parts, preset.emoji) end
    if preset.text then table.insert(parts, preset.text) end
    return table.concat(parts, " ")
end

--- Run a list of {wait, act} steps in order, waiting after each. Written as a list rather
--- than nested callbacks because that is what it is: a sequence of keystrokes with pauses
--- between them, where nesting would bury every step one closure deeper than the last.
local function run(steps, index, done)
    local step = steps[index]
    if not step then return done(nil) end

    local ok, err = pcall(step.act)
    if not ok then return done(tostring(err)) end

    hs.timer.doAfter(step.wait, function() run(steps, index + 1, done) end)
end

--- Call fn(true) once app is frontmost, or fn(false) if it has not got there by deadline.
---
--- Polled rather than watched because this waits on one activation that has already been
--- asked for, and wants to carry on the instant it lands; a watcher would be a
--- subscription set up and torn down for a single event a fraction of a second away.
local function whenFrontmost(app, deadline, fn)
    local front = hs.application.frontmostApplication()
    if front and front:pid() == app:pid() then return fn(true) end
    if hs.timer.secondsSinceEpoch() >= deadline then return fn(false) end
    hs.timer.doAfter(0.05, function() whenFrontmost(app, deadline, fn) end)
end

--- SlackStatus.status.set(preset, done)
--- Function
--- Set (or clear) the Slack status for a preset, then give focus back.
---
--- done is called as done(ok, err) once the keystrokes have been sent. `ok` says the run
--- completed, not that Slack accepted the command: nothing is read back, because the only
--- thing that could read it back is the API this file exists to avoid needing.
function M.set(preset, done)
    done = done or function() end

    if busy then return done(false, "a status change is already going through") end

    local slack = slackApp()
    if not slack then return done(false, "Slack is not running") end

    local previous = hs.application.frontmostApplication()
    local line = M.command(preset)
    busy = true

    local function finish(err)
        busy = false
        if cfg.restoreFocus and previous and previous:pid() ~= slack:pid() then
            pcall(function() previous:activate() end)
        end
        if err then hs.printf("[SlackStatus] %s", err) end
        done(err == nil, err)
    end

    slack:activate()
    whenFrontmost(slack, hs.timer.secondsSinceEpoch() + cfg.activateTimeout, function(focused)
        if not focused then
            return finish("Slack did not come to the front in " .. cfg.activateTimeout .. "s")
        end

        local steps = {}

        local function press(mods, key, wait)
            table.insert(steps, {wait = wait, act = function()
                hs.eventtap.keyStroke(mods, key, 0)
            end})
        end

        local function typeText(text, wait)
            table.insert(steps, {wait = wait, act = function()
                hs.eventtap.keyStrokes(text)
            end})
        end

        if cfg.conversation then
            -- Slack's quick switcher, then the conversation by name. This is the step
            -- that makes a misfire harmless, so it runs before anything is typed that
            -- could be sent.
            press({"cmd"}, "k", cfg.stepDelay)
            typeText(cfg.conversation, cfg.typeDelay)
            press({}, "return", cfg.typeDelay)
        end

        typeText(line, cfg.settleDelay)
        press({}, "return", cfg.stepDelay)

        if cfg.conversation and cfg.returnToConversation then
            -- Back to whatever conversation was open before the switcher, so setting a
            -- status does not also quietly move the user to Slackbot and leave them there.
            press({"cmd"}, "[", cfg.stepDelay)
        end

        run(steps, 1, finish)
    end)
end

return M

end
