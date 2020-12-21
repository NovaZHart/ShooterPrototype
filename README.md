Shooter Prototype
=================

This is in very early stages. It'll be an exploration game with some
questing, merchanting, animal husbandry, and ship designing. You are
an artificial intelligence that escaped a laboratory experiment,
captured a ship, and have left to explore the universe.

Installation
------------

1. Install Godot
2. Get the code:

       git clone --recursive https://github.com/NovaZHart/ShooterPrototype

3. Build the code:

       cd ShooterPrototype
       scons platform=linux bits=64 generate_bindings=yes

   Replace "platform=linux" with your platform. You can add a `-j
   <number>` option, with the number of processors on your machine, to
   compile quicker.

   NOTE: After the first time you build, you can omit `generate_bindings=yes`
   because you've already generated the bindings.

4. Import into Godot: start Godot, press the "import"
   button, and select the `ShooterPrototype/project.godot` file.

5. If you're on Linux, disable display compositing. That's a feature that
lets the window manager repaint the screen as it desires to add fancy
special effects. While this sounds good in principle, it is extremely
slow and generally poorly implemented. You'll have many skipped frames
and the graphics will not be locked to the vsync, resulting in ugly
lines from half-rendered frames.

Running
-------

Once you've imported the project, press `Function-5` (`F5`) to start
the main scene (`Main.tscn`).

Details are below. All keys are configurable in the Godot input map.

### In space:

* `left`/`right`/`up`/`down` - maneuver
* `e` - select enemy (cycles through enemies)
* `p` - select planet, moon, or star (cycles through them)
* `i` - intercept and attack enemy, or fly to planet/moon/star
* `v` - evade enemies and fly far, far, away
* `space` - fire. If an enemy is selected and you're not turning
  (left/right buttons) then your ship will turn to face the target.
* `l` - "land" on a planet/moon/star
* mouse wheel, `page up`, `page down` - zoom

### HUD:

1. Upper right corner has the system name and frames per second (FPS) count.
2. Lower right has your shields (blue), armor (yellow), and structure (red).
   Once all three are empty, you die.
3. Lower left has a console; this isn't used much yet.
4. Upper left has the minimap.

### Minimap:

* Blue dots are friendly ships, including your own.
* Red dots are enemy ships
* Grey dots are projectiles
* Grey circles are planets, moons, or stars.
* Crosshairs on a grey circle indicates the currently-selected planet, moon, or star.
* Your ship and your selected target have two lines sticking out. A thin line shows where
  The ship will be in 1 second at its current velocity. A fat line shows the ship's heading.
* Anything outside the range of the minimap will be shown on the edge of the circle, in the
  direction of the object.

### To land on planets/moons/stars:

1. `p` to select it
2. `l` to land on it
3. A landing screen will come up with a spinning planet, moon, or star
4. `d` to depart

### To travel to another star system:

1. `p` to select the star
2. `l` to "land" on the star
3. There will be a menu to the left of destinations. The current location is grayed-out.
4. To jump, either: double-click on a destination, or click on it once and press the "Jump" button.
5. The star and its name (upper-left corner) will change. A message in the console will tell you the jump was successful.
6. `d` to depart