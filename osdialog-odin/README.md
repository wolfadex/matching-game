# osdialog-odin

[badge__build-status]: https://img.shields.io/github/actions/workflow/status/ttytm/osdialog-odin/ci.yml?branch=main&logo=github&logoColor=C0CAF5&labelColor=333
[badge__version-lib]: https://img.shields.io/github/v/tag/ttytm/osdialog-odin?logo=task&logoColor=C0CAF5&labelColor=333&color=

[![][badge__build-status]](https://github.com/ttytm/osdialog-odin/actions?query=branch%3Amain)
[![][badge__version-lib]](https://github.com/ttytm/osdialog-odin/releases/latest)

Cross-platform utility library for Odin to open native dialogs for the filesystem, message boxes, color-picking.

## Quickstart

- [Installation](#installation)
- [Usage](#usage)
  - [Example](#example)
- [Credits](#credits)

## Showcase

<table align="center">
  <tr>
    <th>Linux</th>
    <th>Windows</th>
    <th>macOS</th>
  </tr>
  <tr>
    <td width="400">
      <img alt="Linux File Dialog" src="https://github.com/ttytm/dialog/assets/34311583/6ba6e96b-3581-4382-8074-79918a99dcbd">
    </td>
    <td width="400">
      <img alt="Windows File Dialog" src="https://github.com/ttytm/dialog/assets/34311583/911e8c71-0cc1-4426-a62c-04714b6b071f">
    </td>
    <td width="400">
      <img alt="macOS File Dialog" src="https://github.com/ttytm/dialog/assets/34311583/f7c4375e-d2e4-4121-ad34-db0473d8fabe">
    </td>
  </tr>
</table>

<details>
<summary><b>More Examples</b> <sub><sup>Toggle visibility...</sup></sub></summary><br>

<table align="center">
  <tr>
    <th>Linux</th>
    <th>Windows</th>
    <th>macOS</th>
  </tr>
  <tr>
    <td width="400">
      <img alt="Linux Color Picker GTK3" src="https://github.com/ttytm/dialog/assets/34311583/8e587c8c-2f12-41ee-9a10-4c3f92e72885">
      <img alt="Linux Message" src="https://github.com/ttytm/dialog/assets/34311583/42e1081b-ee52-4286-abfd-ad9eda63d282">
      <img alt="Linux Message with Yes and No Buttons" src="https://github.com/ttytm/dialog/assets/34311583/07aa26bd-f887-417b-9c1a-56724ceb2589">
      <img alt="Linux Input Prompt" src="https://github.com/ttytm/dialog/assets/34311583/bc5e3ec1-88b5-4e1a-b46e-381b322b8a6c">
      <img alt="Linux Color Picker GTK2" src="https://github.com/ttytm/dialog/assets/34311583/37619ed0-8fe2-4e5c-af11-70d7f2304b2b">
    </td>
    <td width="400">
      <img alt="Windows Color Picker" src="https://github.com/ttytm/dialog/assets/34311583/966b1395-55ac-45b8-aa1b-516f673b64e8">
      <img alt="Windows Message" src="https://github.com/ttytm/dialog/assets/34311583/a73e0eaf-e56b-44e6-bcc5-31bb381c6e37">
      <img alt="Windows Message with Yes and No Buttons" src="https://github.com/ttytm/dialog/assets/34311583/16a1ad65-571e-4183-8c0b-119cbf126aec">
      <img alt="Windows Input Prompt" src="https://github.com/ttytm/dialog/assets/34311583/54e4a708-de38-44ea-ae61-be39c1bdbff9">
    </td>
    <td width="400">
      <img alt="macOS Color Picker" src="https://github.com/user-attachments/assets/551ac8d6-406d-4b01-9095-d0a357cc8250">
      <!-- <img alt="macOS Message" src="https://github.com/ttytm/dialog/assets/34311583/15920c46-e529-405f-9731-3ac57ce46449"> -->
      <img alt="macOS Message with Yes and No Buttons" src="https://github.com/ttytm/dialog/assets/34311583/11cba10b-3190-4114-b1ad-e49e56d4498c">
      <img alt="macOS Input Prompt" src="https://github.com/ttytm/dialog/assets/34311583/e6d496b4-3c20-4ece-8808-0eba99a59a45">
    </td>
  </tr>
</table>

</details>

## Installation

1. Add it as a submodule to your Odin Git project

   ```sh
   # <projects-path>/your-awesome-odin-project
   git submodule add https://github.com/ttytm/osdialog-odin.git osdialog
   ```

2. Prepare the C Binding

   _Unix-like_

   ```sh
   cd osdialog && make && cd -
   ```

   _Windows_

   ```sh
   cd osdialog
   nmake
   cd ..
   ```

## Usage

Ref.: [`osdialog-odin/osdialog.odin`](https://github.com/ttytm/osdialog-odin/blob/main/osdialog.odin)

```odin
// Opens a message box and returns `true` if "OK" or "Yes" was pressed.
message :: proc(message: string, level: MessageLevel = .Info, buttons: MessageButtons = .Ok) -> bool

// Opens an input prompt with an "OK" and "Cancel" button and returns the entered text and `true`,
// or `false` if the dialog was cancelled. `text` optionally sets the initial content of the input box.
prompt :: proc(message: string, text: string = "", level: MessageLevel = .Info) -> (string, bool) #optional_ok

// Opens a file dialog and returns the selected path and `true` or `false` if the selection was canceled.
path :: proc(action: PathAction, path: string = "", filename: string = "") -> (string, bool) #optional_ok

// Opens an RGBA color picker and returns the selected `Color` and `true`, or `false` if the selection was canceled.
// Optionally, it takes a `color` and `opacity` argument. `color` sets the dialogs initial color. `opacity` can be
// set to `false` to disable the opacity slider on unix-like systems. It has no effect on Windows.
color :: proc(color: Color = {255, 255, 255, 255}, opacity: bool = true) -> (Color, bool) #optional_ok
```

### Example

Ref.: [`osdialog-odin/examples/main.odin`](https://github.com/ttytm/osdialog-odin/blob/main/examples/main.odin)

```odin
package main

import osd "osdialog"
import "core:fmt"

main :: proc() {
	osd.message("Hello, World!")

	input := osd.prompt("Give me some input")
	fmt.println("Input:", input)

	if color, ok := osd.color(); ok {
		fmt.println("Selected color", color)
	}

	if path, ok := osd.path(.Open); ok {
		fmt.println("Selected file:", path)
	}

	if path, ok := osd.path(.Open_Dir); ok {
		fmt.println("Selected dir", path)
	}

	if path, ok := osd.path(.Save); ok {
		fmt.println("Selected save path", path)
	}
}
```

For a simple local run:

_Unix-like_

One-shot copy pasta to perform a lighter, filtered development clone and build the C binding target.

```sh
git clone --recursive --filter=blob:none --also-filter-submodules \
  https://github.com/ttytm/osdialog-odin \
  && cd osdialog-odin && make
```

_Windows_

```sh
git clone --recursive --filter=blob:none --also-filter-submodules https://github.com/ttytm/osdialog-odin
```

```sh
cd osdialog-odin
nmake
```

Run the example

```sh
odin run examples/main.odin -file
```

## Credits

- [AndrewBelt/osdialog](https://github.com/AndrewBelt/osdialog) - The C project this library is leveraging
