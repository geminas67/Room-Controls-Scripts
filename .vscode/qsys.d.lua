---@meta
--[[
  Q-SYS Lua API stubs for Lua Language Server (sumneko/lua).
  Runtime is provided by Q-SYS Designer; these definitions only silence IDE diagnostics.
  https://help.qsys.com/Content/Control_Scripting/Using_Lua_in_Q-Sys/
]]--

---@class QSysControl
---@field String string
---@field Boolean boolean
---@field Value number
---@field Position number
---@field Color string
---@field Choices string[]
---@field EventHandler fun(ctl: QSysControl)|nil

---@class QSysControls
---@field [string] QSysControl

---@class QSysComponentInfo
---@field Name string
---@field Type string

---@class QSysComponent : QSysControl
---@field [string] QSysControl

---@class QSysComponentAPI
---@field New fun(name: string): QSysComponent
---@field GetComponents fun(): QSysComponentInfo[]
---@field GetControls fun(comp: QSysComponent): QSysControl[]

---@class QSysTimer
---@field EventHandler fun()|nil
---@field IsRunning boolean
function QSysTimer:Start(interval: number) end
function QSysTimer:Stop() end
function QSysTimer:Restart(interval: number) end

---@class QSysTimerAPI
---@field New fun(): QSysTimer

---@type QSysControls
Controls = {}

---@type QSysComponentAPI
Component = {}

---@type QSysTimerAPI
Timer = {}
