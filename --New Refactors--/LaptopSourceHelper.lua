--[[
    Laptop Source Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-10-22
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the with Source Selection in Conferencing Spaces.
]]

-------------------[ Configuration ]-------------------
laptopHdmiIndex = 9 -- NVH32 Input AV3

rooms = {
    { dec = "decRmA", mixer = "mixPGMRmA" },
    { dec = "decRmB", mixer = "mixPGMRmB" },
}

-------------------[ Control References ]-------------------
roomRefs = {}

for _, cfg in ipairs(rooms) do
    roomRefs[#roomRefs + 1] = {
        dec = Component.New(cfg.dec),
        mixer = Component.New(cfg.mixer),
        mixerName = cfg.mixer,
    }
end

-------------------[ Functions ]-------------------

function syncMixerLaptopMute(room)
    local muted = room.dec["hdmi.out.1.select.index"].Value ~= laptopHdmiIndex
    room.mixer["input.2.mute"].Boolean = muted
    print(room.mixerName .. " Mute set " .. tostring(muted))
end

-------------------[ Event Handlers ]-------------------

for _, room in ipairs(roomRefs) do
    room.dec["hdmi.out.1.select.index"].EventHandler = function()
        syncMixerLaptopMute(room)
    end
    syncMixerLaptopMute(room)
end
