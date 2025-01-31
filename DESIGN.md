# Theme: You are the weapon

# Introduction

## Game idea / pitch

The game is a non standard pool game where player needs to destroy opponent balls by dealing damage
to them. Players can use alternative cues and apply upgrades to their cues and balls in order to 
enhance the gameplay.

# Inspiration

## Buckshot roulette

Buckshot roulette takes a well known game concept and adds an additional layer of game play on top.
This prompts the player to seek more advanced strategies to win the game.

## Player experience

The whole game happens at a pool table. There is only 1 game to play. Players take turns and can
hit any single ball assigned to them. Additionally players can buy cue/ball upgrades from the shop
in order to deal more damage to the opponent or heal their balls. Players need to apply strategy
and learn shop items effects in order to have more chances of winning. 

## Platform

The game is developed on Linux, but also capable of running in the Web.

# Development Software

- Game is build from scratch and uses software renderering.
- Aseprite for 2D textures
- Audacity for soundtrack conversions.

## Genre

Action, Casual, Simulation

# Concept

## Gameplay overview

There are 2 players in the game. Each one starts with 15 balls.
Players take turns and use cues to hit any of their balls. The goal of the game is to destroy all
opponents balls.

Each ball starts with 10 HP, 5 DAMAGE and 0 ARMOR. These values can by upgraded
during the game. Total player HP is a sum of HP of all player balls.
When total  player HP drops down to 0, player looses. 
  During the turn, special collision rules apply for friendly (turn owners) and opponents balls:

- If a friendly ball collides with another friendly ball: both heal 1 HP
- If a friendly ball collides  with an opponent's ball: friendly ball heals by its
DAMAGE value. Opponent's ball loses HP equal to the friendly ball DAMAGE.
- If opponent's ball hits opponent's ball: nothing happens

If player's ball looses all HP or is pocketed, it is permanently removed from the field.
If player's ball  HP was full when it was healed, the heal amount is converted into souls     .
Souls act as a currency in the game. Players can buy upgrades and other cue in the shop.
Each player starts with a default cue. There is one slot for an additional one. 
Additional cues can be used only once.

## Theme interpretation (You are the weapon)

The game is a game of life and death. Player's life is infused into balls and these balls
are used to kill the opponent by destroying all his balls.

## Primary mechanics

- Ball hit:
    Standard pool mechanic. Player hits the ball with a cue. This applies an instantaneous velocity
    change in the ball which propels it forward.
- Ball collision
    Standard pool mechanic. Balls collide with other balls, table borders or table pockets.
- Ball interactions
    Balls have special rules when it comes to the collision with other balls:
    - If 2 friendly balls collide they heal each other
    - If friendly and opponent's ball collide, friendly ball is healed and opponent's ball take 
    damage.
- Souls
    When friendly balls receive heal in any form, but their HP are already full, the heal value 
    is converted into souls. Souls act as a currency in the game to buy items.
- Ball upgrades
    Balls have characteristics such as HP, DAMAGE, ARMOR and effects like Bouncy etc. Balls can
    be upgrade with items bought from the shop.
- Cue upgrades
    Cues can be upgraded with items from the shop. The example is the scope upgrade that shows the
    hit ball trajectory.
- Alternative cues
    In addition to the default pool cue, player can buy alternative cues each with special effects.

# Art

2D pixel art leaning towards darker color scheme, but not too dark as the background of the
scene is already black.

# Audio

## Music

Background music is selected to be dramatic to enhance the life and death atmosphere.

## Sound effects

Basic sound effects for ball collisions, cue hit and upgrade application. The volume is tuned
down a bit to let the background music take precedence.

# Game experience

## UI

UI is minimal, but all text/buttons have proper size and are clearly visible due to good contrast
on the black background.

## Controls

Mouse and LMB arm only inputs the game needs to operate.

# Development timeline

01/17/2025
- Brain storm ideas for the jam
- Setup new repo for the project

01/18/2025
- Create a debug poll table and draw it
- Create debug circle texture and draw some balls
- Create basic physics
	- Ball <-> Rectangle collision
	- Ball <-> Ball collision
- Add rectangle colliders
- Add ball colliders
- Add multiple balls
- Hit balls with mouse drag

01/19/2025
- Add pocket colliders
- Make balls selectable with (use texture with white outline for selected one)
- Better table border colliders
- Linear collision resolution
- And more physics
- Button map
- State transition animations

01/20/2025
- Impulse based collision resolution
- Game states
- Input state
- Game state transitions
- Basic in game UI
- Basic game play loop (turns, score, restart)

01/21/2025
- More gameplay mechanics around HP
- Basic cue implementation
- Basic cue aim, shoot and go to storage animations
- Create debug cue texture and draw it
- Make cue hit the ball with constant force
- Make hit force adjustable
- Basic shop menu

01/22/2025
- Basic item usage
- Figure out inventory and item usage
- Make items be highlighted when hovered
- Only show ball info when selected
- Item/Cue highlight
- Window resolution change
- Basic shop item reroll and buy logic

01/23/2025
- Refactor game to use global context
- Use custom UiText instead of default Text
- opponent item and cue inventories
01/24/2025
- Create initial poll ball layout
- Opponent AI
- Ball can die, win/lost conditions

01/25/2025
- Fix physics
- Fix physics friction (at 60 FPS it is too high)
- Fix balls clipping through the borders
- Not allow player to use opponent's items

01/26/2025
- Fix ordering of drawable objects + add proper Z levels
- Maybe remove sorting of quads as they are quite big in size
- Add basic item description
- Add a new line handling to the text rendering

01/27/2025
- Add basic sprites for panels
- Select new font
- Animate the dash line
- Create panels for shop
- Cue controls update
- Ball selection input update

01/28/2025
- Better selected/upgradable cue visuals
- One time use cues
- Better visuals for turn owner
- Hover button texture
- Fix win/lose conditions
- Create panels for ball info
- Add bouncy,antigrav and runner ball upgrades
- Add ring of light and ghost ball upgrades/mods

01/29/2025
- Kar98k hit animation + damage effect
- Cross hit animation + damage effect
- Fix AI hitting in opposite direction
- All cue upgrades

01/30/2025
- Add proper item icons
- Add sounds + SFX
- Cue hitting adjustments
- Add screen with rules
- Proper item descriptions

01/31/2025
- Add remaining ball upgrade icons
- Finalize design doc

### Assets used:

- Ball sounds: https://pixabay.com/sound-effects/billiard-sound-05-288416/
- Gun fire: https://pixabay.com/sound-effects/cannon-fire-161072/
- Cross cue hit/spell: https://pixabay.com/sound-effects/magic-spell-6005/
- Background music: https://pixabay.com/music/classical-piano-moonlight-sonata-classical-piano-241539/
