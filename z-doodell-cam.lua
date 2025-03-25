local function convert_s16(num)
    local min = -32768
    local max = 32767
    while (num < min) do
        num = max + (num - min)
    end
    while (num > max) do
        num = min + (num - max)
    end
    return num
end

local function lerp(a, b, t)
    return a * (1 - t) + b * t
end

local function approach_vec3f_asymptotic(current, target, multX, multY, multZ)
    local output = {x = 0, y = 0, z = 0}
    output.x = current.x + ((target.x - current.x)*multX)
    output.y = current.y + ((target.y - current.y)*multY)
    output.z = current.z + ((target.z - current.z)*multZ)
    return output
end

local function round(num)
    return num < 0.5 and math.floor(num) or math.ceil(num)
end

local function clamp(num, min, max)
    return math.min(math.max(num, min), max)
end

local OPTION_SQUISHYCAM = _G.charSelect.add_option("Doodell Cam", 1, 2, {"Off", "Squishy Only", "On"}, {"Toggles the unique camera", "built for Squishy's Moveset", (_G.OmmEnabled and "(Inactive with OMM Camera)" or "")}, true)

local cutsceneActExclude = {
    [ACT_WARP_DOOR_SPAWN] = true,
    [ACT_PULLING_DOOR] = true,
    [ACT_PUSHING_DOOR] = true,
    [ACT_UNLOCKING_KEY_DOOR] = true,
    [ACT_UNLOCKING_STAR_DOOR] = true,
    [ACT_ENTERING_STAR_DOOR] = true,
    
    [ACT_EMERGE_FROM_PIPE] = true,
    --[ACT_DISAPPEARED] = true,

    [ACT_PICKING_UP_BOWSER] = true,
    [ACT_HOLDING_BOWSER] = true,
    [ACT_RELEASING_BOWSER] = true,
    
    [ACT_RELEASING_BOWSER] = true,
}
local function is_mario_in_cutscene(m)
    if m.action & ACT_GROUP_MASK == ACT_GROUP_CUTSCENE and not cutsceneActExclude[m.action] then return true end
    if (m.area.camera and m.area.camera.cutscene ~= 0) then return true end
    return false
end

-- Settings
local OMM_SETTING_CAMERA = ""
-- Settings Toggles
local OMM_SETTING_CAMERA_ON = -1
if _G.OmmEnabled then
    OMM_SETTING_CAMERA = _G.OmmApi["OMM_SETTING_CAMERA"]
    OMM_SETTING_CAMERA_ON = _G.OmmApi["OMM_SETTING_CAMERA_ON"]
end

local function omm_camera_enabled(m)
    if not _G.OmmEnabled then return false end
    if _G.OmmApi.omm_get_setting(m, OMM_SETTING_CAMERA) == OMM_SETTING_CAMERA_ON then
        return true
    end
end

local function button_to_analog(m, negInput, posInput)
    local num = 0
    num = num - (m.controller.buttonDown & negInput ~= 0 and 127 or 0)
    num = num + (m.controller.buttonDown & posInput ~= 0 and 127 or 0)
    return num
end

local nonMomentumActs = {
    [ACT_SQUISHY_WALL_SLIDE] = true,
}
local nonCameraActs = {
    [ACT_READING_AUTOMATIC_DIALOG] = true,
    [ACT_READING_NPC_DIALOG] = true,
    [ACT_WAITING_FOR_DIALOG] = true,
    [ACT_IN_CANNON] = true
}

local eepyActs = {
    [ACT_SLEEPING] = true,
}

local camAngle = 0
local camScale = 3
local camPitch = 0
local camPan = 0
local squishyCamActive = true
local prevSquishyCamActive = false
local camTweenSpeed = 0.1
local camForwardDist = 10
local camPanSpeed = 25
local focusPos = {x = 0, y = 0, z = 0}
local camPos = {x = 0, y = 0, z = 0}
local camFov = 50

local doodellState = 0
local doodellTimer = 1
local doodellBlink = false
local eepyTimer = 0
local eepyStart = 390
local eepyCamOffset = 0
local prevPos = {x = 0, y = 0, z = 0}
local function camera_update()
    local m = gMarioStates[0]
    local l = gLakituState
    local squishyCamToggle = _G.charSelect.get_options_status(OPTION_SQUISHYCAM)
    local isSquishy = _G.charSelect.character_get_current_number() == CT_SQUISHY
    if squishyCamActive then
        doodellState = doodellBlink and 1 or 0
        camera_freeze()
        if not (is_game_paused() or eepyTimer > eepyStart) then
            local controller = m.controller
            local camSwitch = (controller.buttonDown & R_TRIG ~= 0)
            local analogToggle = camera_config_is_analog_cam_enabled()
            local invertXMultiply = camera_config_is_x_inverted() and -1 or 1
            local invertYMultiply = camera_config_is_y_inverted() and -1 or 1

            local camDigitalLeft  = analogToggle and L_JPAD or L_CBUTTONS
            local camDigitalRight = analogToggle and R_JPAD or R_CBUTTONS
            local camDigitalUp    = analogToggle and U_JPAD or U_CBUTTONS
            local camDigitalDown  = analogToggle and D_JPAD or D_CBUTTONS

            local camAnalogX = analogToggle and controller.extStickX or button_to_analog(m, L_JPAD, R_JPAD)
            local camAnalogY = analogToggle and controller.extStickY or button_to_analog(m, U_JPAD, D_JPAD)
            
            if not camSwitch then
                --[[
                if m.forwardVel > 0 then
                    camAngle = m.faceAngle.y+0x8000 - approach_s32(convert_s16(m.faceAngle.y+0x8000 - camAngle), 0, m.forwardVel*5, m.forwardVel*5)
                end
                ]]

                if math.abs(camAnalogX) > 10 then
                    camAngle = camAngle + camAnalogX*10*invertXMultiply
                end
                if math.abs(camAnalogY) > 10 then
                    camScale = clamp(camScale - camAnalogY*0.001*invertYMultiply, 1, 7)
                end

                if controller.buttonPressed & camDigitalLeft ~= 0 then
                    camAngle = camAngle - 0x2000*invertXMultiply
                end
                if controller.buttonPressed & camDigitalRight ~= 0 then
                    camAngle = camAngle + 0x2000*invertXMultiply
                end
                if controller.buttonPressed & camDigitalDown ~= 0 then
                    camScale = math.min(camScale + invertYMultiply, 7)
                end
                if controller.buttonPressed & camDigitalUp ~= 0 then
                    camScale = math.max(camScale - invertYMultiply, 1)
                end
                camPitch = 0
                camPan = 0
            else
                if controller.buttonDown & L_CBUTTONS ~= 0 then
                    camPan = camPan - camPanSpeed*camScale
                end
                if controller.buttonDown & R_CBUTTONS ~= 0 then
                    camPan = camPan + camPanSpeed*camScale
                end
                if controller.buttonDown & D_CBUTTONS ~= 0 then
                    camPitch = camPitch - camPanSpeed*camScale
                end
                if controller.buttonDown & U_CBUTTONS ~= 0 then
                    camPitch = camPitch + camPanSpeed*camScale
                end
            end
        end

        --l.mode = CAMERA_MODE_NONE

        local angle = camAngle
        local roll = ((sins(atan2s(m.vel.z, m.vel.x) - camAngle)*m.forwardVel/150)*0x800)
        if not camSwitch then
            if m.action & ACT_FLAG_SWIMMING_OR_FLYING ~= 0 and m.action ~= ACT_TWIRLING and m.action ~= ACT_TWIRL_LAND then
                angle = m.faceAngle.y - 0x8000
                if m.controller.buttonDown & L_CBUTTONS ~= 0 then
                    angle = angle - 0x2000
                end
                if m.controller.buttonDown & R_CBUTTONS ~= 0 then
                    angle = angle + 0x2000
                end
                camAngle = round(angle/0x2000)*0x2000

                if m.action & ACT_FLAG_FLYING ~= 0 then
                    roll = m.faceAngle.z*0.1
                end
            end
        end

        local posVel = {
            x = m.pos.x - prevPos.x,
            y = m.pos.y - prevPos.y,
            z = m.pos.z - prevPos.z,
        }

        local camPanX = sins(convert_s16(camAngle + 0x4000))*camPan
        local camPanZ = coss(convert_s16(camAngle + 0x4000))*camPan
        
        focusPos = {
            x = m.pos.x + (not nonMomentumActs[m.action] and posVel.x*camForwardDist or 0) + camPanX,
            y = m.pos.y + 150 + (not nonMomentumActs[m.action] and clamp(get_mario_y_vel_from_floor(m), -100, 100)*camForwardDist*0.8 or 0) - eepyCamOffset + camPitch,
            z = m.pos.z + (not nonMomentumActs[m.action] and posVel.z*camForwardDist or 0) + camPanZ,
        }
        camPos = {
            x = m.pos.x + (not nonMomentumActs[m.action] and posVel.x*7 or 0) + sins(angle) * 500 * camScale,
            y = m.pos.y - (not nonMomentumActs[m.action] and get_mario_y_vel_from_floor(m)*5 or 0) - 150 + 350 * camScale - eepyCamOffset,
            z = m.pos.z + (not nonMomentumActs[m.action] and posVel.z*7 or 0) + coss(angle) * 500 * camScale,
        }
        
        if camPitch >= 600*((camScale + 1)/3.5) and
            m.floor and m.floor.type == SURFACE_LOOK_UP_WARP and
            save_file_get_total_star_count(get_current_save_file_num() - 1, COURSE_MIN - 1, COURSE_MAX - 1) >= gLevelValues.wingCapLookUpReq and
            not is_game_paused() then

            level_trigger_warp(m, WARP_OP_LOOK_UP)
        end

        -- Doodell is eepy
        if eepyActs[m.action] then
            doodellState = 4
            eepyTimer = eepyTimer + 1
            local camFloor = collision_find_surface_on_ray(camPos.x, camPos.y + eepyCamOffset, camPos.z, 0, -10000, 0).hitPos.y
            if eepyTimer > eepyStart then
                doodellState = 5
                if camPos.y > (camFloor + 150) then
                    eepyCamOffset = eepyCamOffset + (math.sin(eepyTimer*0.1) + 1)*2
                end
            end
        else
            eepyCamOffset = eepyCamOffset * 0.9
            eepyTimer = 0
        end

        if math.abs(math.sqrt(camPos.x^2 + camPos.z^2) - math.sqrt(l.pos.x^2 + l.pos.z^2)) < 1500*((camScale+1)*0.5) then
            vec3f_copy(l.focus, approach_vec3f_asymptotic(l.focus, focusPos, camTweenSpeed, camTweenSpeed*0.5, camTweenSpeed))
            vec3f_copy(l.pos, approach_vec3f_asymptotic(l.pos, camPos, camTweenSpeed, camTweenSpeed*0.5, camTweenSpeed))
        else
            vec3f_copy(l.focus, focusPos)
            vec3f_copy(l.pos, camPos)
        end
        l.roll = lerp(l.roll, roll, 0.1)
        camFov = lerp(camFov, 50 + math.abs(m.forwardVel)*0.1, 0.1)
        set_override_fov(camFov)
        prevSquishyCamActive = squishyCamActive

        if l.roll < -1000 then
            doodellState = 2
        end
        if l.roll > 1000 then
            doodellState = 3
        end
        vec3f_copy(prevPos, m.pos)
    end
    
    if is_mario_in_cutscene(m) or nonCameraActs[m.action] or omm_camera_enabled(m) or camera_config_is_free_cam_enabled() then
        squishyCamActive = false
    else
        squishyCamActive = (squishyCamToggle == 2 or (squishyCamToggle == 1 and isSquishy))
    end
    
    if not squishyCamActive and prevSquishyCamActive ~= squishyCamActive then
        camera_unfreeze()
        vec3f_copy(l.focus, approach_vec3f_asymptotic(l.focus, focusPos, camTweenSpeed, camTweenSpeed*0.5, camTweenSpeed))
        vec3f_copy(l.pos, approach_vec3f_asymptotic(l.pos, camPos, camTweenSpeed, camTweenSpeed*0.5, camTweenSpeed))
        set_camera_mode(m.area.camera, CAMERA_MODE_NONE, 0)
        prevSquishyCamActive = squishyCamActive
    end
end

local TEX_DOODELL_CAM = get_texture_info("squishy-doodell-cam")
local MATH_DIVIDE_SHAKE = 1/1000

local doodellScale = 0
local function hud_render()
    local m = gMarioStates[0]
    local l = gLakituState
    if squishyCamActive then
        djui_hud_set_resolution(RESOLUTION_N64)
        local width = djui_hud_get_screen_width()
        local height = 240
        doodellTimer = (doodellTimer + 1)%20
        local animFrame = math.floor(doodellTimer*0.1)

        if doodellTimer == 0 then
            doodellBlink = math.random(1, 10) == 1
        end

        doodellScale = lerp(doodellScale, (math.abs(camScale-8)/8)*0.2 + 0.4, 0.1)
        local shakeX = math.random(-1, 1)*math.max(math.abs(l.roll)-1000, 0)*MATH_DIVIDE_SHAKE
        local shakeY = math.random(-1, 1)*math.max(math.abs(l.roll)-1000, 0)*MATH_DIVIDE_SHAKE

        djui_hud_set_color(255, 255, 255, 255)
        _G.charSelect.hud_hide_element(HUD_DISPLAY_FLAG_CAMERA)
        djui_hud_set_rotation(l.roll, 0.5, 0.8)
        djui_hud_render_texture_tile(TEX_DOODELL_CAM, width - 38 - 64*doodellScale + shakeX, height - 38 - 64*doodellScale + eepyCamOffset*0.1*doodellScale + shakeY, doodellScale, doodellScale, animFrame*128, doodellState*128, 128, 128)
        djui_hud_set_rotation(l.roll, 0, 0)
    else
        _G.charSelect.hud_show_element(HUD_DISPLAY_FLAG_CAMERA)
    end
end

---@param m MarioState
local function input_update(m)
    if m.playerIndex ~= 0 then return end
    if doodell_cam_active() and m.action & ACT_FLAG_SWIMMING_OR_FLYING == 0 and gLakituState.mode == CAMERA_MODE_NONE then
        local camAngle = camAngleRaw
        local analogToggle = camera_config_is_analog_cam_enabled()
        if not analogToggle then
            camAngle = (camAngle/0x1000)*0x1000
        end
        m.area.camera.yaw = camAngle
        m.intendedYaw = atan2s(-m.controller.stickY, m.controller.stickX) + camAngle
    end
end

local function on_level_init()
    camAngle = round(gMarioStates[0].faceAngle.y/0x2000)*0x2000 - 0x8000
end

hook_event(HOOK_ON_HUD_RENDER_BEHIND, hud_render)
hook_event(HOOK_BEFORE_MARIO_UPDATE, input_update)
hook_event(HOOK_UPDATE, camera_update)
hook_event(HOOK_ON_LEVEL_INIT, on_level_init)
