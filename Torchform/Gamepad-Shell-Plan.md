# Gamepad Shell — System Design Specification and Implementation Prompt

**Document ID:** GPSH-SDS-001
**Revision:** A
**Status:** Draft for review
**Language standard:** ASD-STE100 Simple Technical English (STE)

---

## 0. About This Document

### 0.1 Purpose

This document specifies a Unix application that lets an operator use a POSIX shell with a gamepad. The document gives the problem statement, the requirements, a trade study of solutions, a recommended language, and a program structure.

### 0.2 Audience

The audience is a principal engineer or an equivalent implementer. The document is also a complete prompt. You can give Section 21 to an AI agent or to a new team member.

### 0.3 Language Rules

The prose obeys ASD-STE100. Sentences are short. The voice is active. The tense is simple present. Each term has one meaning only. See the glossary in Section 4.

Three parts of this document do not obey STE, because the standard does not apply to them:

- Source code blocks and type sketches.
- Tables of identifiers, file names, and key bindings.
- Quoted names of libraries and commands.

---

## 1. Problem Statement

### 1.1 The Situation

The operator uses a handheld computer. The computer has a gamepad. The computer has a second screen with an on-screen keyboard (OSK). The computer runs Linux and a standard shell.

### 1.2 The Problem

A standard shell needs much text entry. The OSK gives approximately 1 character per 1.5 seconds. A typical command has 20 to 60 characters. Therefore each command needs 30 to 90 seconds of text entry. This rate makes the shell unusable in practice.

The problem is not the shell. The problem is the input method. A gamepad has approximately 16 discrete controls. A keyboard has approximately 100. A gamepad is good for selection. A gamepad is bad for spelling.

### 1.3 The Design Insight

Almost all shell text is not new text. Almost all shell text is a selection from a known set:

| Part of a command | Set that it comes from | Set size (typical) |
|---|---|---|
| Program name | Executable files on `PATH` | 1000 to 5000 |
| Option flag | Options of that program | 5 to 60 |
| Path argument | Files in the file system | Known at run time |
| Redirection operator | `\|`, `>`, `>>`, `<`, `2>`, `&&` | 6 to 10 |
| Variable name | Environment of the session | 30 to 80 |

Only free text (a search string, a literal value, a new file name) is new. Free text is a small part of the total. Thus the application must replace spelling with selection, and must keep the OSK for free text only.

### 1.4 Reference Designs

Two designs show that this approach operates:

- The **DSi and DS "basic computer" applications.** These applications supply a menu of commands. The operator selects. The operator does not spell.
- The **TI graphing calculators.** TI-BASIC has no full keyboard for keywords. Each keyword comes from a category menu. The result is a usable scripting system with 40 keys.

---

## 2. Goals and Non-Goals

### 2.1 Goals

| ID | Goal |
|---|---|
| G1 | The operator starts any program on `PATH` with the gamepad only. |
| G2 | The operator builds pipelines and redirections with the gamepad only. |
| G3 | The operator selects file and directory paths with the gamepad only. |
| G4 | The operator reads, sets, and deletes environment variables. |
| G5 | The operator reads output and scrolls the scrollback. |
| G6 | The operator uses the OSK for free text only. |
| G7 | The operator saves a command as a named script, and starts that script again later. |
| G8 | The application keeps the semantics of the host shell (bash or zsh). |

### 2.2 Non-Goals

| ID | Non-goal |
|---|---|
| N1 | The application is not a new shell language. |
| N2 | The application does not replace a text editor. |
| N3 | The application does not need a mouse. |
| N4 | The application does not need a network connection. |
| N5 | The application is not a desktop environment. |

### 2.3 Success Criterion

An operator who knows the shell must build and run `ls -la /var/log \| grep err > out.txt` in less than 20 seconds. The operator must not use the OSK for this task.

---

## 3. Constraints and Assumptions

| ID | Constraint |
|---|---|
| C1 | The operating system is Linux with `evdev` input devices. |
| C2 | The hardware is handheld class. Assume 4 cores at low frequency, and 1 GB to 4 GB of RAM. |
| C3 | The display is small. Assume 640 x 480 pixels as the minimum. |
| C4 | The computer runs on a battery. The application must stay idle when no event occurs. |
| C5 | The gamepad is the primary input device. The keyboard is optional. |
| C6 | One operator uses the application at a time. |
| C7 | The host shell is bash or zsh. The operator selects the host shell. |

---

## 4. Glossary

Use these terms only. Do not use a different word for the same thing.

| Term | Definition |
|---|---|
| **Operator** | The person who uses the application. |
| **Gamepad** | The physical control device. It has a D-pad, two sticks, four face buttons, and four shoulder controls. |
| **OSK** | On-screen keyboard. A software keyboard that the operator uses for free text. |
| **Host shell** | The bash or zsh process that runs below the application. |
| **PTY** | Pseudo-terminal. The device pair that connects the application to the host shell. |
| **Catalog** | The index of the executable files that the operator can start. |
| **Token** | One element of a command. A token is a program name, a flag, an argument, or an operator. |
| **Draft** | The command that the operator builds, but does not start. |
| **Node** | One command in a pipeline, with its tokens and its redirections. |
| **Action** | A logical input event, such as `MoveUp` or `Confirm`. An Action is not a button. |
| **Mode** | The state that decides how the application translates a button into an Action. |
| **Pane** | One rectangular part of the screen with one function. |
| **Effect** | An instruction from the core to the runtime, such as "write these bytes to the PTY". |

---

## 5. Requirements

### 5.1 Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| FR-01 | The application must show a menu of executable files. The operator opens the menu with one control or one chord. | Must |
| FR-02 | The menu must group the executable files by source directory. Examples are `/usr/bin`, `/usr/local/bin`, `~/.local/bin`, and the current directory. | Must |
| FR-03 | The operator must move between the groups with the shoulder controls. | Must |
| FR-04 | The operator must filter the menu with a free-text search. This search is one of the permitted OSK uses. | Must |
| FR-05 | The application must add the selected executable file to the draft as token 0. | Must |
| FR-06 | The application must show the known flags of the selected program in a list. The operator selects a flag. The operator does not spell the flag. | Must |
| FR-07 | The application must supply a file browser. The operator selects a path. The application adds the path to the draft as a token. | Must |
| FR-08 | The application must supply a connector menu with `\|`, `>`, `>>`, `<`, `2>`, `2>&1`, `&&`, and `;`. | Must |
| FR-09 | The application must quote each token correctly when it makes the command text. | Must |
| FR-10 | The application must show the draft as a horizontal list of tokens. The operator moves a cursor along the tokens. | Must |
| FR-11 | The operator must delete, replace, and insert a token at the cursor position. | Must |
| FR-12 | The application must start the draft only after an explicit Run action. | Must |
| FR-13 | The application must show a confirmation dialog before it starts a dangerous command. See Section 15.2. | Must |
| FR-14 | The application must show the output of the host shell in a scrollback pane. | Must |
| FR-15 | The operator must scroll the scrollback with the stick or the D-pad. | Must |
| FR-16 | The operator must search the scrollback. | Should |
| FR-17 | The application must show the environment variables in a list. | Must |
| FR-18 | The operator must create, change, and delete an environment variable. | Must |
| FR-19 | The application must save a draft as a named script. | Should |
| FR-20 | The application must show the saved scripts in the catalog with the executable files. | Should |
| FR-21 | The application must record the command history. The operator selects a command from the history, and edits it. | Should |
| FR-22 | The operator must remap each control. The application reads the map from a configuration file. | Should |
| FR-23 | The application must let the operator send raw keys to the host shell for interactive programs. | Should |
| FR-24 | The application must supply a text-input pane for a literal argument. | Must |

### 5.2 Non-Functional Requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | Input latency. The time from a button event to the new screen content. | Less than 50 ms at the 95th percentile |
| NFR-02 | Cold start time. | Less than 500 ms |
| NFR-03 | Catalog build time for 5000 files. | Less than 1000 ms |
| NFR-04 | Catalog read time from the cache. | Less than 50 ms |
| NFR-05 | Resident memory. | Less than 80 MB |
| NFR-06 | CPU load when idle. | Less than 1 percent |
| NFR-07 | Frame rate limit. The application must not draw more than 30 frames per second. | 30 fps maximum |
| NFR-08 | Output throughput. The application must not lose output at 10 MB/s from the host shell. | No loss |
| NFR-09 | Distribution. The product is one static binary with no runtime dependency. | 1 file |

---

## 6. Solution Options

### 6.1 Option A — A Plugin in the Shell

Write a bash or zsh plugin. The plugin reads the gamepad and writes to the command line with the shell line editor.

| Advantage | Disadvantage |
|---|---|
| Small quantity of code. | The shell line editor gives no control of the screen layout. |
| No new process. | Panes, menus, and a file browser are not possible. |
| Full shell semantics. | The gamepad is difficult to read from a shell script. |

**Result: rejected.** The plugin cannot satisfy FR-01, FR-07, and FR-14.

### 6.2 Option B — A TUI Front End over a PTY

Write an application that owns the screen. The application starts the host shell in a PTY. The application draws all panes. The application writes command text into the PTY.

| Advantage | Disadvantage |
|---|---|
| Full control of the screen and the input. | The application must parse terminal escape sequences. |
| Full shell semantics, because a real shell runs below. | The application must manage the PTY correctly. |
| Aliases, functions, and the operator `rc` files continue to operate. | More code than Option A. |
| The application operates in a terminal, on a bare TTY, or in a window. | |

**Result: recommended.**

### 6.3 Option C — A New Shell

Write a shell. Run each command directly with `fork` and `exec`. Do not use a host shell.

| Advantage | Disadvantage |
|---|---|
| Full control of the command model. | The application loses aliases, functions, and `rc` files. |
| No PTY parser for the shell prompt. | Job control is complex. Signal handling is complex. |
| | The operator must learn a new environment. This result contradicts G8. |

**Result: rejected as the primary design. Adopted in part.** Section 7.2 explains the hybrid.

### 6.4 Option D — A Graphical Application

Write an application with SDL or a GPU toolkit. Draw the text with a font renderer.

| Advantage | Disadvantage |
|---|---|
| Good visual quality. Smooth animation. | The application must contain a full text stack. |
| Direct gamepad access. | Higher memory use and higher battery use. |
| | The application cannot operate over SSH or in a terminal. |

**Result: rejected for version 1. Keep as a future backend.** Section 14 keeps the view layer independent of the backend.

### 6.5 The Recommendation

Build **Option B**. Use the command model of **Option C** for the editor. Section 7.2 explains this hybrid.

---

## 7. The Central Design Decisions

### 7.1 Decision 1 — The Application Owns the Terminal

The application is the terminal. The host shell is a child process on a PTY. The application:

1. Opens a PTY pair.
2. Starts bash or zsh on the child side.
3. Reads the output bytes from the master side.
4. Parses the bytes with a VT parser into a character grid.
5. Draws the grid in the output pane.
6. Writes command text to the master side when the operator starts a command.

### 7.2 Decision 2 — Edit a Tree, Not a String

Do not let the operator edit a string of characters. A string is a bad model for gamepad editing.

Let the operator edit a **tree**. The tree is a small abstract syntax tree (AST). Each node is a command. Each command has a program, a list of arguments, and a list of redirections.

The application converts the tree into shell text one time only, immediately before it starts the command. This design gives four benefits:

- The operator selects and deletes a whole token with one action. Character positions are not necessary.
- The application quotes each token correctly, because it knows the token boundaries.
- The application shows a flag menu, because it knows which program is token 0.
- The application saves and reloads a draft, because the tree serializes to a data file.

### 7.3 Decision 3 — Two Input Layers

Layer 1 translates a physical event into an Action. Layer 2 translates an Action into a state change. The Mode selects the translation table in Layer 1.

This separation gives three benefits:

- The operator remaps the controls in a configuration file.
- The keyboard and the gamepad produce the same Actions. Test and use become identical.
- The core has no knowledge of hardware. Section 17 uses this property for the tests.

### 7.4 Decision 4 — A Pure Core

The core is a function of this form:

```
update(state, event) -> (new_state, effects)
```

The core does no I/O. The runtime performs the effects. The core is deterministic. Therefore you can test the core with a list of events and no hardware.

---

## 8. Recommended Language

### 8.1 The Summary

Two languages satisfy all requirements. The two languages are **Rust** and **C++20**. The difference between them is small. The target hardware decides the choice.

- Select **Rust** if you build for a standard Linux distribution, and if you control the toolchain.
- Select **C++20** if you build against a vendor board support package (BSP), or if you must draw directly on a bare TTY at version 1.

Section 8.8 gives the decision rule. Section 8.10 shows that the choice is reversible, because the architecture does not depend on the language.

### 8.2 The Candidates

| Candidate | Status |
|---|---|
| Rust | Recommended. See Section 8.5. |
| C++20 | Recommended alternative. See Section 8.4. |
| C (C11) | Viable, but more work. See Section 8.7. |
| Go | Good, but two libraries are absent. See Section 8.6. |
| Zig | Rejected. The ecosystem is not sufficient. |
| Python | Rejected. The start time and the packaging fail NFR-02 and NFR-09. |

### 8.3 The Comparison

| Criterion | Rust | C++20 | C (C11) | Go | Zig | Python |
|---|---|---|---|---|---|---|
| Start time (NFR-02) | Excellent | Excellent | Excellent | Good | Excellent | Poor |
| Memory use (NFR-05) | Excellent | Excellent | Excellent | Fair (GC) | Excellent | Poor |
| Single static binary (NFR-09) | Yes | Yes | Yes | Yes | Yes | No |
| TUI library | `ratatui` | `notcurses`, `FTXUI` | `notcurses`, `ncurses` | `bubbletea` | Immature | `textual` |
| Direct TTY / DRM output | Manual work | `notcurses` (built in) | `notcurses` (built in) | Manual work | Manual | No |
| PTY control | `portable-pty` | `forkpty(3)` | `forkpty(3)` | `creack/pty` | Manual | `ptyprocess` |
| VT parser | `vte` (Alacritty) | `libvterm` (Neovim) | `libvterm` | Limited | None | `pyte` (slow) |
| Gamepad input | `gilrs` | `SDL_GameController` | `SDL_GameController` | Limited | Manual | `pygame` |
| Controller map database | Uses the SDL database | **Is** the SDL database | **Is** the SDL database | Manual | Manual | Uses SDL |
| Fuzzy search | `nucleo` (Helix) | `fzf`-class libraries, or local | Local code | Go libraries | Manual | `rapidfuzz` |
| Configuration parse | `serde` + `toml` | `toml++` | `tomlc99` | `BurntSushi/toml` | Manual | Standard library |
| Memory safety of the serializer | **Enforced** | Manual | Manual | Enforced (GC) | Manual | Enforced |
| Exhaustive match on the token type | **Yes** (`match`) | Partial (`std::visit`) | No | No | Yes | No |
| Dependency management | Cargo | vcpkg, Conan, or vendoring | Manual | Modules | Immature | pip |
| Cross-compile to a vendor BSP | Fair | **Excellent** | **Excellent** | Good | Fair | Poor |
| Development speed | Fair | Fair | Poor | Excellent | Fair | Excellent |
| Fitness for this task | **Excellent** | **Excellent** | Good | Good | Poor | Poor |

### 8.4 The Case for C++20

C++20 is a strong candidate. Three properties make it strong.

**1. `notcurses` supplies two backends in one library.** Section 14 lists a terminal backend for version 1, and a framebuffer or DRM backend for version 2. `notcurses` supplies both. It draws in a terminal. It also draws on a bare Linux TTY with no X server and no Wayland compositor. This property removes a complete milestone from Section 18. Rust has no equivalent library.

**2. SDL is the source of the controller map database.** `gilrs` reads the SDL controller database. `SDL_GameController` **is** that database. A C++ application uses the primary source, and receives each update immediately. Risk R3 becomes smaller.

**3. The PTY code is libc code.** `forkpty(3)`, `openpty(3)`, `ioctl(TIOCSWINSZ)`, and `waitpid(2)` are POSIX functions. `portable-pty` is a wrapper of the same functions. Rust gives no advantage here. `libvterm` is the parser of the Neovim terminal. It has the same maturity as `vte`.

**The C++ library stack:**

| Library | Function | Note |
|---|---|---|
| `notcurses` | Drawing, terminal control, and the TTY/DRM backend | Replaces `ratatui` and `crossterm` |
| `libvterm` | Escape sequence parser | The Neovim parser |
| `SDL2` (`SDL_GameController`) | Gamepad events, hotplug, and the map database | The reference implementation |
| `forkpty(3)` from libc | PTY creation and process control | No library is necessary |
| `toml++` | Configuration files and specification files | Header only |
| `{fmt}` | Text format | In the standard library from C++20 |
| `spdlog` | Structured logs | Optional |
| `Catch2` or `doctest` | Tests | Necessary for Section 17 |
| `libinotify` or `inotify(7)` | File system watch | In libc |

**The C++ language features to use:**

- `std::variant` and `std::visit` for the `Token` type.
- `std::unique_ptr` for the `Subshell` node.
- `std::string_view` for the parse code, but **not** for the serializer. See Section 8.6.
- Concepts for the `Backend` interface.
- `std::expected` (C++23) or a local `Result` type for the errors. Do not use exceptions in the core.

### 8.5 The Case for Rust

Rust is strong for one reason above all others: **the serializer is the critical component, and Rust protects it.**

Risk R4 in Section 19 is the only Critical risk in the project. A quoting defect causes command injection or data loss. The serializer receives operator text, and it produces text that the shell runs. Rust gives three protections:

- The `Token` enum forces an exhaustive `match`. A new token type causes a compile error in each place that handles tokens. `std::visit` in C++ gives a similar result, but only if the developer does not add a default case.
- The borrow checker prevents a dangling `std::string_view` into a freed buffer. This defect class is a frequent cause of injection in C++.
- The ownership rules make the buffer lifetimes clear when the core builds the command text.

Rust also wins on the small operations. Cargo manages the eleven dependencies with one file. `nucleo` is production code from the Helix editor. `serde` removes all manual parse code for the specification files in Section 12.2.

### 8.6 Where Each Language Is Weak

**Rust is weak in three places:**

- Cross-compilation to a vendor BSP is difficult. A handheld device with a vendor kernel often has an unusual glibc version, or a musl target with no prebuilt standard library. This work costs days.
- The framebuffer and DRM backend needs manual code. `notcurses` gives this backend to C++ for no cost.
- Development speed is lower than Go, and lower than C++ for a team that knows C++ well.

**C++ is weak in three places:**

- The serializer has no structural protection. You must find each defect with the tests in Section 17.2.
- Dependency management is manual. Four of the libraries need vendoring, vcpkg, or a system package.
- `std::visit` does not force exhaustiveness if a developer adds `auto&&` as a default case. Prohibit this pattern in the code review.

**Go is weak in two places.** Go has no equivalent of `vte`, and no equivalent of `gilrs`. You must write a VT parser and an `evdev` reader. These two components are approximately 4 weeks of work, and they carry high defect risk. Select Go only if the team knows Go, and does not know Rust or C++.

### 8.7 Plain C

C satisfies the non-functional requirements. `notcurses`, `libvterm`, and `SDL2` are C libraries. Therefore the library stack is identical to the C++ stack.

C is weaker than C++ for one reason. The `Token` type is a tagged union, and the `Pipeline` type is a tree with variable length lists. In C you write the memory management for these types by hand. This code is exactly the code that must not have a defect, because of Risk R4.

Select C only if a constraint prohibits C++. An example is a toolchain with no C++ standard library.

### 8.8 The Decision Rule

Answer the questions in order. Stop at the first answer that decides.

1. **Does the target hardware need a vendor BSP, or a vendor kernel with an unusual libc?**
   Yes → **Use C++20.** The cross-compilation cost decides.
   No → Continue.

2. **Must version 1 draw on a bare TTY, with no terminal emulator?**
   Yes → **Use C++20.** `notcurses` supplies this backend immediately.
   No → Continue.

3. **Does the team know C++ well, and Rust not at all?**
   Yes → **Use C++20.** The learning cost is larger than the safety benefit at this project size.
   No → Continue.

4. **In all other conditions → Use Rust.** The protection of the serializer is the deciding property.

Answer Open Question 5 in Section 20 before you apply this rule. That question identifies the reference hardware.

### 8.9 The Dependency Lists

**Rust crates:**

| Crate | Function |
|---|---|
| `ratatui` | Widget layout and drawing |
| `crossterm` | Terminal backend, raw mode, key events |
| `portable-pty` | PTY creation and process control |
| `vte` | Escape sequence parser |
| `gilrs` | Gamepad events and hotplug |
| `nucleo` | Fuzzy match and sort |
| `serde` + `toml` | Configuration and specification files |
| `notify` | File system watch for `PATH` changes |
| `shell-quote` or a local module | Correct quoting for bash and zsh |
| `directories` | XDG paths |
| `anyhow` + `thiserror` | Error types |
| `tracing` | Structured logs |

**C++20 libraries:** see the table in Section 8.4.

### 8.10 The Choice Is Reversible

The architecture in Sections 9 to 12 does not depend on the language. Each of these designs translates directly:

| Design element | Rust | C++20 |
|---|---|---|
| The pure core | A crate with no I/O dependency | A static library with no I/O link |
| `update(state, event)` | A free function | A free function |
| The `Token` type | `enum` + `match` | `std::variant` + `std::visit` |
| The event channel | `std::sync::mpsc` | A `std::queue` with a mutex and a condition variable |
| The `Backend` trait | `trait` | A concept, or an abstract base class |
| The specification files | `serde` + TOML | `toml++` |
| The effects | An `enum` list | A `std::variant` list |

Therefore you can start the M0 skeleton in one language, and you can change the language before M2 at a moderate cost. Do not change the language after M2.

---

## 9. Architecture

### 9.1 The Layer Diagram

```
+---------------------------------------------------------------+
|  INPUT SOURCES  (threads)                                      |
|  gilrs gamepad   |  crossterm keys  |  PTY reader  |  ticker   |
+--------|---------------|-----------------|-------------|-------+
         |               |                 |             |
         +---------------+--------+--------+-------------+
                                  |
                          mpsc::Sender<AppEvent>
                                  |
+---------------------------------v-----------------------------+
|  INPUT NORMALIZER            (gpsh-input)                      |
|  Button + Mode -> Action.  Dead zone. Repeat. Chords.          |
+---------------------------------|-----------------------------+
                                  |
+---------------------------------v-----------------------------+
|  APPLICATION CORE            (gpsh-core)      NO I/O           |
|  update(state, event) -> effects                               |
|  +---------------+ +--------------+ +----------------------+   |
|  | Mode machine  | | Draft (AST)  | | Selection + cursor   |   |
|  +---------------+ +--------------+ +----------------------+   |
+------------|--------------------------------------|-----------+
             | effects                              | state (read only)
+------------v------------+          +--------------v-----------+
|  RUNTIME / EFFECTS      |          |  VIEW LAYER  (gpsh-ui)   |
|  write PTY, scan disk,  |          |  Panes, menus, OSK,      |
|  save file, spawn task  |          |  scrollback view         |
+------------|------------+          +--------------|-----------+
             |                                      |
+------------v------------+          +--------------v-----------+
|  PTY SESSION (gpsh-pty) |          |  BACKEND                 |
|  bash / zsh + VT parse  |          |  crossterm | TTY | SDL   |
+-------------------------+          +--------------------------+
```

### 9.2 The Event Loop

The application has one core thread. Producer threads send events into one channel. The core thread does this sequence:

1. Receive one event. Block if the channel is empty.
2. Call `update`. Get the effects.
3. Send each effect to the runtime.
4. Set the "dirty" flag if the state changed.
5. Drain the channel of all events that are ready. Repeat steps 2 to 4.
6. Draw one frame if the dirty flag is set, and if 33 ms passed after the last frame.

Step 5 is important. It coalesces a burst of PTY output into one frame. This behavior satisfies NFR-07 and NFR-08.

### 9.3 The Thread Map

| Thread | Function | Communication |
|---|---|---|
| `main` | Core loop and drawing | Owns the state |
| `input-pad` | `gilrs` event loop | Sends `AppEvent::Pad` |
| `input-key` | `crossterm` event loop | Sends `AppEvent::Key` |
| `pty-read` | Reads the PTY master | Sends `AppEvent::PtyBytes` |
| `catalog` | Scans `PATH`, builds the index | Sends `AppEvent::CatalogReady` |
| `argspec` | Parses `--help` on demand | Sends `AppEvent::SpecReady` |

Only the `main` thread holds the state. No lock is necessary.

---

## 10. Data Models

### 10.1 The Command Model

```rust
/// One element of a command.
pub enum Token {
    /// The program name. Token 0 of a node.
    Program { name: String, path: PathBuf },
    /// A short flag or a long flag. Example: -l or --color=auto.
    Flag { text: String, takes_value: bool },
    /// A literal string from the OSK.
    Literal(String),
    /// A path from the file browser. The serializer quotes it.
    Path(PathBuf),
    /// A variable reference. Example: $HOME.
    VarRef(String),
    /// A nested command. Example: $(date).
    Subshell(Box<Pipeline>),
}

/// A redirection of one stream.
pub struct Redirect {
    pub fd: u16,          // 0, 1, or 2
    pub op: RedirectOp,   // Read, Write, Append, Duplicate
    pub target: Token,
}

/// One command in a pipeline.
pub struct Node {
    pub tokens: Vec<Token>,       // tokens[0] is always a Program
    pub redirects: Vec<Redirect>,
}

/// How two nodes connect.
pub enum Connector { Pipe, And, Or, Sequence }

/// The full command.
pub struct Pipeline {
    pub nodes: Vec<Node>,
    pub links: Vec<Connector>,    // links.len() == nodes.len() - 1
    pub background: bool,
}

/// The command that the operator edits.
pub struct Draft {
    pub pipeline: Pipeline,
    pub cursor: Cursor,           // which node, which token
    pub undo: Vec<Pipeline>,      // limit 32
}
```

**Rule:** the application must never build the command text by concatenation. The application must call one serializer function. Section 17.2 specifies the tests of this function.

### 10.2 The Catalog Model

```rust
pub struct CatalogEntry {
    pub name: String,
    pub path: PathBuf,
    pub source: SourceKind,   // SystemBin, LocalBin, UserBin, Cwd, Script, Builtin
    pub group: usize,         // index of the source directory
    pub score: u32,           // frequency of use, for the sort order
    pub has_spec: bool,       // an argument specification exists
}

pub struct Catalog {
    pub entries: Vec<CatalogEntry>,
    pub groups: Vec<GroupHeader>,
    pub built_at: SystemTime,
}
```

### 10.3 The State Model

```rust
pub enum Mode {
    Browse,        // the operator reads the output
    Catalog,       // the program menu is open
    Args,          // the flag menu is open
    Files,         // the file browser is open
    Connector,     // the connector menu is open
    Env,           // the variable editor is open
    Text,          // the OSK is open
    Search,        // the scrollback search is open
    Passthrough,   // all input goes to the host shell
    Confirm,       // a dialog waits for a decision
}

pub struct AppState {
    pub mode: Mode,
    pub mode_stack: Vec<Mode>,   // a menu returns to its caller
    pub draft: Draft,
    pub catalog: Catalog,
    pub screen: TerminalGrid,    // from the VT parser
    pub scrollback: RingBuffer<Line>,
    pub env: Vec<(String, String)>,
    pub history: Vec<Pipeline>,
    pub status: StatusLine,
}
```

### 10.4 The Event and Effect Models

```rust
pub enum AppEvent {
    Pad(PadEvent),
    Key(KeyEvent),
    PtyBytes(Vec<u8>),
    CatalogReady(Catalog),
    SpecReady(String, ArgSpec),
    Tick,
    Resize(u16, u16),
}

pub enum Effect {
    WritePty(Vec<u8>),
    ScanCatalog,
    LoadSpec(String),
    SaveScript(String, Pipeline),
    ReadEnv,
    Quit,
}
```

---

## 11. The Input Model

### 11.1 The Two Layers

Layer 1 is a table. The key of the table is `(Mode, PhysicalInput)`. The value is an Action. The application reads the table from `keymap.toml`.

Layer 2 is the core. The core receives the Action only.

### 11.2 The Default Map

| Physical control | Browse | Catalog / Files / Env | Text (OSK) |
|---|---|---|---|
| D-pad up/down | Scroll one line | Move the selection | Move the cursor |
| D-pad left/right | Move the token cursor | Change the group | Move the cursor |
| Left stick | Scroll with acceleration | Move the selection fast | Move the cursor |
| Right stick | Scroll the scrollback fast | Not used | Not used |
| A (south) | Open the catalog | Confirm the selection | Type the character |
| B (east) | Delete the token at the cursor | Cancel. Return to the caller | Delete one character |
| X (west) | Open the connector menu | Open the search (OSK) | Space |
| Y (north) | Open the file browser | Toggle a detail view | Change the layer |
| L1 | Previous group | Previous group | Change the layout |
| R1 | Next group | Next group | Change the layout |
| L2 (hold) | Chord modifier | Chord modifier | Not used |
| R2 | **Run the draft** | Not used | Confirm the text |
| Start | Open the main menu | Close the menu | Close the OSK |
| Select | Open the variable editor | Not used | Not used |
| L2 + A | Save the draft as a script | | |
| L2 + B | Clear the draft | | |
| L2 + Y | Open the history | | |
| L2 + Start | Enter Passthrough mode | | |

### 11.3 The Analog Rules

- Apply a radial dead zone of 0.25 of the full range.
- Convert the stick position into repeat events. Use a rate of 4 Hz at 0.3 deflection, and 25 Hz at 1.0 deflection.
- Apply a first-repeat delay of 250 ms to the D-pad. Then repeat at 15 Hz.
- Debounce each button for 20 ms.

### 11.4 The OSK Design

Supply three layouts. The operator changes the layout with L1 and R1.

1. **Grid.** A 10 x 4 grid of characters. The operator moves with the D-pad, and confirms with A. This layout is simple, but slow.
2. **Radial.** Eight groups of eight characters. The operator selects the group with the left stick, and the character with the face buttons. An expert operator reaches 60 characters per minute with this layout.
3. **Suggestion row.** A row above the layout. The row shows path completions, history items, and catalog names. The operator selects a suggestion with the shoulder controls. This row removes most of the text entry.

---

## 12. Subsystem Designs

### 12.1 The Catalog

**Build procedure:**

1. Read `PATH` from the host shell environment.
2. Read the directory entries of each `PATH` component.
3. Keep an entry if the file has the execute bit for the operator.
4. Add the executable files of the current directory. Mark them `Cwd`.
5. Add the saved scripts from `$XDG_DATA_HOME/gpsh/scripts`. Mark them `Script`.
6. Add the shell built-in commands from a static list. Mark them `Builtin`.
7. Remove a duplicate name. Keep the first entry in `PATH` order.
8. Sort each group by the use score, then by the name.
9. Write the index to `$XDG_CACHE_HOME/gpsh/catalog.bin`.

**Cache validation:** compare the `mtime` of each `PATH` directory with the value in the cache. Rebuild only the groups that changed. This procedure satisfies NFR-04.

**Search:** send the query to `nucleo`. Show the results in one flat list. Keep the group headers visible in the unfiltered list only.

### 12.2 Argument Assistance

Use four tiers. Try the tiers in order. Stop at the first tier that gives a result.

| Tier | Source | Confidence | Cost |
|---|---|---|---|
| 1 | A bundled specification file. One TOML file for each common command. | High | None |
| 2 | The completion functions of the host shell, through `compgen` or `compsys`. | Medium | 50 ms |
| 3 | A parse of the `--help` output with a heuristic. | Low | 100 ms |
| 4 | A free-form entry with the OSK. | None | Operator time |

The specification format of Tier 1:

```toml
# specs/ls.toml
name = "ls"
summary = "List the directory contents."

[[flags]]
short = "-l"
help = "Use the long format."

[[flags]]
short = "-a"
long = "--all"
help = "Show the hidden files."

[[flags]]
long = "--color"
takes_value = true
values = ["auto", "always", "never"]
help = "Control the color output."

[[positional]]
name = "path"
kind = "directory"     # the file browser uses this hint
repeat = true
```

Supply approximately 60 specification files with the product. Cover `ls`, `cd`, `cat`, `grep`, `find`, `ps`, `kill`, `git`, `tar`, `ssh`, and similar commands. Let the operator add a specification file.

### 12.3 The Draft Editor

The draft pane shows the tokens as a horizontal strip. Example:

```
 [ grep ] [ -i ] [ "error" ] [ /var/log/syslog ]  |  [ head ] [ -n 20 ]  >  [ out.txt ]
     ^^^^^^^^
     cursor
```

Rules:

- The cursor selects one token, or one connector, or the end position.
- The operator inserts a token at the cursor position.
- The operator replaces a token. The application opens the menu that is correct for the token type.
- The application keeps 32 undo steps.
- The application shows the serialized command text below the strip. This text lets an experienced operator confirm the result.

### 12.4 The File Browser

- Read one directory at a time. Do not read the tree.
- Show the size, the type, and the permission bits.
- Sort the directories before the files.
- Let the operator show or hide the dot files with one action.
- Let the operator select more than one file. Each file becomes one token.
- Return the absolute path, or the relative path if the file is below the current directory.
- Filter the list by the `kind` hint from the specification file. Example: show directories only for `cd`.

### 12.5 The Environment Editor

- Read the variables with `env -0` in the host shell. Parse the null-separated output.
- Show the list. Show a long value in a wrapped detail pane.
- Set a variable with `export NAME=value` in the host shell. Quote the value.
- Delete a variable with `unset NAME`.
- Mark a variable as persistent. For a persistent variable, write the line into a managed block of the `rc` file:

```bash
# >>> gpsh managed block >>>
export EDITOR='nano'
# <<< gpsh managed block <<<
```

Never write outside this block. Never delete a line that the operator did not create with the application.

### 12.6 The Output Pane

- Send the PTY bytes to the `vte` parser.
- Keep a grid of cells. Each cell has a character, a foreground color, a background color, and attributes.
- Push each line that leaves the top of the grid into a ring buffer. Limit the ring buffer to 10 000 lines, or to 8 MB.
- Support scroll regions, alternate screen, and the common SGR codes. An application such as `htop` or `vim` must operate in Passthrough mode.
- Supply a mark mode. The operator sets the start and the end with two actions. The application copies the text to a local register. The operator inserts the register as a Literal token.

### 12.7 Scripts and Macros

This subsystem satisfies G7, and it gives the "TI calculator" property.

- Save a `Pipeline` as a `.gpsh.toml` file in `$XDG_DATA_HOME/gpsh/scripts`.
- Show the saved scripts in the catalog with the group name `Scripts`.
- Let a script contain a parameter. Show a form when the operator starts the script. Fill each parameter from the file browser or the OSK.
- Let the operator export a script as a POSIX shell file. Write the same serialized text, with a `#!/bin/sh` line at the top.

---

## 13. Program Structure

### 13.1 The Workspace

Use a Cargo workspace. Each crate has one responsibility. `gpsh-core` must have no I/O dependency.

If you select C++20 in Section 8.8, use Appendix A. Appendix A gives the equivalent structure with CMake. The module boundaries are identical.

```
gpsh/
├── Cargo.toml                  # workspace manifest
├── README.md
├── crates/
│   ├── gpsh-core/              # NO I/O. Pure logic. High test coverage.
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── model/
│   │       │   ├── token.rs        # Token, Redirect, Node, Pipeline
│   │       │   ├── draft.rs        # Draft, Cursor, undo
│   │       │   └── state.rs        # AppState, Mode, mode stack
│   │       ├── update.rs           # update(state, event) -> effects
│   │       ├── action.rs           # the Action enum
│   │       ├── effect.rs           # the Effect enum
│   │       └── serialize/
│   │           ├── mod.rs          # Pipeline -> String
│   │           ├── quote.rs        # POSIX and zsh quoting
│   │           └── danger.rs       # the dangerous command detector
│   │
│   ├── gpsh-input/             # gamepad, keyboard, and the map
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── pad.rs              # the gilrs thread
│   │       ├── keyboard.rs         # the crossterm thread
│   │       ├── keymap.rs           # (Mode, Input) -> Action
│   │       ├── repeat.rs           # the repeat and acceleration rules
│   │       └── chord.rs            # the modifier chords
│   │
│   ├── gpsh-catalog/           # the executable file index
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── scan.rs             # the PATH walk
│   │       ├── cache.rs            # the binary cache and its validation
│   │       ├── search.rs           # the nucleo matcher
│   │       └── score.rs            # the frequency and recency score
│   │
│   ├── gpsh-argspec/           # the flag knowledge
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── spec.rs             # the TOML model
│   │       ├── bundled.rs          # the built-in specification files
│   │       ├── compgen.rs          # Tier 2, the host shell completion
│   │       └── helpparse.rs        # Tier 3, the --help heuristic
│   │
│   ├── gpsh-pty/               # the host shell session
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── session.rs          # the spawn, the resize, the signals
│   │       ├── reader.rs           # the read thread
│   │       ├── vt.rs               # the vte Perform implementation
│   │       ├── grid.rs             # the cell grid
│   │       └── scrollback.rs       # the ring buffer
│   │
│   ├── gpsh-ui/                # the drawing. It reads the state only.
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── layout.rs           # the pane geometry
│   │       ├── theme.rs
│   │       └── panes/
│   │           ├── output.rs
│   │           ├── draft.rs        # the token strip
│   │           ├── catalog.rs
│   │           ├── files.rs
│   │           ├── env.rs
│   │           ├── osk.rs
│   │           ├── hints.rs        # the control legend at the bottom
│   │           └── confirm.rs
│   │
│   ├── gpsh-config/            # the XDG paths and the settings
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── paths.rs
│   │       ├── settings.rs
│   │       └── keymap_file.rs
│   │
│   └── gpsh/                   # the binary. The wiring only.
│       └── src/
│           ├── main.rs             # the argument parse and the setup
│           ├── runtime.rs          # the event loop and the effect execution
│           └── panic.rs            # the terminal restore on a panic
│
├── specs/                      # the bundled argument specification files
│   ├── ls.toml
│   ├── grep.toml
│   └── ... (approximately 60 files)
│
├── assets/
│   ├── keymap.default.toml
│   └── osk.layouts.toml
│
└── tests/
    ├── serialize_golden.rs     # the quoting tests
    ├── core_sequences.rs       # the recorded Action sequences
    └── fixtures/
        └── traces/*.json
```

### 13.2 The Dependency Rule

```
gpsh  ->  gpsh-ui, gpsh-input, gpsh-pty, gpsh-catalog, gpsh-argspec, gpsh-config, gpsh-core
gpsh-ui, gpsh-input, gpsh-pty, gpsh-catalog, gpsh-argspec  ->  gpsh-core
gpsh-core  ->  (no crate in this workspace, and no I/O crate)
```

A pull request that adds an I/O dependency to `gpsh-core` must fail the review. This rule keeps the tests fast and complete.

### 13.3 The Screen Layout

```
+------------------------------------------------------------+
|  gpsh   ~/projects/foo        bash        env: 47   [MODE]  |  status, 1 row
+------------------------------------------------------------+
|                                                            |
|  $ ls -la                                                  |
|  total 48                                                  |
|  drwxr-xr-x  6 user user 4096 Aug 12 10:22 .               |  output pane
|  ...                                                       |  (flexible)
|                                                            |
+------------------------------------------------------------+
| [ grep ] [ -i ] [ "error" ] [ syslog ] | [ head ] [ -n 20 ] |  draft strip
| grep -i 'error' syslog | head -n 20                        |  preview, 1 row
+------------------------------------------------------------+
| A Catalog   B Delete   X Pipe   Y Files   R2 RUN   ST Menu  |  hints, 1 row
+------------------------------------------------------------+
```

When a menu opens, the menu covers the output pane. The draft strip and the hint row always stay visible. The operator must always see the current draft and the current controls.

---

## 14. Display Backends

Keep `gpsh-ui` independent of the backend. Supply a trait:

```rust
pub trait Backend {
    fn size(&self) -> (u16, u16);
    fn draw(&mut self, buffer: &Buffer) -> Result<()>;
    fn flush(&mut self) -> Result<()>;
}
```

| Backend | Use case | Priority |
|---|---|---|
| `crossterm` | The application runs in an existing terminal. | Version 1 |
| Linux framebuffer or DRM | The application runs on a bare TTY with no X server. | Version 2 |
| SDL2 window | The application runs on a desktop, or with a custom font. | Future |

---

## 15. Error Handling and Safety

### 15.1 The General Rules

- The application must never lose the draft because of an error.
- The application must restore the terminal on a panic. Use a panic hook.
- The application must show an error in the status row. The application must not exit.
- If the host shell exits, the application must show a message and offer a restart.

### 15.2 The Dangerous Command Rule

A gamepad makes an accidental selection more probable than a keyboard makes an accidental spelling. Therefore the application must detect a dangerous command, and must ask for a confirmation.

Detect these patterns:

| Pattern | Reason |
|---|---|
| `rm` with `-r` and a path above the home directory | Data loss |
| `dd` with `of=` and a block device | Disk destruction |
| `mkfs.*` | Disk destruction |
| `chmod` or `chown` with `-R` on `/` or `/usr` | System damage |
| `>` on an existing file | Silent overwrite |
| Any command with `sudo` | Elevated privilege |
| `curl` or `wget` with a pipe into a shell | Remote code execution |

The confirmation dialog must show the full command text. The operator must press two different controls in sequence. One button press must never start a dangerous command.

---

## 16. Configuration

Obey the XDG Base Directory Specification.

| Path | Content |
|---|---|
| `$XDG_CONFIG_HOME/gpsh/settings.toml` | The host shell, the theme, and the limits |
| `$XDG_CONFIG_HOME/gpsh/keymap.toml` | The control map |
| `$XDG_CONFIG_HOME/gpsh/specs/` | The operator argument specification files |
| `$XDG_DATA_HOME/gpsh/scripts/` | The saved scripts |
| `$XDG_DATA_HOME/gpsh/history.jsonl` | The command history |
| `$XDG_CACHE_HOME/gpsh/catalog.bin` | The catalog cache |
| `$XDG_STATE_HOME/gpsh/log` | The log files |

---

## 17. Test Strategy

### 17.1 The Principle

The pure core makes hardware unnecessary in the test environment. Continuous integration must run all core tests with no gamepad and no terminal.

### 17.2 The Test Types

| Type | Target | Method |
|---|---|---|
| Unit | The serializer | Golden files. Compare the output with `printf %q` from bash. |
| Property | The quoting function | Generate a random string. Serialize it. Run `echo`. Compare the result with the input. |
| Unit | The core reducer | Send a list of Actions. Compare the final state with a snapshot. |
| Integration | The PTY session | Start `sh -c 'echo hello'`. Compare the parsed grid. |
| Integration | The catalog | Build a temporary directory tree. Verify the index and the precedence. |
| Replay | The full application | Record an Action trace as JSON. Replay the trace. Compare the frames. |
| Manual | The latency | Measure with a high-speed camera, or with a `tracing` timestamp. |

### 17.3 The Critical Test

The quoting test is the most important test in the project. A quoting defect causes command injection or data loss. Write this test first. Give it 100 percent branch coverage.

---

## 18. Milestones

| ID | Milestone | Content | Estimate |
|---|---|---|---|
| M0 | The skeleton | The workspace, the event loop, the PTY, and a raw terminal view. The operator sees the shell output. | 1 week |
| M1 | The catalog | The `PATH` scan, the cache, the menu, and the selection. FR-01 to FR-05. | 1 week |
| M2 | The draft | The AST, the token strip, the serializer, and the Run action. FR-09 to FR-12. | 1.5 weeks |
| M3 | The paths and the pipes | The file browser and the connector menu. FR-07, FR-08. | 1 week |
| M4 | The text | The OSK, the search, and the suggestion row. FR-04, FR-24. | 1.5 weeks |
| M5 | The environment and the safety | The variable editor and the confirmation dialog. FR-17, FR-18, FR-13. | 1 week |
| M6 | The specifications | The flag menu and the 60 bundled files. FR-06. | 2 weeks |
| M7 | The scripts | Save, load, parameters, and export. FR-19, FR-20. | 1 week |
| M8 | The polish | The remap file, the theme, the framebuffer backend, and the packaging. | 2 weeks |

M0 to M3 give the minimum usable product. The success criterion in Section 2.3 becomes possible at the end of M3.

---

## 19. Risks

| ID | Risk | Effect | Mitigation |
|---|---|---|---|
| R1 | The VT parser is incomplete. A full-screen program shows incorrect output. | High | Use `vte`. Do not write a parser. Supply Passthrough mode as the fallback. |
| R2 | The `--help` parse gives incorrect flags. | Medium | Show the confidence level. Let the operator edit the specification file. Prefer Tier 1. |
| R3 | The gamepad has a different button map on different hardware. | Medium | Use the SDL game controller database through `gilrs`. Supply a calibration screen. |
| R4 | The quoting is incorrect. The application runs an incorrect command. | Critical | Write the property tests in Section 17.2 before the feature code. |
| R5 | The catalog scan is slow on a slow storage device. | Medium | Scan in a thread. Show the cache immediately. Update the list when the scan ends. |
| R6 | The screen is too small for the panes. | Medium | Define a minimum size of 60 x 20 cells. Hide the hint row below this size. |
| R7 | The operator wants a feature that needs text. Example: a `sed` expression. | Low | Accept this limit. The OSK covers this case. Add a snippet library. |

---

## 20. Open Questions

1. Does the operator want job control? Job control adds much complexity. A first version can omit it.
2. Does the second screen show the OSK only, or does it show a second pane? A two-screen layout changes Section 13.3.
3. Does the product support a remote host over SSH? This support changes the catalog source.
4. Is `zsh` completion (Tier 2) worth the cost? Measure the accuracy against Tier 3 before the implementation.
5. Which handheld hardware is the reference target? This answer sets the minimum screen size and the gamepad map.

---

## 21. The Condensed Implementation Prompt

Give the text below to an implementer or to an AI agent.

> Build a Unix application in Rust, or in C++20. The application lets an operator use bash or zsh with a gamepad, and with almost no text entry.
>
> **The language.** Use Rust if the target is a standard Linux distribution. Use C++20 if the target needs a vendor BSP, or if version 1 must draw on a bare TTY.
>
> **Architecture.** The application owns the terminal. It starts the host shell in a PTY. It parses the shell output with a VT parser. It draws all panes with a TUI library. It reads the gamepad with a controller library.
> In Rust use `portable-pty`, `vte`, `ratatui` with `crossterm`, and `gilrs`.
> In C++20 use `forkpty(3)`, `libvterm`, `notcurses`, and `SDL_GameController`.
>
> **The central rule.** The operator edits a small abstract syntax tree, and does not edit a string. The tree has this form: `Pipeline { nodes: Vec<Node>, links: Vec<Connector> }`, and `Node { tokens: Vec<Token>, redirects: Vec<Redirect> }`. One serializer function converts the tree into shell text. The serializer quotes each token. The application writes the text into the PTY only when the operator presses Run.
>
> **The core rule.** The core is `update(state, event) -> (state, effects)`. The core does no I/O. The runtime performs the effects. Put the core in a crate with no I/O dependency.
>
> **The input rule.** A physical button becomes an Action through a table. The key of the table is the pair `(Mode, Input)`. The core receives Actions only. The operator remaps the table in a TOML file.
>
> **The panes.** Supply an output pane, a token strip for the draft, a program catalog from `PATH`, a file browser, a connector menu for `|`, `>`, `>>`, `<`, an environment variable editor, and an on-screen keyboard.
>
> **The catalog.** Scan each `PATH` directory, the current directory, and the script directory. Group the results by the source directory. Cache the index. Search with `nucleo`.
>
> **The flags.** Get the flags of a program from a bundled TOML specification file. If no file exists, parse the `--help` output. If the parse fails, use free text.
>
> **The safety.** Detect a dangerous command such as `rm -rf`, `dd of=`, `mkfs`, or a pipe into a shell. Show a confirmation dialog. Never start a command with one button press.
>
> **The tests.** Test the quoting function first, and test it with property tests against `printf %q`. Test the core with recorded Action traces. Do not use hardware in the tests.
>
> **The order of work.** 1. The PTY and the output pane. 2. The catalog and the menu. 3. The AST, the strip, and Run. 4. The file browser and the connectors. 5. The OSK. 6. The environment editor and the safety dialog. 7. The specification files. 8. The scripts.
>
> **The measure of success.** An operator builds and runs `ls -la /var/log | grep err > out.txt` in less than 20 seconds, and uses no keyboard.

---

## Appendix A — The C++20 Project Structure

Use this structure if Section 8.8 selects C++20. The module boundaries are identical to Section 13.1. Only the build system and the file names change.

```
gpsh/
├── CMakeLists.txt              # the top-level build
├── cmake/
│   ├── FindNotcurses.cmake
│   └── FindLibvterm.cmake
├── vcpkg.json                  # or a conanfile.txt
├── src/
│   ├── core/                   # STATIC LIBRARY. No I/O. No SDL. No notcurses.
│   │   ├── model/
│   │   │   ├── token.hpp           # std::variant<Program, Flag, Literal, Path, ...>
│   │   │   ├── pipeline.hpp        # Node, Connector, Pipeline
│   │   │   └── draft.hpp           # Draft, Cursor, the undo stack
│   │   ├── state.hpp               # AppState, Mode, the mode stack
│   │   ├── update.cpp/.hpp         # update(state, event) -> std::vector<Effect>
│   │   ├── action.hpp
│   │   ├── effect.hpp
│   │   └── serialize/
│   │       ├── serialize.cpp/.hpp  # Pipeline -> std::string
│   │       ├── quote.cpp/.hpp      # POSIX and zsh quoting
│   │       └── danger.cpp/.hpp     # the dangerous command detector
│   │
│   ├── input/
│   │   ├── pad.cpp/.hpp            # the SDL_GameController loop
│   │   ├── keyboard.cpp/.hpp       # the notcurses key input
│   │   ├── keymap.cpp/.hpp         # (Mode, Input) -> Action
│   │   ├── repeat.cpp/.hpp
│   │   └── chord.cpp/.hpp
│   │
│   ├── catalog/
│   │   ├── scan.cpp/.hpp           # the PATH walk with std::filesystem
│   │   ├── cache.cpp/.hpp
│   │   ├── search.cpp/.hpp         # the fuzzy matcher
│   │   └── score.cpp/.hpp
│   │
│   ├── argspec/
│   │   ├── spec.cpp/.hpp           # the toml++ model
│   │   ├── bundled.cpp/.hpp
│   │   ├── compgen.cpp/.hpp
│   │   └── helpparse.cpp/.hpp
│   │
│   ├── pty/
│   │   ├── session.cpp/.hpp        # forkpty, TIOCSWINSZ, waitpid
│   │   ├── reader.cpp/.hpp         # the read thread
│   │   ├── vt.cpp/.hpp             # the libvterm callbacks
│   │   ├── grid.cpp/.hpp
│   │   └── scrollback.cpp/.hpp
│   │
│   ├── ui/
│   │   ├── layout.cpp/.hpp
│   │   ├── theme.cpp/.hpp
│   │   ├── backend.hpp             # the concept or the abstract base class
│   │   └── panes/
│   │       ├── output.cpp/.hpp
│   │       ├── draft.cpp/.hpp
│   │       ├── catalog.cpp/.hpp
│   │       ├── files.cpp/.hpp
│   │       ├── env.cpp/.hpp
│   │       ├── osk.cpp/.hpp
│   │       ├── hints.cpp/.hpp
│   │       └── confirm.cpp/.hpp
│   │
│   ├── config/
│   │   ├── paths.cpp/.hpp          # the XDG paths
│   │   ├── settings.cpp/.hpp
│   │   └── keymap_file.cpp/.hpp
│   │
│   └── main/
│       ├── main.cpp                # the argument parse and the setup
│       ├── runtime.cpp/.hpp        # the event loop and the effect execution
│       └── signals.cpp/.hpp        # the terminal restore on SIGSEGV or SIGABRT
│
├── specs/                      # identical to Section 13.1
├── assets/                     # identical to Section 13.1
└── tests/
    ├── serialize_golden.cpp    # Catch2 or doctest
    ├── quote_property.cpp      # compare with printf %q
    └── core_sequences.cpp
```

### A.1 The Build Rules

- Build `src/core/` as a static library with the name `gpsh_core`.
- Do not link `gpsh_core` to `SDL2`, to `notcurses`, or to `libvterm`. The link must fail if a developer adds one of these dependencies. This rule replaces the Cargo rule in Section 13.2.
- Compile with `-std=c++20 -Wall -Wextra -Werror`.
- Compile the test build with `-fsanitize=address,undefined`. The serializer tests must run with the sanitizers on.

### A.2 The Code Review Rules for C++

These three rules control the risks in Section 8.6. Apply them in each review.

1. **No default case in a `std::visit` on a `Token`.** A default case removes the exhaustiveness check. Write one function object with one overload for each alternative.
2. **No `std::string_view` in the serializer.** The serializer returns owned strings only. This rule removes the dangling reference defect class.
3. **No exception in `gpsh_core`.** Return `std::expected` or a local `Result` type. The core must be deterministic, because Section 17 replays event traces.

---

## Revision History

| Rev | Date | Change |
|---|---|---|
| A | 2026-08-12 | The first issue. |
| B | 2026-08-12 | Section 8 rewritten. C++20 added as a full option with a library stack and a decision rule. Appendix A added with the C++20 project structure. Section 21 updated for two languages. |