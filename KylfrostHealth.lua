-- ============================================================================
-- KylfrostHealth - A simple addon to display health text above unit frames
-- ============================================================================
-- This addon creates text displays above the Player and Target unit frames
-- showing: current health / max health (health%)
-- Example: 52.8K/52.8K (100.0%)
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
-- Change these values to customize the look and position of the health text.
-- We will migrate these to a settings screen later.
-- ============================================================================

local CONFIG = {
    -- Font settings
    fontFace = "Fonts\\FRIZQT__.TTF",  -- Default WoW font
    fontSize = 16,                      -- Size of the text in points
    fontOutline = "OUTLINE",            -- "OUTLINE", "THICKOUTLINE", or "" for none

    -- Text color (Red, Green, Blue, Alpha) — values from 0 to 1
    -- Default is gold/yellow to match the WoW aesthetic
    fontColorR = 1.0,   -- Red
    fontColorG = 0.82,  -- Green
    fontColorB = 0.0,   -- Blue
    fontColorA = 1.0,   -- Alpha (transparency: 1 = fully visible, 0 = invisible)

    -- Position offset relative to the anchor frame
    -- Positive Y moves the text UP, negative moves it DOWN
    -- Positive X moves RIGHT, negative moves LEFT
    playerOffsetX = 25,   -- Horizontal offset for player health text
    playerOffsetY = 3,    -- Vertical offset for player health text
    targetOffsetX = -25,  -- Horizontal offset for target health text
    targetOffsetY = 3,    -- Vertical offset for target health text
}

-- ============================================================================
-- IMPORTANT NOTE ON "SECRET NUMBERS"
-- ============================================================================
-- In modern WoW (patch 12+), health values returned by UnitHealth() and
-- UnitHealthMax() are "secret numbers." This is a Blizzard security measure
-- to prevent addons from automating gameplay based on exact health values.
--
-- Secret numbers CANNOT be used in normal math (addition, division, etc.).
-- However, they CAN be passed to specific Blizzard functions that are
-- designed to handle them:
--   - AbbreviateLargeNumbers() converts a secret number into a secret string
--     like "52.8K" that can be displayed.
--   - UnitHealthPercent() returns the health percentage directly as a secret
--     number, so we don't need to calculate it ourselves.
--   - Secret strings can be concatenated with ".." and passed to SetText().
-- ============================================================================

-- ============================================================================
-- HELPER FUNCTION: Build the health display string
-- ============================================================================
-- Takes a unit ID (like "player" or "target") and returns a displayable
-- string using only secret-number-safe Blizzard API functions.
-- Example output: "52.8K/52.8K (100%)"
-- Returns nil if the unit doesn't exist (e.g., no target selected).
-- ============================================================================

local function GetHealthText(unitId)
    -- Check if the unit exists before trying to get health info
    if not UnitExists(unitId) then
        return nil
    end

    -- Use Blizzard's AbbreviateLargeNumbers() to safely convert secret
    -- health numbers into readable strings like "52.8K"
    local healthStr = AbbreviateLargeNumbers(UnitHealth(unitId))
    local maxHealthStr = AbbreviateLargeNumbers(UnitHealthMax(unitId))

    -- Use UnitHealthPercent() to get the percentage directly from the API.
    -- This avoids doing arithmetic on secret numbers (which would cause errors).
    -- UnitHealthPercent() is a patch 12+ API that returns a secret number.
    -- We pass it through AbbreviateLargeNumbers() to get a displayable string.
    if UnitHealthPercent then
        local percentStr = AbbreviateLargeNumbers(UnitHealthPercent(unitId))
        -- Build the final string using concatenation (safe with secret strings)
        return healthStr .. "/" .. maxHealthStr .. " (" .. percentStr .. "%)"
    end

    -- Fallback if UnitHealthPercent is not available: show without percentage
    return healthStr .. "/" .. maxHealthStr
end

-- ============================================================================
-- CREATE THE HEALTH TEXT DISPLAY FOR A UNIT FRAME
-- ============================================================================
-- This function creates a FontString (text element) and anchors it above
-- the specified unit frame. It returns an update function so we can refresh
-- the text whenever health changes.
-- ============================================================================

local function CreateHealthText(parentFrame, unitId, offsetX, offsetY)
    -- Create a new frame to hold our text
    -- We parent it to the unit frame so it moves/hides with the frame
    local frame = CreateFrame("Frame", nil, parentFrame)

    -- Create a FontString — this is how WoW displays text on screen
    local text = frame:CreateFontString(nil, "OVERLAY")

    -- Set the font, size, and outline from our configuration
    text:SetFont(CONFIG.fontFace, CONFIG.fontSize, CONFIG.fontOutline)

    -- Set the text color from our configuration
    text:SetTextColor(CONFIG.fontColorR, CONFIG.fontColorG, CONFIG.fontColorB, CONFIG.fontColorA)

    -- Position the text above the parent frame
    -- "BOTTOM" of our text is anchored to the "TOP" of the parent frame
    -- This places our text directly above the unit frame
    text:SetPoint("BOTTOM", parentFrame, "TOP", offsetX, offsetY)

    -- Define a function to update the displayed health text
    local function UpdateText()
        local healthString = GetHealthText(unitId)
        if healthString then
            text:SetText(healthString)
            text:Show()
        else
            -- If the unit doesn't exist (e.g., no target), hide the text
            text:Hide()
        end
    end

    -- Do an initial update so the text shows right away
    UpdateText()

    -- Return the update function so we can call it when health changes
    return UpdateText
end

-- ============================================================================
-- MAIN ADDON LOGIC
-- ============================================================================
-- Here we create the health text displays and register for the events
-- that tell us when health values change.
-- ============================================================================

-- Create the main event frame — this invisible frame listens for game events
local eventFrame = CreateFrame("Frame")

-- We need to wait until the player's unit frames are available.
-- The "PLAYER_ENTERING_WORLD" event tells us the UI is ready.
-- We also listen for "PLAYER_TARGET_CHANGED" and "UNIT_HEALTH" events.
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

-- These will hold our update functions once the text displays are created
local UpdatePlayerHealth = nil
local UpdateTargetHealth = nil

-- This function runs every time one of our registered events fires
eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- When the player first enters the world, create the health text displays
    if event == "PLAYER_ENTERING_WORLD" then
        -- Only create the text displays once
        if not UpdatePlayerHealth then
            -- Create health text above the Player unit frame
            -- "PlayerFrame" is the name of WoW's built-in player unit frame
            UpdatePlayerHealth = CreateHealthText(
                PlayerFrame,
                "player",
                CONFIG.playerOffsetX,
                CONFIG.playerOffsetY
            )
        end

        if not UpdateTargetHealth then
            -- Create health text above the Target unit frame
            -- "TargetFrame" is the name of WoW's built-in target unit frame
            UpdateTargetHealth = CreateHealthText(
                TargetFrame,
                "target",
                CONFIG.targetOffsetX,
                CONFIG.targetOffsetY
            )
        end

        -- Update both displays immediately
        UpdatePlayerHealth()
        if UpdateTargetHealth then
            UpdateTargetHealth()
        end

    -- When any unit's health changes, update the relevant display
    elseif event == "UNIT_HEALTH" then
        -- The first argument (...) tells us WHICH unit's health changed
        local unitId = ...

        -- Update player health text if the player's health changed
        if unitId == "player" and UpdatePlayerHealth then
            UpdatePlayerHealth()
        end

        -- Update target health text if the target's health changed
        if unitId == "target" and UpdateTargetHealth then
            UpdateTargetHealth()
        end

    -- When the player selects a new target (or clears their target)
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update the target health display to show the new target's health
        -- (or hide it if there's no target)
        if UpdateTargetHealth then
            UpdateTargetHealth()
        end
    end
end)

-- ============================================================================
-- Print a message to chat so we know the addon loaded successfully
-- ============================================================================
print("|cFFFFD100Kylfrost Health|r loaded successfully!")
