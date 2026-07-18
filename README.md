# ghostty-agent-face

A living ASCII face on your [Ghostty](https://ghostty.org) terminal background that shows your AI agent's status at a glance — no tokens, no daemons, no polling.

| State | Trigger | Face |
|---|---|---|
| 😐 **Idle** | no signal | dim blue half-closed eyes, occasional blink, slow look-around |
| 🤔 **Thinking** | you submit a prompt | amber round eyes, scanning pupils, bobbing **?** |
| 😊 **Done** | agent finishes the turn | green happy arc-eyes `^ ^`, wide smile, drifting fireflies |
| 😮 **Needs you** | agent waits for approval | orange wide eyes, mouth **o**, pulsing **!** |

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
cp hooks/agent-face.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/agent-face.sh
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
    "Stop":             [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh done" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh attn" }] }],
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh reset" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/agent-face.sh reset" }] }]
  }
}
```

Any other agent works the same way — call `agent-face.sh run|done|attn|reset` on its lifecycle events.

4. Reload Ghostty config (`Cmd+Shift+,`). No restart needed — `custom-shader` applies at runtime to all open terminals.

## Try it without an agent

```sh
printf '\033]11;#332308\033\\'   # thinking (amber, "?")
printf '\033]11;#0A331A\033\\'   # done (green, smile)
printf '\033]11;#33110A\033\\'   # needs you (orange, "!")
printf '\033]111\033\\'          # reset -> idle
```

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
- If your theme background differs from `#282c34`, update `BASE_BG` or the repaint will be visible.
- On terminals other than Ghostty the shader layer does nothing, but OSC 11 signals still work as flat status tints (kill switch: `touch ~/.claude/hooks/agent-face.disabled`).

## Credits

Mechanism (OSC 11 as a hook→shader IPC channel) popularized by [astra-glow](https://github.com/Astralune-ai/astra-glow); this project is an independent implementation with its own renderer.

MIT license.
