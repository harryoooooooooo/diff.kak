# diff.kak

**diff.kak** is inspired by the official `:git show-diff<ret>` tool,
but it can be extended to more kinds of VCS easily.
Also it updates the flags non-blockingly,
which is helpful when you're working on slow storage or VCS.


## Installation

### With [plug.kak](https://github.com/andreyorst/plug.kak)

Add this to the `kakrc`:
``` kak
plug "harryoooooooooo/diff.kak"
```
Then reload the configuration file or restart Kakoune and run `:plug-install`.

### Without plugin manager

This plugin has only one source file. `source`ing it in `kakrc` just works:

``` kak
source "/path/to/diff.kak/rc/diff.kak"
```


## Usage

Add `diff-enable-auto-detect` in `kakrc`, then done.
By default it detects if a buffer links to a file under [Git](https://git-scm.com/) or [Mercurial](https://www.mercurial-scm.org/) control,
and enable the automatic flags update.
The automatic flags update happens on each write to the buffer.

As like the official `:git` command, the plugin provides `:diff-jump [next|prev]` to jump between the hunks,
and `:diff` to show a common diff output in a scratch buffer.

Other than Git and Mercurial, there is also `:diff-file <file_name>` command for tracing the diff of current buffer and a specific file.

Referece the doc of options `diff_command`, `diff_command_readable`, and `diff_need_cd`, to add support of other VCS.
