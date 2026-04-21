# Forgotten Catacombs

<p align="right">
<img src="docs/manual/images/playdate.png" width=200/>
</p>

A simple rogue-like targeted for desktop terminal and [playdate console](https://play.date/).

### 🛠️ Building from source

**📌 Requirements**

- Zig compiler: **version 0.16.0 or later**
- Playdate SDK (for Playdate build only)

**💻 Terminal build**

Build and run the game in terminal mode:
```sh
zig build run -Doptimize=ReleaseFast
```
Output binary will be located in: `zig-out/bin/`

**🎮 Playdate build**

Additional requirements:
 * Playdate SDK installed
 * `PLAYDATE_SDK` environment variable set

Set SDK path (example):
```sh
export PLAYDATE_SDK=~/PlaydateSDK
```
**Build and run in emulator:**
```sh
zig build emulate -Doptimize=ReleaseFast
```
This will:

 * build the Playdate version
 * launch it in the Playdate Simulator
 * generate a .pdx package

The resulting package will be located in:
```sh
zig-out/forgotten_catacombs.pdx
```

### 📖 Manual

🇷🇺 [Русская версия](docs/manual/manual.ru.pdf)


### 📬 Contacts & Contributions

This is a hobby project developed in free time.
Feedback, bug reports, and suggestions are very welcome — feel free to open an issue 
for bug reports and suggestions.

While contributions are appreciated, please note:

- Pull requests may not always be reviewed promptly
- Some pull requests may not be merged
- There is no guarantee that all suggestions will be implemented

This is not due to lack of interest, but simply limited available time.

### ⚖️ Licensing & Copyright

**💻 Source Code**

The source code is licensed under the MIT License.
You are free to use, modify, and distribute the code as long as the license is included.

**🎨 Game Content (Assets, Story, Design)**

All non-code content is proprietary and protected by copyright.
Game content is only permitted for use within this project.
