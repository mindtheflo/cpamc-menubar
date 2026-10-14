# Install Juice Bar

You are a coding agent installing **Juice Bar** on this Mac: a menu-bar app that shows the Claude and Codex subscription quotas of the user's local CPAMC/CLIProxyAPI instance. Follow these steps in order and run the commands yourself. Juice Bar then updates itself; running these steps again reinstalls the latest release.

## Rules

- Never read, print, copy or upload the CPAMC management key, API keys or provider credential files. Only check that the key file exists.
- Do not use `sudo`, change Gatekeeper or other security settings, or edit CLIProxyAPI, CPAMC or other launch agents.
- If a step fails, stop, show the error and ask the user how to continue.

## 1. Check the Mac

```sh
sw_vers -productVersion
xcode-select -p && swift --version
```

Juice Bar needs macOS 13 or later and Swift 6 or later. If `xcode-select -p` fails or `swift` is older, ask the user to run `xcode-select --install` (or update Xcode), and wait until they confirm it finished.

## 2. Get the source

Clone the release branch, `stable`, into the folder Juice Bar updates itself from, so its updates reuse this copy and its build cache. Don't change the files: a build with local changes is never updated automatically.

```sh
src="$HOME/Library/Application Support/Juice Bar/Source"
if [ -d "$src/.git" ]; then
  git -C "$src" fetch --quiet origin stable
  git -C "$src" checkout --quiet --force -B stable FETCH_HEAD
  git -C "$src" clean -ffdq
else
  mkdir -p "$(dirname "$src")"
  git clone --quiet --branch stable --single-branch https://github.com/mindtheflo/juice-bar.git "$src"
fi
```

## 3. Build and install

```sh
cd "$HOME/Library/Application Support/Juice Bar/Source"
bash scripts/install.sh --login
```

The installer builds the app from source, replaces any earlier Juice Bar in `~/Applications`, keeps its settings, opens it and starts it at login. Leave out `--login` only if the user doesn't want Juice Bar to start at login.

## 4. Check the connection

Juice Bar reads CPAMC at `http://127.0.0.1:8317`, with the management key in `~/Library/Application Support/CLIProxyAPI/management-key`.

```sh
nc -z 127.0.0.1 8317 && echo "Proxy: reachable"
test -s ~/Library/Application\ Support/CLIProxyAPI/management-key && echo "Key file: present"
~/Applications/Juice\ Bar.app/Contents/MacOS/cpamc-quota-check > /dev/null; echo "Quota check: exit $?"
```

- Exit 0: Juice Bar reads the quotas.
- Exit 2: connected, but at least one enabled account could not be read right now.
- Exit 1: no connection. If the proxy is reachable but runs elsewhere, or the key is in another file, ask the user to open Juice Bar › **Settings** › **Connection** and set the URL or choose the key file there.

Never add `--show-names` to the quota check.

## 5. Report

Tell the user:

- the installed version (`/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ~/Applications/Juice\ Bar.app/Contents/Info.plist`) and the connection result;
- the two bars are now in the menu bar; a menu-bar manager such as Bartender or Ice may keep the icon hidden until they place it;
- Juice Bar checks the `stable` branch once a day and installs new versions itself, without prompts; in Juice Bar › **Settings** › **Updates** they can turn this off, or choose **Nightly** to get every change as soon as it is merged;
- to remove Juice Bar, run `bash ~/Library/Application\ Support/Juice\ Bar/Source/scripts/uninstall.sh`.
