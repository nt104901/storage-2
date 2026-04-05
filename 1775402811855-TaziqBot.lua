local events = require('samp.events')
local angle = require ('vector3d')

local state = false
local count = 0

function main()
    repeat wait(0) until isSampAvailable()
    SendMessage('Loaded')
    sampRegisterChatCommand('tbot', function()
        if isCharInAnyCar(PLAYER_PED) then
            state = not state
            if not state then
                setCarProofs(storeCarCharIsInNoSave(PLAYER_PED), false, false, false, false, false)
            else
                id = select(2, sampGetVehicleIdByCarHandle(getCarCharIsUsing(PLAYER_PED)))
            end
            SendMessage(state and 'Work!' or 'Off')
        else
            if state then
                state = not state
                SendMessage(state and 'Work!' or 'On')
            else
                SendMessage('Not in car!!')
            end
        end
    end)
    while true do wait(0)
        if state then
            if isCharInAnyCar(PLAYER_PED) then
                blip, x, y, z = SearchMarker()
                if blip then
                    PLAYER_POS = {getCharCoordinates(PLAYER_PED)}
                    if getDistanceBetweenCoords3d(x, y, z, PLAYER_POS[1], PLAYER_POS[2], PLAYER_POS[3]) > 7 then
                        DISTANCE = getDistanceBetweenCoords3d(x, y, z, PLAYER_POS[1], PLAYER_POS[2], PLAYER_POS[3])
                        angleX = x - PLAYER_POS[1]
                        angleY = y - PLAYER_POS[2]
                        angleZ = z - PLAYER_POS[3]
                        local ang = angle(angleX, angleY, angleZ)
                        local data = samp_create_sync_data(incar and "vehicle" or "player")
                        ang:normalize()
                        PLAYER_POS[1] = PLAYER_POS[1] + ang.x * 7
                        PLAYER_POS[2] = PLAYER_POS[2] + ang.y * 7
                        PLAYER_POS[3] = PLAYER_POS[3] - 2 + ang.z * 2
                        VEHICLE_SYNC(id, PLAYER_POS[1], PLAYER_POS[2], PLAYER_POS[3], true)
                        setCharCoordinates(PLAYER_PED, PLAYER_POS[1], PLAYER_POS[2], PLAYER_POS[3])
                        printStringNow(math.floor(DISTANCE), 1000)
                        SetAngle(x, y, z)
                        count = count + 1
                        if count >= 7 then
                            count = 0
                            wait(800)
                        end    
                    else
                        setCharCoordinates(PLAYER_PED, x, y, z - 7)
                        VEHICLE_SYNC(id, x, y, z - 7, false)
                        wait(3500)
                    end
                else
                    printStringNow('trying to found checkpoint', 1000)
                end
            else
                SendMessage('Not in car')
                state = false
            end
        end
    end
end

lua_thread.create(function()
    while true do wait(0)
        if state and isCharInAnyCar(PLAYER_PED) then
            setCarRoll(storeCarCharIsInNoSave(PLAYER_PED), 0)
            setCarForwardSpeed(storeCarCharIsInNoSave(PLAYER_PED), 0)
            setCarProofs(storeCarCharIsInNoSave(PLAYER_PED), true, true, true, true, true)
        end
    end
end)

function SetAngle(x, y, z)
    local PLAYER_POS = {getCharCoordinates(PLAYER_PED)}
    local HX = x - PLAYER_POS[1]
    local HY = y - PLAYER_POS[2]
    local zAngle = getHeadingFromVector2d(HX, HY)
    if isCharInAnyCar(PLAYER_PED) then
        local _, handle = sampGetCarHandleBySampVehicleId(id)
        setCarHeading(handle, zAngle)
    end
end

function VEHICLE_SYNC(vehicleId, x, y, z, speed)
    local data = samp_create_sync_data('vehicle')
    data.vehicleId = tonumber(vehicleId)
    if speed then
        data.moveSpeed = {0.2, 0.2, 0.1}
    else
        data.moveSpeed = {0.0, 0.0, 0.0}
    end
    data.position = {x, y, z}
    data.send()
end

function events.onSendVehicleSync(data)
    if state then
        return false
    end
end

function events.onSendUnoccupiedSync() if state then return false end end

function samp_create_sync_data(sync_type, copy_from_player)
    local ffi = require 'ffi' local sampfuncs = require 'sampfuncs'
    local raknet = require 'samp.raknet' copy_from_player = copy_from_player or true
    local sync_traits = {
        player = {'PlayerSyncData', raknet.PACKET.PLAYER_SYNC, sampStorePlayerOnfootData},
        vehicle = {'VehicleSyncData', raknet.PACKET.VEHICLE_SYNC, sampStorePlayerIncarData},
        passenger = {'PassengerSyncData', raknet.PACKET.PASSENGER_SYNC, sampStorePlayerPassengerData},
        aim = {'AimSyncData', raknet.PACKET.AIM_SYNC, sampStorePlayerAimData},
        trailer = {'TrailerSyncData', raknet.PACKET.TRAILER_SYNC, sampStorePlayerTrailerData},
        unoccupied = {'UnoccupiedSyncData', raknet.PACKET.UNOCCUPIED_SYNC, nil},
        bullet = {'BulletSyncData', raknet.PACKET.BULLET_SYNC, nil},
        spectator = {'SpectatorSyncData', raknet.PACKET.SPECTATOR_SYNC, nil}
    }
    local sync_info = sync_traits[sync_type] local data_type = 'struct ' .. sync_info[1]
    local data = ffi.new(data_type, {})
    local raw_data_ptr = tonumber(ffi.cast('uintptr_t', ffi.new(data_type .. '*', data)))
    if copy_from_player then local copy_func = sync_info[3]
        if copy_func then local _, player_id if copy_from_player == true then
            _, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED) else
            player_id = tonumber(copy_from_player) end
            copy_func(player_id, raw_data_ptr) end
    end
    local func_send = function() local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, sync_info[2])
        raknetBitStreamWriteBuffer(bs, raw_data_ptr, ffi.sizeof(data))
        raknetSendBitStreamEx(bs, sampfuncs.HIGH_PRIORITY, sampfuncs.UNRELIABLE_SEQUENCED, 1)
        raknetDeleteBitStream(bs)
    end
    local mt = {
        __index = function(t, index) return data[index] end,
        __newindex = function(t, index, value) data[index] = value
        end
    }
    return setmetatable({send = func_send}, mt)
end

function SearchMarker(posX, posY, posZ)
    local ret_posX = 0.0
    local ret_posY = 0.0
    local ret_posZ = 0.0
    local isFind = false
    for id = 0, 31 do
        local MarkerStruct = 0
        MarkerStruct = 0xC7F168 + id * 56
        local MarkerPosX = representIntAsFloat(readMemory(MarkerStruct + 0, 4, false))
        local MarkerPosY = representIntAsFloat(readMemory(MarkerStruct + 4, 4, false))
        local MarkerPosZ = representIntAsFloat(readMemory(MarkerStruct + 8, 4, false))
        if MarkerPosX ~= 0.0 or MarkerPosY ~= 0.0 or MarkerPosZ ~= 0.0 then
            ret_posX = MarkerPosX
            ret_posY = MarkerPosY
            ret_posZ = MarkerPosZ
            isFind = true
        end
    end
    return isFind, ret_posX, ret_posY, ret_posZ
end

function SendMessage(t) return sampAddChatMessage('{696969}[TaziqBot]:{FFFFFF} '..t, -1) end