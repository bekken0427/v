local _ = function(...) return ... end

local term = require('term')
local os = require('os')
local V_ROOT = os.getenv("V_ROOT") or "/usr"
local component = require('component')

_(term.isAvailable() or os.exit(1))

print("V root is "..V_ROOT)

v = {HOME = os.getenv('HOME') or '/home', callbacks = {}, term = term, gpu = component.gpu}

-- TODO: load core of v
local vs = require('v-script')
local io = require('io')
local fs = require('filesystem')
local Buffer = require('v/buffer')
local event = require('event')
local exit
local ARGV = table.pack(...)


v.vscript = vs.Environment.new()
vs.stdlib.register(v.vscript)
v.keymap = require('v/keymap').new(v)

do
    local msfile = V_ROOT..'/share/v/vs/main.vs'
    local f, err = io.open(msfile)
    _(f or error("Could not load main script from "..msfile..": "..err))
    local code = f:read('*a')
    f:close()
    v.vscript:eval(code)
end

if fs.exists(v.HOME..'/.vrc') then
    f = io.open(v.HOME..'/.vrc')
    local code = f:read('*a')
    f:close()
    v.vscript:eval(code)
end

function v.exit(code)
    for i = 1, #(v.callbacks) do
        local cb = v.callbacks[i]
        event.ignore(cb.key, cb.value)
    end
    v = nil
    exit = code or 0
    term.clear()
end

function v.loadText(data, file, readonly)
    local w, h = component.gpu.getResolution()
    v.buf = Buffer.new(data, term, {w = w, h = h}, component.gpu)
    v.writable = not readonly
    v.file = file
end
v.loadText("")

function v.checkPermission(file, mode)
    local ret = true
    for i = 1, #mode do
        local m = mode:sub(i, i)
        if m == 'w' then
            if fs.get(file).isReadOnly() or not fs.exists(fs.path(file)) then
                return false
            end
        elseif m == 'r' then
            ret = fs.exists(file)
        elseif m == 'x' then
            -- nothing here. all files are executable in OpenOS
        else
            error("Unknown File Mode: "..m)
        end
        if not ret then return false end
    end
end

function v.loadFile(file, readonly)
    readonly = readonly or not v.checkPermission(file, "w")
    local exists = fs.exists(file)
    local data = ""
    if readonly and not exists then
        return false, "file not found"
    elseif exists then
        local f, err = io.open(file, "r")
        if not f then
            return false, err
        end
        data = f:read("*a")
        f:close()
    end
    v.loadText(data, file, readonly)
    return true, (exists and ("Read "..#data.." bytes") or ("[New File]"))
end

function v.save(file)
    if not v.buf.writable then
        return false, "File opened readonly"
    end
    if v.buf.modified then
        if file then
            if v.checkPermission(file, "w") then
                local f, err = io.open(file, "w")
                if not f then
                    return false, "Cannot write "..file..": "..err
                end
                f:write(v.buf.getData())
                f:close()
                v.file = file
                v.buf.modified = false
                return true
            else
                return false, "Cannot write "..file..": Permission denied"
            end
        else
            if not v.file then
                return false, "Please specify a file name"
            end
            v.save(v.file)
        end
    else
        if file then
            if v.checkPermission(file, "w") then
                fs.copy(v.file, file)
                v.file = file
                return true
            else
                return false, "Cannot write "..file..": Permission denied"
            end
        else
            return true
        end
    end
end

function v.listenEvent(name, listener)
    if event.listen(name, listener) then
        table.insert(v.callbacks, {key = name, value = listener})
        return true
    end
    return false
end

function v.doCommand()
    local line = v.buf:readLine()
    local s, m = pcall(runLisp, '('..line..')')
    if not s then
        if not v then
            error(m)
        end
        v.buf:setStatus(m, 'error')
    end
end

local function runLisp(code)
    return v.vscript:eval(code)
end

if #ARGV > 0 then
    v.loadFile(ARGV[1])
end

v.buf:update()
v.keymap:registerEvents()
v.keymap.enabled = true
v.keymap.mode = 'control'
term.setCursorBlink(true)

while true do
    if exit then
        os.exit(exit)
    end
    event.pull()

end
