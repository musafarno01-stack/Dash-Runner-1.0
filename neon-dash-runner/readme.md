# Neon Dash Runner

A small endless runner made with Godot 4. The graphics are drawn by the game;
no external assets are required.

## Run the game

1. Install Godot 4.
2. Open Godot and choose **Import**.
3. Select this folder's `project.godot`.
4. Press **F6** to run the main scene or **F5** to run the project.

## Controls

- Enter or Space: start/replay
- Space, Up, or W: jump
- Down, S, or Shift: slide
- P or Escape: pause/resume
- M: return to menu from pause or game over
- Touch: tap left to jump; tap right to slide

The best score is saved in Godot's `user://` data folder.

## Validate

Run this from the project folder with Godot 4 installed:

    godot --headless --editor --path . --quit

No export or device test is included in this source project.
