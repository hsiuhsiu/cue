#!/bin/bash
set -euo pipefail

usage() {
    printf 'Usage: %s --title|--body <release-notes.md>\n' "${0##*/}" >&2
    exit 2
}

[[ $# -eq 2 ]] || usage
mode="$1"
case "$mode" in
    --title|--body) ;;
    *) usage ;;
esac
source_file="$2"
[[ -f "$source_file" && -r "$source_file" ]] || {
    printf 'Error: Cannot read release notes: %s\n' "$source_file" >&2
    exit 1
}
# Prefix relative paths so awk cannot interpret a filename as an option or assignment.
case "$source_file" in
    /*) ;;
    *) source_file="./$source_file" ;;
esac

# Validate the complete document before either mode writes anything to stdout.
# Ignore CR only for parsing; the body output below preserves original line endings.
if ! metadata="$(awk '
    function fail(message) {
        print "Error: " message > "/dev/stderr"
        failed = 1
        exit 1
    }
    {
        line = $0
        sub(/\r$/, "", line)
        if (!heading) {
            if (line ~ /^[ \t]*$/) next
            if (line !~ /^# /)
                fail("Release notes must begin with a top-level heading: # Title")
            title = substr(line, 3)
            sub(/^[ \t]+/, "", title)
            sub(/[ \t]+$/, "", title)
            if (title == "") fail("The release title must not be empty.")
            heading = NR
            next
        }
        if (line ~ /^ ? ? ?#([ \t]|$)/)
            fail("Release notes must contain exactly one top-level heading; found another on line " NR ".")
        if (!body_start && line !~ /^[ \t]*$/) body_start = NR
    }
    END {
        if (failed) exit 1
        if (!heading) fail("Release notes must begin with a top-level heading: # Title")
        if (!body_start) fail("The release body must not be empty.")
        print body_start
        print title
    }
' "$source_file")"; then
    exit 1
fi

body_start="${metadata%%$'\n'*}"
title="${metadata#*$'\n'}"
if [[ "$mode" == --title ]]; then
    printf '%s\n' "$title"
    exit 0
fi

# Preserve the body verbatim, including CRLF, blank lines, and a missing final newline.
line_number=0
line=''
while IFS= read -r line; do
    line_number=$((line_number + 1))
    if [[ "$line_number" -ge "$body_start" ]]; then
        printf '%s\n' "$line"
    fi
done < "$source_file"
if [[ -n "$line" ]]; then
    line_number=$((line_number + 1))
    if [[ "$line_number" -ge "$body_start" ]]; then
        printf '%s' "$line"
    fi
fi
