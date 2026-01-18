local Roomshift = {}
Roomshift.__index = Roomshift

--- Creates a room table for use with the camera.
-- @param x number Left edge of the room in pixels
-- @param y number Top edge of the room in pixels
-- @param width number Width of the room in pixels
-- @param height number Height of the room in pixels
-- @return table Room with x, y, width, height properties
function Roomshift.newRoom(x, y, width, height)
    return {
        x = x,
        y = y,
        width = width,
        height = height
    }
end

--- Creates a new room-based camera.
-- @param viewportWidth number Width of the viewport in pixels (e.g., 400)
-- @param viewportHeight number Height of the viewport in pixels (e.g., 240)
-- @param panSpeed number Speed of camera panning during room transitions, in pixels per second (e.g., 80)
-- @param followAxes string Which axes the camera follows the target on: "horizontal", "vertical", or "both"
-- @return table Camera instance
function Roomshift.newCamera(viewportWidth, viewportHeight, panSpeed, followAxes)
    local self = setmetatable({}, Roomshift)
    self.x = 0
    self.y = 0
    self.panSpeed = panSpeed
    self.followAxes = followAxes

    self.viewportWidth = viewportWidth
    self.viewportHeight = viewportHeight

    -- Calculate zoom based on window size
    local windowWidth, windowHeight = love.graphics.getWidth(), love.graphics.getHeight()
    self.zoom = math.min(windowWidth / self.viewportWidth, windowHeight / self.viewportHeight)

    self.targetX = 0
    self.targetY = 0
    self.isPanning = false
    self.isTransitioning = false
    self.currentRoom = nil
    self.previousRoom = nil

    return self
end

--- Updates the camera position during room transitions.
-- @param dt number Delta time in seconds
function Roomshift:update(dt)
    if self.isPanning then
        local speed = self.panSpeed * dt

        -- Move horizontally at a constant speed
        if self.x < self.targetX then
            self.x = self.x + speed
            if self.x > self.targetX then self.x = self.targetX end
        elseif self.x > self.targetX then
            self.x = self.x - speed
            if self.x < self.targetX then self.x = self.targetX end
        end

        -- Move vertically at a constant speed
        if self.y < self.targetY then
            self.y = self.y + speed
            if self.y > self.targetY then self.y = self.targetY end
        elseif self.y > self.targetY then
            self.y = self.y - speed
            if self.y < self.targetY then self.y = self.targetY end
        end

        -- Stop panning when target is reached (use epsilon for floating point comparison)
        local epsilon = 0.1
        if math.abs(self.x - self.targetX) < epsilon and math.abs(self.y - self.targetY) < epsilon then
            -- Snap to exact target to prevent drift
            self.x = self.targetX
            self.y = self.targetY
            self.isPanning = false
            if self.isTransitioning then
                self.isTransitioning = false
                self.currentRoom = self.previousRoom
            end
        end
    end
end

--- Sets a target position for the camera to pan to.
-- @param x number Target x position in pixels
-- @param y number Target y position in pixels
function Roomshift:setTarget(x, y)
    self.targetX = x
    self.targetY = y
    self.isPanning = true
end

--- Applies the camera transformation. Call before drawing world objects.
function Roomshift:apply()
    love.graphics.push()
    love.graphics.scale(self.zoom, self.zoom)
    love.graphics.translate(-self.x, -self.y)
end

--- Resets the camera transformation. Call after drawing world objects.
function Roomshift:reset()
    love.graphics.pop()
end

--- Returns the current zoom level.
-- @return number
function Roomshift:getZoom()
    return self.zoom
end

--- Follows a target within a room, respecting room boundaries.
-- @param target table Target to follow with {x, y, width, height} properties
-- @param room table Room bounds with {x, y, width, height} properties (see Roomshift.newRoom)
-- @param dt number Delta time in seconds (unused, kept for API consistency)
function Roomshift:follow(target, room, dt)
    if not room then return end

    -- Check if we changed rooms
    if self.currentRoom ~= room then
        self:startRoomTransition(room)
    end

    -- If transitioning between rooms, don't follow target
    if self.isTransitioning then
        return
    end

    -- Calculate desired camera position based on followAxes setting
    local desiredX = self.x
    local desiredY = self.y

    if self.followAxes == "horizontal" or self.followAxes == "both" then
        desiredX = target.x + target.width / 2 - self.viewportWidth / 2
    end

    if self.followAxes == "vertical" or self.followAxes == "both" then
        desiredY = target.y + target.height / 2 - self.viewportHeight / 2
    end

    -- Clamp desired position to room boundaries
    desiredX, desiredY = self:getClampedPosition(desiredX, desiredY, room)

    -- Snap camera directly to position
    self.x = desiredX
    self.y = desiredY
end

--- Returns a position clamped to room boundaries.
-- If the room is smaller than the viewport, centers the camera on the room.
-- @param x number Desired x position
-- @param y number Desired y position
-- @param room table Room bounds with {x, y, width, height} properties (see Roomshift.newRoom)
-- @return number, number Clamped x and y positions
function Roomshift:getClampedPosition(x, y, room)
    if not room then return x, y end

    local clampedX = x
    local clampedY = y

    -- Clamp X
    if room.width <= self.viewportWidth then
        clampedX = room.x + (room.width - self.viewportWidth) / 2
    else
        if clampedX < room.x then
            clampedX = room.x
        elseif clampedX + self.viewportWidth > room.x + room.width then
            clampedX = room.x + room.width - self.viewportWidth
        end
    end

    -- Clamp Y
    if room.height <= self.viewportHeight then
        clampedY = room.y + (room.height - self.viewportHeight) / 2
    else
        if clampedY < room.y then
            clampedY = room.y
        elseif clampedY + self.viewportHeight > room.y + room.height then
            clampedY = room.y + room.height - self.viewportHeight
        end
    end

    return clampedX, clampedY
end

--- Clamps the camera position to the given room boundaries.
-- @param room table Room bounds with {x, y, width, height} properties (see Roomshift.newRoom)
function Roomshift:clampToRoom(room)
    if not room then return end

    self.x, self.y = self:getClampedPosition(self.x, self.y, room)
end

--- Starts a smooth transition to a new room.
-- @param newRoom table Room bounds with {x, y, width, height} properties (see Roomshift.newRoom)
function Roomshift:startRoomTransition(newRoom)
    self.previousRoom = newRoom
    self.isTransitioning = true

    -- Calculate the target camera position for the new room
    local targetX, targetY

    -- If room is smaller than viewport, center on room
    if newRoom.width <= self.viewportWidth then
        targetX = newRoom.x + (newRoom.width - self.viewportWidth) / 2
    else
        -- Position camera to show the edge of the new room closest to current position
        if self.x < newRoom.x then
            targetX = newRoom.x
        elseif self.x + self.viewportWidth > newRoom.x + newRoom.width then
            targetX = newRoom.x + newRoom.width - self.viewportWidth
        else
            targetX = self.x
        end
    end

    -- Position camera vertically based on room size
    if newRoom.height <= self.viewportHeight then
        targetY = newRoom.y + (newRoom.height - self.viewportHeight) / 2
    else
        targetY = newRoom.y
    end

    -- Start the smooth pan to the new room
    self:setTarget(targetX, targetY)
end

return Roomshift
