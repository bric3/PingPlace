# PingPlace

Control notification position on macOS.

**Note: macOS 26 users can use [@sk0gen](https://github.com/sk0gen)'s build for the time being, [download here](https://github.com/sk0gen/PingPlace/releases/download/v1.3.2/PingPlace.app.tar.gz)!**

![image](https://github.com/user-attachments/assets/469b318f-eba5-464f-87be-74d3decaa8a2)

As seen in [Lifehacker](https://lifehacker.com/tech/change-where-macos-notifications-show-up)

## Installation

```bash
brew tap notwadegrimridge/brew
brew install pingplace --no-quarantine
```

## Usage

The app needs accessibility permissions to work. It lives in the top bar. You can set notifications to appear in eight positions:

- Top Left
- Top Middle (default)
- Top Right (macOS default)
- Middle Left
- Middle Right
- Bottom Left
- Bottom Middle
- Bottom Right

### Debug build and logs

To diagnose notification placement resets (especially after screen topology changes), build a debug binary:

```bash
make debug-build
open PingPlace.app
```

This build enables debug tracing by default and writes to:

```bash
~/Library/Logs/PingPlace/debug.log
```

You can override runtime debug mode with:

```bash
defaults write com.grimridge.PingPlace debugMode -bool true   # force on
defaults write com.grimridge.PingPlace debugMode -bool false  # force off
```

## Requirements

- macOS 14 or later
- Accessibility permissions

## Support

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/wadegrimridge)
<a href="https://www.buymeacoffee.com/wadegrimridge" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;"></a>

Follow [@WadeGrimridge](https://x.com/WadeGrimridge) on X

## License

© 2025 All rights reserved.
