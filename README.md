# Features

## The library adds the following new features:
  * An FPS limiter, disabled by default
  * Ability to add and enable/disable event callbacks, including custom events.
  * Short-circuiting subsequent callbacks, if a callback or its error handler returns `true`, e.g. to capture input to UI
  * Maintains one copy of the module only, preventing errors should multiple libraries include their own copy

## The library adds the following new events:
  * **dispatch(event, ...)** - A dispatch event, to which all events are sent. **Warning**: a custom dispatch callback with priority of -5 will run before ALL other callbacks are dispatched from the default dispatch handler, e.g. before mousepressed or update callbacks with priority -20.
  * **pre_update(dt)** - An event that runs before love.update()
  * **post_update(dt)** - An event that runs after love.update()
  * **postprocess(draw_dt)** - A second draw event, called after draw, can be used to draw overlay, profiling info, etc.
 
## The library provides the following functions:
  * **modrun.setup()** - Sets modrun up, replacing the original love.run
  * **modrun.registerEventType(event, fail_if_exists)** - Registers a new event, issues a warning, or optionally an error, if the event already exists
  * **modrun.addCallback(event, callback, priority, self_obj, on_error)** - Registers a new callback for an event, optionally includes priority(`love.event` functions are 0, negative values will run earlier), an error handler, and an object to be passed as "self"
      * **on_error(err, cb, args)** - `err` is the error, `cb` the callback that produced it, `args` are arguments passed to the callback
      * **on_error(self_obj, err, cb, args)** - as above, but with `self_obj` passed as the `self` argument for the `function obj:fn(err, args)` format
  * **modrun.removeCallback(event, callback)** - Removes a previously registered callback
  * **modrun.enableCallback(event, callback)** - Enables a callback
  * **modrun.disableCallback(event, callback)** - Disables a callback, preventing it from being processed
  * **modrun.setFramerateLimit(fps)** - Set maximum FPS to the given value. Pass 0 or false to disable the limit. Only applies if vsync is disabled

For detailed documentation of function parameters and additional comments, check source.


# Usage 

```lua
-- To start using the library, simply do:
modrun = require "modrun".setup()

-- Example: Handle tweening library updates before love.update is run
modrun.addCallback("update", tween.update, -1)

-- Example: Implement a state handler, and handle all events using it
love.state = {}
modrun.addCallback("dispatch", function(event, ...) 
    if love.state ~= nil and love.state[event] ~= nil then 
        return love.state[event](...)
    end
end)
my_game = { update = function() end, keypressed = function() end }
love.state = my_game

-- Example: Add a callback with an error handler
function on_error(err, cb, args) print(debug.traceback(err)) end
modrun.addCallback("mousepressed", function() error("test error") end, nil, nil, on_error)

-- Example: Add a callback for an object, so the object is passed as the `self` argument
my_game = GameState()
function my_game:update(dt) self.do_stuff(dt) end
function my_game:on_error(err, cb, args) self.do_other_stuff(err) end
-- Without error handling
modrun.addCallback("update", GameState.update, nil, GameState)
-- Or with error handling
modrun.addCallback("update", GameState.update, nil, GameState, my_game.on_error)

-- Example: Don't process further callbacks after returning true:
-- Prevent quitting while the game is saving
modrun.addCallback("quit", function() return is_game_saving() end, -99)
-- Don't propagate events if an UI element was clicked
function ui_handler(x, y, button, ...) 
    if ui_element_clicked(x, y) return true end
end
modrun.addCallback("mousepressed", ui_handler, -99)
```


# Future directions

 - [ ] Run dispatch inbetween hooks, so that dispatch with priority -5 dispatches mouspressed AFTER a mousepressed callback with priority -10, rather than before like now. Maybe as a separate event type to support both behaviors?
 - [ ] Add table-of-callbacks operation for stuff like e.g. `modrun.addMultipleCallbacks(my_library.callbacks)` without having to manually add each.
 - [ ] Add an event that handles uncaught errors in other events(`uncaughterror` maybe?) in situations where not crashing the entire game is desired.