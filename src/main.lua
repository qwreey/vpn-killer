_G.process = require('process').globalProcess()
local uv = require('uv')

local dns = require('dns')
dns.loadResolver()

if jit.os ~= 'Windows' then
    local sig = uv.new_signal()
    uv.signal_start(sig, 'sigpipe')
    uv.unref(sig)
end

_G.require = require

local success, err = xpcall(function ()
    -- Call the main app inside a coroutine
    local utils = require('utils')

    local thread = coroutine.create(require)
    utils.assertResume(thread, "./init")

    -- Start the event loop
    uv.run()
end, function(err)
    -- During a stack overflow error, this can fail due to exhausting the remaining stack.
    -- We can't recover from that failure, but wrapping it in a pcall allows us to still
    -- return the stack overflow error even if the 'process.uncaughtException' fails to emit
    pcall(function() require('hooks'):emit('process.uncaughtException',err) end)
  return debug.traceback(err)
end)

if success then
    -- Allow actions to run at process exit.
    require('hooks'):emit('process.exit')
    uv.run()
else
    _G.process.exitCode = -1
    require('pretty-print').stderr:write("Uncaught exception:\n" .. err .. "\n")
end

local function isFileHandle(handle, name, fd)
    return _G.process[name].handle == handle and uv.guess_handle(fd) == 'file'
end
local function isStdioFileHandle(handle)
    return isFileHandle(handle, 'stdin', 0) or isFileHandle(handle, 'stdout', 1) or isFileHandle(handle, 'stderr', 2)
end

-- When the loop exits, close all unclosed uv handles (flushing any streams found).
uv.walk(function (handle)
    if handle then
        local function close()
            if not handle:is_closing() then handle:close() end
        end
        -- The isStdioFileHandle check is a hacky way to avoid an abort when a stdio handle is a pipe to a file
        -- TODO: Fix this in a better way, see https://github.com/luvit/luvit/issues/1094
        if handle.shutdown and not isStdioFileHandle(handle) then
            handle:shutdown(close)
        else
            close()
        end
    end
end)
uv.run()