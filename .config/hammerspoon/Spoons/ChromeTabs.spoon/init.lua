--- === ChromeTabs ===
---
--- Two tidying actions for Chrome, across every window: closeDuplicates() and
--- gatherTabs().
---
--- closeDuplicates() keeps one tab per address. Which one survives is decided in this
--- order: the tab showing in the frontmost window, then a tab showing in any window, then
--- the first one met reading windows front to back and tabs left to right. A tab you are looking at is never the one closed out from
--- under you, and nothing that is merely open beats it.
---
--- Incognito and normal windows are never matched against each other. The same address in
--- both is two sessions with different cookies, not a duplicate.
---
--- gatherTabs() collects tabs into named windows by site, per ChromeTabs.windowRules.
--- Windows rather than tab groups, because Chrome's AppleScript dictionary has no tab
--- groups in it, and an extension that could reach them is not something every Chrome
--- will load.
---
--- Both scripts run out of process through osascript rather than in process through
--- hs.osascript, for the reason Amphetamine.amphetamine gives: an Apple Event carries no
--- deadline of its own, and in process it would stall the main thread that also drives
--- every hotkey and Stream Deck press.
---
--- There is no start(): nothing here polls or keeps state between calls.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "ChromeTabs"
obj.version = "1.0"
obj.author = "kusold"
obj.license = "MIT"

--- ChromeTabs.bundleID
--- Variable
--- Bundle identifier of the browser to tidy. Default "com.google.Chrome".
---
--- Any Chromium browser that ships Chrome's AppleScript dictionary answers to the same
--- scripts.
obj.bundleID = "com.google.Chrome"

--- ChromeTabs.ignoreFragment
--- Variable
--- Whether two addresses differing only after "#" count as the same. Default false.
---
--- Off by default because apps that route on the fragment (Gmail's #inbox against
--- #sent, for one) put different pages behind it, and treating those as one would close
--- a page you meant to keep.
obj.ignoreFragment = false

--- ChromeTabs.windowRules
--- Variable
--- Which sites gatherTabs() collects into which window. Empty by default.
---
--- Keyed by window name, each mapping to a list of hosts, e.g.
--- `{Personal = {"news.ycombinator.com", "reddit.com"}}`. A host matches itself and any
--- subdomain of it. The window is the one given that name through Chrome's Name Window,
--- and is opened and named if there is none. Incognito windows are neither gathered from
--- nor into.
obj.windowRules = {}

--- ChromeTabs.commandTimeout
--- Variable
--- Seconds to wait for Chrome to answer before giving up. Default 10.
obj.commandTimeout = 10

-- `running` is checked before anything else is asked of Chrome, because addressing an
-- application's elements launches it, and tidying tabs must not open a browser that was
-- deliberately quit. Reading the property does not launch it.
--
-- Tabs are closed by id rather than by index: closing one shifts the index of every tab
-- after it in the same window, an id stays put.
local DUPLICATES_SCRIPT = [==[
function run(argv) {
    const chrome = Application(argv[0]);
    const ignoreFragment = argv[1] === "true";
    if (!chrome.running()) return JSON.stringify({closed: 0});

    // One Apple Event per property across every window, rather than one per tab: asking
    // tab by tab costs seconds once a few hundred tabs are open.
    const winIds = chrome.windows.id();
    const modes = chrome.windows.mode();
    const activeIds = chrome.windows.activeTab.id();
    const tabIds = chrome.windows.tabs.id();
    const urls = chrome.windows.tabs.url();

    const tabs = [];
    winIds.forEach((winId, w) => {
        tabIds[w].forEach((id, i) => {
            let url = urls[w][i];
            if (ignoreFragment) url = url.replace(/#.*$/, "");
            tabs.push({winId, id, key: modes[w] + " " + url, front: w === 0, active: id === activeIds[w]});
        });
    });

    const keep = {};
    const claim = pick => tabs.filter(pick).forEach(t => { if (!(t.key in keep)) keep[t.key] = t; });
    claim(t => t.front && t.active);
    claim(t => t.active);
    claim(() => true);

    let closed = 0;
    tabs.forEach(t => {
        if (keep[t.key] !== t) { chrome.windows.byId(t.winId).tabs.byId(t.id).close(); closed++; }
    });
    return JSON.stringify({closed});
}
]==]

-- Tabs are reopened in the target window and the originals closed, rather than moved:
-- Chrome's `move` of a tab to another window leaves a blank new tab there and the page
-- gone, with a new id, whether aimed at the window or at the end of its tabs. Reopening
-- reloads the page and drops its back history and anything typed and not yet submitted.
--
-- Windows and tabs are reread for each rule, because gathering for one can close a
-- window whose tabs all went.
local GATHER_SCRIPT = [==[
function hostOf(url) {
    const m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@\/?#]*@)?([^\/:?#]+)/i.exec(url);
    return m ? m[1].toLowerCase() : "";
}

function run(argv) {
    const chrome = Application(argv[0]);
    const rules = JSON.parse(argv[1]);
    if (!chrome.running()) return JSON.stringify({moved: 0});

    let moved = 0;
    for (const [name, hosts] of Object.entries(rules)) {
        const matches = url => {
            const host = hostOf(url);
            return hosts.some(h => host === h || host.endsWith("." + h));
        };

        const winIds = chrome.windows.id();
        const modes = chrome.windows.mode();
        const names = chrome.windows.givenName();
        const tabIds = chrome.windows.tabs.id();
        const urls = chrome.windows.tabs.url();

        const t = winIds.findIndex((_, w) => modes[w] === "normal" && names[w] === name);
        let target = t >= 0 ? winIds[t] : null;

        const loose = [];
        winIds.forEach((winId, w) => {
            if (modes[w] !== "normal" || winId === target) return;
            tabIds[w].forEach((id, i) => {
                if (matches(urls[w][i])) loose.push({winId, id, url: urls[w][i]});
            });
        });
        if (!loose.length) continue;

        // A new window comes with a new tab of its own, closed once the gathered ones
        // are in so that the window is never left empty and closing itself.
        let blank = null;
        if (target === null) {
            chrome.Window().make();
            target = chrome.windows[0].id();
            chrome.windows.byId(target).givenName = name;
            blank = chrome.windows.byId(target).tabs.id()[0];
        }

        const win = chrome.windows.byId(target);
        loose.forEach(tab => {
            win.tabs.push(chrome.Tab({url: tab.url}));
            chrome.windows.byId(tab.winId).tabs.byId(tab.id).close();
            moved++;
        });
        if (blank !== null) win.tabs.byId(blank).close();
    }
    return JSON.stringify({moved});
}
]==]

-- -1743 is TCC withholding Apple Events until Hammerspoon is granted Automation access to
-- Chrome, which is the one failure a person has to act on rather than read about.
local function describeError(exitCode, stderr)
    local message = (stderr or ""):gsub("%s+$", "")
    if message == "" then
        message = string.format("osascript exited %s", tostring(exitCode))
    end
    if message:match("%(%-1743%)%s*$") then
        return "Allow Hammerspoon to control Chrome in System Settings › Privacy & Security › Automation"
    end
    return message
end

-- Runs a script with argv and calls done(result, err) exactly once: result is the decoded
-- JSON it printed, or nil when it failed, in which case err says why.
function obj:_run(script, argv, done)
    local settled, watchdog, task = false, nil, nil

    local function settle(result, err)
        if settled then return end
        settled = true
        if watchdog then watchdog:stop(); watchdog = nil end
        done(result, err)
    end

    local args = {"-l", "JavaScript", "-e", script}
    for _, arg in ipairs(argv) do table.insert(args, arg) end

    task = hs.task.new("/usr/bin/osascript", function(exitCode, out, err)
        if exitCode ~= 0 then return settle(nil, describeError(exitCode, err)) end
        local ok, result = pcall(hs.json.decode, out or "")
        if not ok or type(result) ~= "table" then
            return settle(nil, "unreadable answer from osascript: " .. tostring(out))
        end
        settle(result, nil)
    end, args)

    if not task or not task:start() then
        return settle(nil, "could not run osascript")
    end

    -- Terminating the task makes its own callback fire in turn, which is what `settled`
    -- is for: the caller hears back exactly once either way.
    watchdog = hs.timer.doAfter(self.commandTimeout, function()
        watchdog = nil
        if settled then return end
        pcall(function() task:terminate() end)
        settle(nil, string.format("no answer from Chrome in %ss", tostring(self.commandTimeout)))
    end)
end

local function plural(n, word)
    return string.format("%d %s%s", n, word, n == 1 and "" or "s")
end

local function report(heading, err)
    hs.printf("ChromeTabs: %s", err)
    hs.alert.show(heading .. ": " .. err)
end

--- ChromeTabs:closeDuplicates([callback])
--- Method
--- Close every duplicate tab, then report how many went in an alert.
---
--- callback, if given, is called once as callback(closed, err): closed is the number of
--- tabs closed, or nil when the script failed, in which case err says why.
function obj:closeDuplicates(callback)
    self:_run(DUPLICATES_SCRIPT, {self.bundleID, tostring(self.ignoreFragment)}, function(result, err)
        local closed = result and result.closed
        if not err and type(closed) ~= "number" then err = "unreadable answer from osascript" end
        if err then
            closed = nil
            report("Duplicate tabs", err)
        elseif closed == 0 then
            hs.alert.show("No duplicate tabs")
        else
            hs.alert.show("Closed " .. plural(closed, "duplicate tab"))
        end
        if callback then callback(closed, err) end
    end)
    return self
end

--- ChromeTabs:gatherTabs([callback])
--- Method
--- Collect tabs into named windows per ChromeTabs.windowRules, then report how many
--- moved in an alert.
---
--- Each tab is reopened rather than moved, so it reloads; see GATHER_SCRIPT for why.
---
--- callback, if given, is called once as callback(moved, err), the way closeDuplicates()
--- calls its own.
function obj:gatherTabs(callback)
    self:_run(GATHER_SCRIPT, {self.bundleID, hs.json.encode(self.windowRules)}, function(result, err)
        local moved = result and result.moved
        if not err and type(moved) ~= "number" then err = "unreadable answer from osascript" end
        if err then
            moved = nil
            report("Gather tabs", err)
        elseif moved == 0 then
            hs.alert.show("Nothing to gather")
        else
            hs.alert.show("Gathered " .. plural(moved, "tab"))
        end
        if callback then callback(moved, err) end
    end)
    return self
end

--- ChromeTabs:bindHotkeys(mapping)
--- Method
--- Bind hotkeys. The actions are `closeDuplicates` and `gatherTabs`.
function obj:bindHotkeys(mapping)
    hs.spoons.bindHotkeysToSpec({
        closeDuplicates = function() self:closeDuplicates() end,
        gatherTabs = function() self:gatherTabs() end,
    }, mapping)
    return self
end

return obj
