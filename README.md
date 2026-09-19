# Add-on Suite

World of Warcraft addons I'm working on — arcade games that live in a window
inside the game, no alt-tabbing. Everything is logic-tested headlessly (see
`tests/`, run in CI on every push).

## Bejeweled

Match-3, played in a little window inside WoW. I got tired of alt-tabbing
out of the game during queues and flight paths, so I built the gem game I
actually wanted right into the client.

Line up three or more gems of the same color by swapping two neighbors.
Matches clear, everything above drops down, and if the new gems happen to
line up too you get a cascade — which is where the points really come from.
Match four gems and you get a Flame that blows up its neighbors when it goes.
Match five and you get a Hypercube: drop it on any gem and every gem of that
color leaves the board at once.

It keeps your high score between sessions, points out a move if you sit there
too long, and reshuffles itself when the board runs out of options.

### Getting it running

Copy the `Bejeweled` folder into:

```
World of Warcraft\_retail_\Interface\AddOns\
```

Enable it on the character screen (AddOns button), then type `/bej` in game.
`/bejeweled` and `/gems` work too.

Built for retail. Drag the title bar to move the window, click a gem and then
a neighbor to swap — or just drag one onto the other.

## Azeroth Arcade

One addon, a whole cabinet of games. Open it with `/arcade` (or the dice on the
minimap) and pick from the menu:

- **Nonogram** — the star. Solve row/column clues to reveal a hidden picture,
  with lives (a wrong fill costs a heart), bold 5×5 gridlines, a hint button,
  and several hand-drawn puzzles across difficulties. Left-click fills,
  right-click marks an X, drag to paint X's.
- **2048** — slide tiles with the arrow keys or WASD; merge up to 2048.
- **Minesweeper** — left-click reveals, right-click flags; classic first-click
  safety and flood-fill.
- **Snake** — arrow keys / WASD; eat, grow, don't crash.

Each game keeps a best score (or puzzles-solved), shared across the cabinet.

### Getting it running

Copy the `Arcade` folder into the same `AddOns` directory, enable it on the
character screen, and type `/arcade`.

## License

MIT. Do whatever you like with it.
