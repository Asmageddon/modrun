--Copyright (c) 2015 - 2023 Llamageddon <asmageddon@gmail.com>
--
--Permission is hereby granted, free of charge, to any person obtaining a
--copy of this software and associated documentation files (the
--"Software"), to deal in the Software without restriction, including
--without limitation the rights to use, copy, modify, merge, publish,
--distribute, sublicense, and/or sell copies of the Software, and to
--permit persons to whom the Software is furnished to do so, subject to
--the following conditions:
--
--The above copyright notice and this permission notice shall be included
--in all copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
--OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
--MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
--IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
--CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
--TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
--SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

-- Only one instance of modrun can exist, if it is to function right
if __modrun_singleton then
    return __modrun_singleton
end

local modrun = {}

local function error_check(condition, message, level)
    return condition or error(message, (level or 1) + 1)
end

local noop = function() end

modrun.deltatime = 0
modrun.max_fps = 0

-- Extend love.handlers with new(pre, post, etc.) and previously-inlined(load,update,draw) functions
love.handlers = love.handlers or {}

love.handlers.pre_quit = noop
love.handlers.pre_update = noop
love.handlers.post_update = noop
love.handlers.postprocess = noop

love.handlers.load = function(...)
    if love.load then love.load(...) end
end
love.handlers.update = function(...)
    if love.update then love.update(...) end
end
love.handlers.draw = function()
    if love.draw then love.draw() end
end

-- Dispatches events to base handlers, and calls callbacks
-- @param event - The name of the event for which the dispatch is being handled
-- @param ... - Arguments associated with the event
-- @returns `true` if any of the event handlers has returned `true`, `false` otherwise

-- Dispatches the initial dispatch event for an event, which runs the handlers for both dispatch and the event itself
function modrun._dispatchEvent(event, ...)
    love.handlers.dispatch("dispatch", event, ...)
end

function love.handlers.dispatch(event, ...)
    for _, cb_entry in ipairs(modrun.sorted_enabled_callbacks[event] or {}) do
        -- local cb, err_handler, self_obj, enabled, priority = cb_entry[1], cb_entry[2], cb_entry[3], cb_entry[4], cb_entry[5]
        local cb, enabled, priority, err_handler, self_obj = cb_entry[1], cb_entry[2], cb_entry[3], cb_entry[4], cb_entry[5]
        local abort
        if not enabled then
            -- Pass, do nothing
        elseif err_handler == nil then
            -- If no error handler was provided, we just let the error propagate down the stack
            if self_obj then abort = cb(self_obj, ...) else abort = cb(...) end
        else
            -- If an error handler was passed, handle any potential errors via it
            local success, result
            if self_obj ~= nil then
                success, result = xpcall(cb, function(err) return err end, self_obj, ...)
                abort = result
                if not success then abort = err_handler(self_obj, result, cb, {...}) end
            else
                success, result = xpcall(cb, function(err) return err end, ...)
                abort = result
                if not success then abort = err_handler(result, cb, {...}) end
            end
        end
        if abort then return true end -- Short-circuit and cancel calling the rest of callbacks
    end

    return false
end
-- Each entry has the format of: { callback, enabled, priority, on_error, self_obj }
modrun.callbacks = {}
-- Sorted arrays of enabled callbacks for a given event
modrun.sorted_enabled_callbacks = {}

-- Register a new event type
-- @param event - The name of the event to be registered
-- @param fail_if_exists - (Optional) Throw an error if the event already exists
function modrun.registerEventType(event, fail_if_exists)
    if not love.handlers[event] then
        love.handlers[event] = noop
        modrun.callbacks[event] = modrun.callbacks[event] or {}
    else
        if fail_if_exists then
            error("[Error] Event type '" .. event .. "' is already registered.")
        else
            print("[Warning] Event type '" .. event .. "' is already registered.")
        end
    end
end

-- Behind-the-scenes function that performs callback operations, in order to have shared logic in one place.
local callback_actions = {add = true, remove = true, enable = true, disable = true}
function modrun._setCallback(action, event, callback, priority, self_obj, on_error)
    error_check(callback_actions[action], "Unknown action('" .. action .. "') specified. Must be one of: add, remove, enable, disable.", 2)
    error_check(event and rawget(love.handlers, event), "Unknown or invalid event type has been provided: '" .. tostring(event) .. "'", 2)
    if action == "add" then
        error_check(callback and type(callback) == "function", "No or invalid callback function has been provided: '" .. tostring(callback) .. "'", 2)
        modrun.callbacks[event] = modrun.callbacks[event] or {}
        modrun.callbacks[event][callback] = {callback, true, priority or 0, on_error, self_obj}
    else
        error_check(callback and modrun.callbacks[event][callback], "Unregistered or invalid callback has been provided", 2)
        if action == "remove" then
            modrun.callbacks[event][callback] = nil
        elseif action == "enable" then
            modrun.callbacks[event][callback][2] = true
        elseif action == "disable" then
            modrun.callbacks[event][callback][2] = false
        end
    end

    -- Re-sort the enabled callbacks table for the given event
    modrun.sorted_enabled_callbacks[event] = {}
    for _, cb_entry in pairs(modrun.callbacks[event] or {}) do
        if cb_entry[2] then -- If it's enabled
            table.insert(modrun.sorted_enabled_callbacks[event], cb_entry)
        end
    end
    table.sort(modrun.sorted_enabled_callbacks[event], function(a, b) return a[3] < b[3] end)
end

-- Add a callback function to be called on event
-- If the callback returns true, further callbacks will be blocked from running
-- @param event - The name of the event for which a callback is being registered
-- @param callback - The callback function
-- @param priority - Defines the order in which callbacks are executed, starting with lowest values
-- @param self_obj - (Optional) A value to pass as the first "self" parameter to the handler
-- @param on_error - (Optional) Error handler to invoke when the event handler throws an error
--     The following parameters are passed to the handler: 
--      * self_obj, if one was provided
--      * Event info, in format of {event, ...}
--      * The error traceback
function modrun.addCallback(event, callback, priority, self_obj, on_error)
    modrun._setCallback("add", event, callback, priority, self_obj, on_error)
end

-- Remove a callback
-- @param event - The name of the event for which a callback is being removed
-- @param callback - The callback function that was originally provided to modrun.addCallback
function modrun.removeCallback(event, callback)
    modrun._setCallback("remove", event, callback)
end

-- Enable a callback
-- @param event - The name of the event for which a callback is being enabled
-- @param callback - The callback function that was originally provided to modrun.addCallback
function modrun.enableCallback(event, callback)
    modrun._setCallback("enable", event, callback)
end

-- Disable a callback
-- @param event - The name of the event for which a callback is being disabled
-- @param callback - The callback function that was originally provided to modrun.addCallback
function modrun.disableCallback(event, callback)
    modrun._setCallback("disable", event, callback)
end

-- Set framerate limit
-- @param fps - Desired number of frames per second
function modrun.setFramerateLimit(fps)
    modrun.max_fps = fps or 0
end

-- A simple function ran when love has been terminated
function modrun._shutdown()
    if love.audio then
        love.audio.stop()
    end
end

-- The run function to replace `love.run` 
function modrun.run()
    for event, handler in pairs(love.handlers) do
        modrun.addCallback(event, handler, 0)
    end

    if love.event then love.event.pump() end
    ---@diagnostic disable-next-line: undefined-field
    modrun._dispatchEvent("load", love.arg.parseGameArguments(arg), arg)
    -- We don't want the first frame's dt to include time taken by love.load.
    if love.timer then love.timer.step() end

    modrun.deltatime = 0
    -- Main loop time.
    return function() -- Love2D wants a function it can call continuously rather than for love.run() to run a loop itself
        -- Process events.
        if love.event then
            love.event.pump()
            for event, a, b, c, d, e, f in love.event.poll() do
                -- Quit has to be handled as a special case
                if event == "quit" then
                    local abort_quit = modrun._dispatchEvent(event, a, b, c, d, e, f)
                    if not abort_quit then modrun._shutdown(); return a or 0 end
                else
                    -- The rest of events can be handled normally
                    modrun._dispatchEvent(event,a,b,c,d,e,f) -- Does not include update or draw
                end
            end
        end

        -- Update dt, as we'll be passing it to update
        if love.timer then modrun.deltatime = love.timer.step() end
        
        local before_update = love.timer.getTime()

        -- Call update and draw
        modrun._dispatchEvent("pre_update", modrun.deltatime) -- will pass 0 if love.timer is disabled
        modrun._dispatchEvent("update", modrun.deltatime) -- will pass 0 if love.timer is disabled
        modrun._dispatchEvent("post_update", modrun.deltatime) -- will pass 0 if love.timer is disabled

        if love.graphics and love.graphics.isActive() then
            love.graphics.clear(love.graphics.getBackgroundColor())
            love.graphics.origin()
            local start = love.timer.getTime()
            modrun._dispatchEvent("draw")
            modrun._dispatchEvent("postprocess", love.timer.getTime() - start)
            love.graphics.present()
        end
        
        if love.timer then love.timer.sleep(0.001) end
        
        -- If vsync is disabled, and FPS limit is enabled, enforce it
        local w, h, flags = love.window.getMode()
        if not flags.vsync and modrun.max_fps > 0 then
            local max_delta, delta = (1 / modrun.max_fps), love.timer.getTime() - before_update
            if delta < max_delta then love.timer.sleep(max_delta - delta) end
        end
    end
end

function modrun.setup()
    love.run = modrun.run
    return modrun
end

modrun._DESCRIPTION = 'An alternative run function module for Love2D with support for callbacks and additional events'
modrun._VERSION     = 'modrun v2.0.2'
modrun._URL         = 'http://github.com/Asmageddon/modrun'
modrun._LICENSE     = 'MIT LICENSE <http://www.opensource.org/licenses/mit-license.php>'

__modrun_singleton = modrun

return modrun