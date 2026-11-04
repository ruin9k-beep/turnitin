# Turn It In

A quality-of-life addon for **Turtle WoW** (1.12 client, Lua 5.0 API) that takes the tedium out of repeatable turn-in quests: battleground mark quests, Zul'Gurub coins, and similar.

## What it does

- **Records repeatable quests** from any NPC. No hardcoded quest or NPC lists.
- **Shows the quest straight away** when you open it: name, items to hand in (with your bag counts), and the rewards.
- **Projects the rewards** for as many turn-ins as your bags allow: gold, items, honor, reputation and experience.
- **Reward picker** for quests that offer a choice. Your pick is remembered and used by auto turn-in.
- **Auto turn-in** for the selected quest, with an on/off button in the window.
- **Minimap button** (gold coin) that opens a list of every known quest, viewable **by quest** or **by turn-in location**.
- Shows itself in zones where you have a tracked quest, and stays hidden in raids.

## Install

1. Download this repository (green **Code** button, **Download ZIP**), or clone it straight into your AddOns folder with a Git-based addon manager.
2. The addon files sit at the root of the repository, so the folder must be named `turnitin`. Unzip or clone it to `World of Warcraft/Interface/AddOns/turnitin`, so that `turnitin.toc` sits directly inside that folder. A downloaded ZIP unpacks to `turnitin-main`, so rename it to `turnitin`. If you have an older `TurnItIn` folder, remove it; your recorded quests are kept.
3. Restart the game client. A brand-new addon is not picked up by `/console reloadui`.

## Use

1. Turn in a repeatable quest once. The addon records what it needs, and learns honor, reputation and XP from the messages in your chat.
2. When the NPC offers the quest again, it is marked as repeatable automatically. You can also press **Track quest** in the window while the quest is open.
3. Pick the quest in the dropdown, press **Auto: OFF** to switch it on, and right-click the NPC.

### Commands

| Command | Action |
| --- | --- |
| `/tii` | Show or hide the tracker window |
| `/tii list` | Open or close the known-quests list |
| `/tii auto` | Switch auto turn-in on or off |
| `/tii track` | Track the quest in the open dialog |
| `/tii forget` | Remove the selected quest |
| `/tii forget all` | Remove every recorded quest |
| `/tii minimap` | Show or hide the minimap button |
| `/tii debug` | Print what NPCs offer, to diagnose detection problems |
| `/tii ids` | Print the quest ID and flags the client reports for the open quest dialog (needs nampower/ClassicAPI/SuperWoW) |
| `/tii ids log` | The same for every quest in your quest log |

Left-click the minimap coin for the quest list, right-click it for the tracker window, and drag it to move it.

In the quest list, click the red **x** at the end of a row to remove that quest, or **Remove all quests** at the bottom (it asks first).

## Notes and limitations

- The 1.12 client does not flag repeatable quests. With a client mod that exposes quest IDs (such as nampower), a quest counts as repeatable once an ID you have completed is offered again, which also keeps quest chains that reuse a title from being mistaken for repeats. Without one, the addon falls back to comparing quest text.
- Without quest IDs, the rule is: A quest counts as repeatable once an NPC offers it again with the same quest text after you turned it in (quest chains that reuse a title are not mistaken for repeats), or when you track it by hand.
- Honor, reputation and XP are read from English chat messages after a turn-in.
- Quest windows may close after each turn-in, so auto turn-in can need one right-click per cycle.
- Written for the 1.12 client (Lua 5.0). Tested against a mock of the WoW API rather than the live client, so please report anything that behaves differently in the real client.

## License

MIT. See [LICENSE](LICENSE).
