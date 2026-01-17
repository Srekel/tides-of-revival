# Get started

## 1. Get prerequisites
Tides of Revival development is currently limited to Windows. You need the following software. (or equivalent)

### Python 3.9 or thereabouts
- https://www.python.org/downloads/
- During installation, make sure to tick "Add to path" on the first screen.

### Git For Windows
- https://gitforwindows.org/

### TortoiseSVN
- https://tortoisesvn.net/downloads.html
- Needed for content.

### VS Code
- https://code.visualstudio.com/download
- After installation, and github cloning (see below), install all recommended workspace extensions.

### Visual Studio 2022 Community Edition
- https://visualstudio.microsoft.com/vs/community/
- Seems like it's needed for the C++ VS Code extension for debugging.

### Fork
- https://git-fork.com/

## 2. Get the repos

### Git 
- Clone `https://github.com/Srekel/tides-of-revival.git`

### SVN Content
- Clone `(ask Anders for details)`
- Put it inside the tides-of-revival repo, so that `content` is parallel to `README.md`.

### SVN Source
- Clone `(ask Anders for details)`
- Put it parallel to the the tides-of-revival repo.


## 3. Initialize

- Run `sync_external.py`
- This will first sync all of the project's repos and dependencies. 
- Start Code from the root folder. It should open a workspace.
- Build "build_simulator_release"
- Run "Simulator_Release"
- Maybe: After it starts, close it down, and then start it back up again.
- Wait, it will take a while. Like, half an hour or so depending on your computer.
- When it's done, go to the tools/binaries folder and start AssetCooker.
- Wait.
- Go back to Code. Run "Tides of Revival". 

## 4. Start the game!
- You should be able to debug it from within VS Code.
