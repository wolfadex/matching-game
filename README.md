# Yggdrasil

A GUI interface for managing your Minecraft servers

## Development Notes

The UI is rendered with [webview](https://github.com/webview/webview).
This is currently built separately by cloning that repo, building for the respective platform, and then the necessary libs copied into here.
This is mostly copied from [webview-odin](https://github.com/thechampagne/webview-odin) but with minor adjustments for supporting more systems.

The native dialogs use [osdialog-odin](https://github.com/ttytm/osdialog-odin).
It uses git submodules but I'm circumventing that with git subtrees instead because I like them more.
This should be improved.


Built with ❤️ with [Odin](https://odin-lang.org/)