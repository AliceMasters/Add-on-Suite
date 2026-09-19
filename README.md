# Add-on Suite

World of Warcraft addons I'm working on. One so far, more to come.

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

## License

MIT. Do whatever you like with it.
