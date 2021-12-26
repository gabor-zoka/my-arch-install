# "set -e; . bash-header2.sh" is the boilerplate start, hence I have to turn it 
# off.
set +e -E -u -o pipefail

if ! tail -n1 "$0" | grep -Pq '^\s*onexit\b'; then
    echo "ERROR: onexit is missing at the last line" >&2
    exit 1
fi

if grep -PHn '(^|;)\s*exit(?!\()\b' "$0" >&2; then
    echo "ERROR: Use onexit instead of exit. See line above" >&2
    exit 1
fi

tmp_dir="$(mktemp -d -t "$(basename "$0").XXXXXX")"
td="$tmp_dir" # Shorter alias

if [[ $(printf %q "$td") != $td ]]; then
    # I do not want to quote tmp dir as I use it often.

    echo "ERROR: $td tmp dir would require quoting" >&2
    exit 1
fi

_clean() {
    if [[ -e $td/clean$BASH_SUBSHELL ]]; then
        tac $td/clean$BASH_SUBSHELL >$td/tmp$BASH_SUBSHELL
        . $td/tmp$BASH_SUBSHELL
    fi

    if [[ $BASH_SUBSHELL -eq 0 ]]; then
        rm -rf $td
    elif [[ $1 -ne 0 ]]; then
        # Save the exit code for the parent
        echo onexit $1 >$td/child_exit
        # Tell the parent that the subprocess failed and it has to clean up and 
        # die.
        kill -USR1 $$
    fi
}

onexit() {
    local exit=${1:-$?}
    _clean $exit
    exit $exit
}

trap onexit 1 2 3 15 ERR
trap ". $td/child_exit" USR1

push_clean() {
    printf '%q ' "$@" >>$td/clean$BASH_SUBSHELL
    echo              >>$td/clean$BASH_SUBSHELL
}

flush_clean() {
    head -n -${1:-1} $td/clean$BASH_SUBSHELL >$td/tmp$BASH_SUBSHELL
    mv $td/tmp$BASH_SUBSHELL $td/clean$BASH_SUBSHELL
}

pop_clean() {
    tail -n ${1:-1} $td/clean$BASH_SUBSHELL | tac >$td/tmp$BASH_SUBSHELL
    . $td/tmp$BASH_SUBSHELL
    flush_clean ${1:-1}
}

join_by() {
    local IFS="$1"; shift
    echo "$*"
}
