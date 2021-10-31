# diff: Inspired by the official `:git show-diff<ret>` tool,
# but updates the flags non-blockingly and more extensible.

declare-option -docstring '
The command used by diff-update to generate the diff flags.
The buffer file name is passed to the command.
Only the lines in "@@ -LINE,COUNT +LINE,COUNT @@" format are parsed.
Note that the info provided by the "@@" lines should be accurate,
that is, should not include the unchanged lines. For example,
"diff -U0 file1 file2" gives proper output.' \
str diff_command

declare-option -docstring '
The command used by diff. If not set, diff_command is used.
This command may provide more human readable output.' \
str diff_command_readable

declare-option -docstring '
If true, change directory to the buffer file before
executing diff_command and diff_command_readable.' \
bool diff_need_cd

define-command -docstring '
diff: Show diff in a scratch buffer.' \
    -params 0 diff %{ evaluate-commands %sh{
    comm="${kak_opt_diff_command_readable:-"${kak_opt_diff_command}"}"
    if [ -z "${comm}" ]; then
        echo "fail diff_command_readable or diff_command should be set"
        exit
    fi
    if [ "${kak_opt_diff_need_cd}" = true ]; then
        dirname_buffer="${kak_buffile%/*}"
        cd "${dirname_buffer}" 2>/dev/null || {
            printf 'fail Unable to change the current working directory to: %s\n' "${dirname_buffer}"
            exit
        }
    fi
    output=$(mktemp -d "${TMPDIR:-/tmp}"/kak-diff.XXXXXXXX)/fifo
    mkfifo ${output}
    ( eval "${comm}" '"$kak_buffile"' > ${output} 2>&1 & ) > /dev/null 2>&1 < /dev/null
    printf %s "evaluate-commands -try-client '$kak_opt_docsclient' %{
        edit! -fifo ${output} *diff*
        set-option buffer filetype diff
        hook -always -once buffer BufCloseFifo .* %{ nop %sh{ rm -r $(dirname ${output}) } }
    }"
}}

declare-option -hidden line-specs diff_flags
define-command -docstring '
diff-update: Update the diff flags with the given diff command.
It evaluates the command and updates the flags asynchronously.' \
    -params 0 diff-update %{ evaluate-commands %sh{
    if [ -z "${kak_opt_diff_command}" ]; then
        echo 'fail Option diff_command should be set'
        exit
    fi
    if [ "${kak_opt_diff_need_cd}" = true ]; then
        dirname_buffer="${kak_buffile%/*}"
        cd "${dirname_buffer}" 2>/dev/null || {
            printf 'fail Unable to change the current working directory to: %s\n' "${dirname_buffer}"
            exit
        }
    fi
    ( eval "${kak_opt_diff_command}" '"$kak_buffile"' | grep '^@@' |
        sed -E 's/^@@ -([0-9]+)(,([0-9]+))? \+([0-9]+)(,([0-9]+))? @@.*$/\1,\3,\4,\6/g' |
        awk -F, -v "bufname=$kak_bufname" -v "timestamp=$kak_timestamp" '{
        from_line = $1
        from_length = $2=="" ? 1 : $2
        to_line = $3
        to_length = $4=="" ? 1 : $4

        if (from_length > to_length) {
            if (to_length == 0) {
                if (to_line == 0) {
                    flags[1] = "{red+b}‾" from_length
                } else {
                    # Concatenate here because it is possible that there exist both
                    # to_line = 0 and 1, and their flags would overlap at line #1.
                    flags[to_line] = flags[to_line] "{red+b}_" from_length
                }
            } else {
                for (i=0; i<to_length-1; i++) {
                    flags[i+to_line] = "{blue+b}~"
                }
                last_line = to_line + to_length - 1
                removed_length = from_length - to_length
                flags[last_line] = "{blue+bu}~{blue+b}" removed_length
            }
        } else {
            face = from_length ? "{blue+b}" : "{green}"
            for (i=0; i<to_length; i++) {
                flags[i+to_line] = face (i<from_length ? "~" : "+")
            }
        }
    } END {
        for (ln in flags) flags_arg = flags_arg " " ln "|" flags[ln]
        print "set-option buffer=" bufname " diff_flags " timestamp flags_arg
    }' | kak -p ${kak_session} ) > /dev/null 2>&1 < /dev/null &
}}

define-command -docstring '
diff-enable: Show the diff flags and enable the update hook.
The hook calls diff-update after every write to the buffer.' \
    -params 0 diff-enable %{ evaluate-commands %sh{
    if [ -z "${kak_opt_diff_command}" ]; then
        echo 'fail Options diff_command should be set'
        exit
    fi
    echo 'try %{ add-highlighter buffer/diff flag-lines Default diff_flags }'

    echo 'try %{ remove-hooks buffer diff-hook }'
    echo 'hook -group diff-hook buffer BufWritePost .* %{ diff-update }'

    echo 'diff-update'
}}

define-command -docstring '
diff-disable: Hide the diff flags and disable the update hook.' \
    -params 0 diff-disable %{
    try %{ remove-highlighter buffer/diff }
    try %{ remove-hooks buffer ^diff-hook$ }
}

declare-option -hidden int-list diff_hunk_list
define-command -docstring '
diff-jump [next|prev]: Jump to next|prev diff hunk.' \
    -shell-script-candidates %{ printf 'next\nprev\n' } \
    -params 1 diff-jump %{ evaluate-commands %sh{

    direction=$1

    # Update hunk list if required, and set the hunk list.
    if [ "${kak_timestamp}" != "${kak_opt_diff_hunk_list%% *}" ]; then
        set -- ${kak_opt_diff_flags}
        shift
        new_hunk_list=$kak_timestamp
        prev_line="-1"
        for line in "$@"; do
            line="${line%%|*}"
            if [ "$((line - prev_line))" -gt 1 ]; then
                new_hunk_list="${new_hunk_list} ${line}"
            fi
            prev_line="$line"
        done
        echo "set-option buffer diff_hunk_list ${new_hunk_list}"
        set -- ${new_hunk_list}
    else
        set -- ${kak_opt_diff_hunk_list}
    fi
    shift

    prev_hunk=""
    next_hunk=""
    for hunk in "$@"; do
        if   [ "$hunk" -lt "$kak_cursor_line" ]; then
            prev_hunk=$hunk
        elif [ "$hunk" -gt "$kak_cursor_line" ]; then
            next_hunk=$hunk
            break
        fi
    done

    if   [ "$direction" = "next" ] && [ -n "$next_hunk" ]; then
        echo "select $next_hunk.1,$next_hunk.1"
    elif [ "$direction" = "prev" ] && [ -n "$prev_hunk" ]; then
        echo "select $prev_hunk.1,$prev_hunk.1"
    fi
}}

define-command -docstring '
diff-git [|head|prev]: Set the diff command of the current buffer to git
and enable the update hook. By default it compares with HEAD. Calling
with prev lets it compare with HEAD~ (which is useful when amending).' \
    -shell-script-candidates %{ printf 'head\nprev\n' } \
    -params 0..1 diff-git %{ evaluate-commands %sh{
    dirname_buffer="${kak_buffile%/*}"
    if ! expr "${dirname_buffer}" : '/.*' >/dev/null ||
            ! cd "${dirname_buffer}" 2>/dev/null; then
        echo "fail Invalid file path."
        exit
    fi
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "fail Not in a git work tree."
        exit
    fi
    case "$1" in
        ""|head)
            echo "set-option buffer diff_command          'git --no-pager diff -U0'"
            echo "set-option buffer diff_command_readable 'git --no-pager diff'"
            ;;
        prev)
            echo "set-option buffer diff_command          'git --no-pager diff -U0 HEAD~'"
            echo "set-option buffer diff_command_readable 'git --no-pager diff HEAD~'"
            ;;
        *)
            echo "fail Unknown diff type '$1'"
            ;;
    esac
    echo "set-option buffer diff_need_cd true"
    echo "diff-enable"
}}

define-command -docstring '
diff-hg [|diff|pdiff]: Set the diff command of the current buffer
to mercurial and enable the update hook. By default it omits the
committed changes. Calling with pdiff lets it compare with prev.' \
    -shell-script-candidates %{ printf 'diff\npdiff\n' } \
    -params 0..1 diff-hg %{ evaluate-commands %sh{
    dirname_buffer="${kak_buffile%/*}"
    if ! expr "${dirname_buffer}" : '/.*' >/dev/null ||
            ! cd "${dirname_buffer}" 2>/dev/null; then
        echo "fail Invalid file path."
        exit
    fi
    if ! hg root >/dev/null 2>&1; then
        echo "fail Not in an hg work tree"
        exit
    fi
    case "$1" in
        ""|diff)
            echo "set-option buffer diff_command          'hg d -U0'"
            echo "set-option buffer diff_command_readable 'hg d'"
            ;;
        pdiff)
            echo "set-option buffer diff_command          'hg pd -U0'"
            echo "set-option buffer diff_command_readable 'hg pd'"
            ;;
        *)
            echo "fail Unknown diff type '$1'"
            ;;
    esac
    echo "set-option buffer diff_need_cd true"
    echo "diff-enable"
}}

define-command -docstring '
diff-file [<file>]: Set the diff compare source to <file>.' \
    -params 1 -file-completion diff-file %{ evaluate-commands %sh{
    if ! [ -r "$1" ]; then
        echo "fail File is not readable."
        exit
    fi
    printf "set-option buffer diff_command          'diff -U0 %s'\n" "$1"
    printf "set-option buffer diff_command_readable 'diff -u %s'\n" "$1"
    echo "set-option buffer diff_need_cd false"
    echo "diff-enable"
}}

declare-option -hidden str-list diff_enable_auto_detect_commands
define-command -docstring '
diff-enable-auto-detect [diff_commands...]: Enable auto diff command detection.
This command simply try enable all given commands until the first success.
If no command is given, diff-git and diff-hg will be tried.' \
    -params .. diff-enable-auto-detect %{
    evaluate-commands %sh{
        if [ $# = 0 ]; then
            set -- diff-git diff-hg
        fi
        printf 'set-option global diff_enable_auto_detect_commands %s\n' "$*"
    }
    try %{ hook -group diff-enable-auto-detect global BufCreate .* %{
        evaluate-commands %sh{
            set -- ${kak_opt_diff_enable_auto_detect_commands}
            printf 'try %%{'
            while [ $# -gt 1 ]; do
                printf ' %s } catch %%{' "$1"
                shift
            done
            printf ' %s } catch %%{}\n' "$1"
        }
    }}
}

define-command -docstring '
diff-disable-auto-detect: Disable auto diff command detection.' \
    -params 0 diff-disable-auto-detect %{
    remove-hooks global diff-enable-auto-detect
}
