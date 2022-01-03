--Copyright (c) 2015 - 2022 Llamageddon <asmageddon@gmail.com>
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

-- The library adds the following new features:
--  * An FPS limiter. Disabled by default
--  * Ability to add and enable/disable event callbacks
--  * Short-circuiting subsequent callbacks, by returning true from them, e.g. to capture input to UI
--  * Maintains one copy of the module only, preventing errors should multiple libraries include their own copy
--
-- The library adds the following new events:
--  * dispatch(event, ...) - A dispatch event, to which all events are sent
--  * pre_update(dt) - An event that runs before love.update()
--  * post_update(dt) - An event that runs after love.update()
--  * postprocess(draw_dt) - A second draw event, called after draw, can be used to draw overlay, profiling info, etc.
-- 
-- The library provides the following functions:
--  * modrun.setup() - Sets modrun up, replacing the original love.run
--  * modrun.registerEventType(event, fail_if_exists) - Registers a new event, issues a warning, or optionally an error, if the event already exists
--  * modrun.addCallback(event, callback, self_obj, on_error) - Registers a new callback for an event, optionally includes an error handler, and an object to be passed as "self"
--  * modrun.removeCallback(event, callback) - Removes a previously registered callback
--  * modrun.enableCallback(event, callback) - Enables a callback
--  * modrun.disableCallback(event, callback) - Disables a callback, preventing it from being processed
--  * modrun.setFramerateLimit(fps) - Set maximum FPS to the given value. Pass 0 or false to disable the limit. Only applies if vsync is disabled

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

modrun.handlers = {
    pre_quit = noop,

    pre_update = noop,
    post_update = noop,
    load = function(...)
        if love.load then love.load(...) end
    end,
    draw = function()
        if love.draw then love.draw() end
    end,
    postprocess = noop,
    update = function(dt)
        if love.update then love.update(dt) end
    end,
}
-- Dispatches events to base handlers, and calls callbacks
-- @param event - The name of the event for which the dispatch is being handled
-- @param ... - Arguments associated with the event
-- @returns `true` if any of the event handlers has returned `true`, `false` otherwise
function modrun.handlers.dispatch(event, ...)
    local args = {...}
    local cancel = false

    if event ~= "dispatch" then
        cancel = modrun.handlers[event](...)
        if cancel then return true end
        cancel = cancel or modrun.handlers.dispatch("dispatch", event, ...)
        if cancel then return true end
    end

    for _, cb_entry in pairs(modrun.callbacks[event] or {}) do
        local cb, err_handler, self_obj, enabled = cb_entry[1], cb_entry[2], cb_entry[3], cb_entry[4]

        if enabled then
            if err_handler == nil then
                -- If no error handler was provided, we just let the error propagate down the stack
                if self_obj then cb(self_obj, ...) else cb(...) end
            else
                -- If an error handler was passed, handle any potential errors via it
                local success, result
                if self_obj ~= nil then
                    success, result = xpcall(cb, function(err) debug.traceback(err) end, self_obj, ...)
                    if not success then
                        err_handler(self_obj, {event, ...}, result) -- Pass traceback as well
                    end
                else
                    success, result = xpcall(cb, function(err) debug.traceback(err) end, ...)
                    if not success then
                        err_handler({event, ...}, result) -- Pass traceback as well
                    end
                end
                if success then cancel = result end
            end
        end
        if cancel then return true end
    end

    return false
end
-- Default to love.handlers for any handlers not specified in the table
setmetatable(modrun.handlers, {__index = function(t, key) return rawget(love.handlers, key) end})

-- Each entry has the format of: { callback, on_error, self_obj, enabled }
modrun.callbacks = {} 

-- Register a new event type
-- @param event - The name of the event to be registered
-- @param fail_if_exists - (Optional) Throw an error if the event already exists
function modrun.registerEventType(event, fail_if_exists)
    if not modrun.handlers[event] then
        modrun.handlers[event] = noop
        modrun.callbacks[event] = modrun.callbacks[event] or {}
    else
        if fail_if_exists then
            error("[Error] Event type '" .. event .. "' is already registered.")
        else
            print("[Warning] Event type '" .. event .. "' is already registered.")
        end
    end
end

-- Add a callback function to be called on event
-- If the callback returns true, further callbacks will be blocked from running
-- @param event - The name of the event for which a callback is being registered
-- @param callback - The callback function
-- @param self_obj - (Optional) A value to pass as the first "self" parameter to the handler
-- @param on_error - (Optional) Error handler to invoke when the event handler throws an error
--     The following parameters are passed to the handler: 
--      * self_obj, if one was provided
--      * Event info, in format of {event, ...}
--      * The error traceback
function modrun.addCallback(event, callback, self_obj, on_error)
    error_check(event and modrun.handlers[event], "Unknown or invalid event type has been provided: '" .. tostring(event) .. "'")
    error_check(callback and type(callback) == "function", "No or invalid callback function has been provided: '" .. tostring(callback) .. "'")
    
    modrun.callbacks[event] = modrun.callbacks[event] or {}
    modrun.callbacks[event][callback] = {callback, on_error, self_obj, true }
end

-- Remove a callback
-- @param event - The name of the event for which a callback is being removed
-- @param callback - The callback function that was originally provided to modrun.addCallback
function modrun.removeCallback(event, callback)
    error_check(event and modrun.handlers[event], "Unknown or invalid event type has been provided: '" .. tostring(event) .. "'")
    error_check(callback and modrun.callbacks[event][callback], "Unregistered or invalid callback has been provided")
    
    modrun.callbacks[event][callback] = nil
end

-- Enable a callback
-- @param event - The name of the event for which a callback is being enabled
-- @param callback - The callback function that was originally provided to modrun.addCallback
function modrun.enableCallback(event, callback)
    error_check(event and modrun.handlers[event], "Unknown or invalid event type has been provided: '" .. tostring(event) .. "'")
    error_check(callback and modrun.callbacks[event][callback], "Unregistered or invalid callback has been provided")
    
    modrun.callbacks[event][callback][4] = true
end

-- Disable a callback
-- @param event - The name of the event for which a callback is being disabled
-- @param callback - The callback function that was originally provided to modrun.addCallback
function modrun.disableCallback(event, callback)
    error_check(event and modrun.handlers[event], "Unknown or invalid event type has been provided: '" .. tostring(event) .. "'")
    error_check(callback and modrun.callbacks[event][callback], "Unregistered or invalid callback has been provided")
    
    modrun.callbacks[event][callback][4] = false
end

-- Set framerate limit
-- @param fps - Desired number of frames per second
function modrun.setFramerateLimit(fps)
    modrun.max_fps = fps or 0
end

-- A simple function ran when love has been terminated
function modrun.shutdown()
    if love.audio then
        love.audio.stop()
    end
end

-- The run function to replace `love.run` 
function modrun.run()
    if love.event then love.event.pump() end
    modrun.handlers.dispatch("load", love.arg.parseGameArguments(arg), arg)
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
                    local abort_quit = modrun.handlers.dispatch(event, a, b, c, d, e, f)
                    if not abort_quit then modrun.shutdown(); return a or 0 end
                else
                    -- The rest of events can be handled normally
                    modrun.handlers.dispatch(event,a,b,c,d,e,f) -- Does not include update or draw
                end
            end
        end

        -- Update dt, as we'll be passing it to update
        if love.timer then modrun.deltatime = love.timer.step() end
        
        local before_update = love.timer.getTime()

        -- Call update and draw
        modrun.handlers.dispatch("pre_update", modrun.deltatime) -- will pass 0 if love.timer is disabled
        modrun.handlers.dispatch("update", modrun.deltatime) -- will pass 0 if love.timer is disabled
        modrun.handlers.dispatch("post_update", modrun.deltatime) -- will pass 0 if love.timer is disabled

        if love.graphics and love.graphics.isActive() then
            love.graphics.clear(love.graphics.getBackgroundColor())
            love.graphics.origin()
            local start = love.timer.getTime()
            modrun.handlers.dispatch("draw")
            modrun.handlers.dispatch("postprocess", love.timer.getTime() - start)
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
modrun._VERSION     = 'modrun v1.1.0'
modrun._URL         = 'http://github.com/Asmageddon/modrun'
modrun._LICENSE     = 'MIT LICENSE <http://www.opensource.org/licenses/mit-license.php>'

__modrun_singleton = modrun

return modrun
