# ghostty-agent-face

A living ASCII face on your [Ghostty](https://ghostty.org) terminal background that shows your AI agent's status at a glance — no tokens, no daemons, no polling.

| State | Trigger | Face |
|---|---|---|
| 😐 **Idle** | no signal | dim blue half-closed eyes, occasional blink — plus an **aquarium**: 4 ASCII fish wander the background |
| 🤔 **Thinking** | you submit a prompt | amber round eyes, pupils on the move, bobbing **?** |
| ⚙️ **Working** | agent runs a tool | gold narrowed eyes looking down at the "keyboard", typing jitter, running **…** |
| 🐣 **Helpers** | agent spawns subagents | working face plus two pairs of small satellite eyes swaying in antiphase |
| 😊 **Done** | agent finishes the turn | green happy arc-eyes `^ ^`, wide smile, drifting fireflies |
| 😮 **Needs you** | agent waits for approval | orange wide eyes, mouth **o**, pulsing **!** |
| 😵 **Dizzy** | context compaction | purple spinner eyes `@ @` (counter-rotating), wavy mouth |
| 😴 **Sleep** | 30 min of unread "done" | closed dash-eyes, slow breathing, three **Z** drifting away, fish keep it company |

And it is genuinely alive:

- **pupils follow your terminal cursor** (Ghostty cursor uniforms) — the face watches you type;
- the **fish** swim on stateless Lissajous paths, turn with their motion, wag their tails and lazily avoid your cursor; bubbles rise behind them;
- a **watchdog** (one sleeping process, no daemon) auto-resets the face if the agent dies, catches "you came back and pressed a key" to dismiss the green smile, and escalates a long-unread "done" into Sleep;
- after **23:00 local** everything politely dims.

The face is drawn as an ASCII-style cell grid (mini-glyphs `0` / block / dot), gently breathes and floats, and **never gets in the way of your text**: any cell that contains terminal glyphs automatically goes dark.

## How it works

Two decoupled layers; the terminal background color itself is the IPC channel:

1. **Signal layer** — agent lifecycle hooks call `hooks/agent-face.sh`, which writes an OSC 11 "signal color" to the session's tty (found by walking the hook process's parent chain — hook processes have no controlling tty). Pure shell.
2. **Render layer** — `shaders/agent-face.glsl`, a Ghostty custom shader, samples the background from the window corners, classifies the signal by **channel ratios** (robust to brightness changes), repaints background pixels back to your normal theme color, and draws the matching face on top.

So the visible background never changes — the signal color is an invisible carrier. Without the shader you'd just get a slightly tinted background; without the hooks the face sits calmly in idle.

## Install

Requirements: Ghostty ≥ 1.2 (macOS), an agent with lifecycle hooks (Claude Code shown below), `lsof` (preinstalled on macOS).

1. Copy the shader and hook script:

```sh
mkdir -p ~/.config/ghostty/shaders ~/.claude/hooks
cp shaders/agent-face.glsl ~/.config/ghostty/shaders/
cp hooks/agent-face.sh hooks/agent-face-watch.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/agent-face.sh ~/.claude/hooks/agent-face-watch.sh
```

2. Add to your Ghostty config (`~/Library/Application Support/com.mitchellh.ghostty/config` or `~/.config/ghostty/config`):

```ini
custom-shader = ~/.config/ghostty/shaders/agent-face.glsl
# animate in unfocused windows too — status is for the windows you are NOT looking at
custom-shader-animation = always
```

3. Wire the hooks — for Claude Code, merge into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh run" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh pre" }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh run" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh done" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh attn" }] }],
    "PreCompact":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh dizzy" }] }],
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh reset" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh reset" }] }]
  }
}
```

Any other agent works the same way — call `agent-face.sh run|done|attn|work|helpers|dizzy|sleep|reset` on its lifecycle events. The `pre` state reads the hook's stdin JSON and picks `helpers` for subagent tools (`Agent`/`Task`/`Workflow`), `work` otherwise.

4. Reload Ghostty config (`Cmd+Shift+,`). No restart needed — `custom-shader` applies at runtime to all open terminals.

## Try it without an agent

```sh
printf '\033]11;#2D2C34\033\\'   # thinking (amber, "?")
printf '\033]11;#283134\033\\'   # working (gold, "...")
printf '\033]11;#2D3139\033\\'   # helpers (satellite eyes)
printf '\033]11;#282C39\033\\'   # done (green, smile)
printf '\033]11;#2D3134\033\\'   # needs you (orange, "!")
printf '\033]11;#2D2C39\033\\'   # dizzy (purple spinners)
printf '\033]11;#283139\033\\'   # sleep (z z z + fish)
printf '\033]111\033\\'          # reset -> idle (aquarium)
```

The signal colors are deliberately near-identical to the theme background (`+5/255` on one or two channels): the background **never visibly changes**, with or without the shader — the signal is a color delta the eye cannot see.

## Tuning

Everything is a constant in `agent-face.glsl`:

| What | Where |
|---|---|
| Your theme background (**must match**, default `#282c34`) | `BASE_BG` |
| Face position / size | `anchor` (screen fraction), `faceScale` |
| Overall brightness | `bright` |
| ASCII grid density | `R.y / 72.0` divisor |
| Text-protection strength | `smoothstep(0.05, 0.16, bgd)` and the `textIn` dimmer |

Signal colors live at the top of `agent-face.sh` and in the classifier thresholds of the shader — change both together.

## Notes & gotchas

- Ghostty's GLSL→Metal chain **silently drops** shaders that fail to compile. If you edit the shader and the face disappears, simplify your change — there is no error message.
- If your theme background differs from `#282c34`: update `BASE_BG` in the shader **and** recompute the hook colors as `background + 5` on the corresponding channels (R=thinking, G=working, B=done, RG=needs-you, RB=dizzy).
- On terminals other than Ghostty the shader does nothing and the signals are invisible by design — nothing to clean up. Kill switch: `touch ~/.claude/hooks/agent-face.disabled`.

## Credits

Mechanism (OSC 11 as a hook→shader IPC channel) popularized by [astra-glow](https://github.com/Astralune-ai/astra-glow); this project is an independent implementation with its own renderer.

MIT license.
