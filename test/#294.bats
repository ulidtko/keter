#!/usr/bin/env bats
#--
#-- https://bats-core.readthedocs.io
#--

setup () {
    MYDIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

    #-- assert dependencies of the test
    test -f $MYDIR/dummy.keter
    test -f $MYDIR/dummy-broken.keter
    test -x $(which nc)

    #-- imports
    load bats-assert/load
    load bats-support/load
    load bats_fixture/common-setup

    locate_keter_executable

    #-- start keter process, backgrounded
    ( cd "$BATS_FILE_TMPDIR"
        mkdir -p log incoming
        keter_config="
        root: $PWD
        rotate-logs: true
        listeners:
          - host: 127.0.0.1
            port: 8000
        "
        echo "$keter_config" > keter-config.yml
        #-- remember to close FD 3
        #-- https://bats-core.readthedocs.io/en/stable/writing-tests.html
        $KETER keter-config.yml 3>&- &
        echo $! > keter.pid
        export KETER_LOG=$BATS_FILE_TMPDIR/log/keter.log
        wait_until "grep -q 'Started listening' $KETER_LOG"
    )
}

teardown () {
    read pid < $BATS_FILE_TMPDIR/keter.pid
    kill $pid
}

@test "Reproduce issue #294" { # https://github.com/snoyberg/keter/issues/294
    tail $BATS_FILE_TMPDIR/log/keter.log
    fail TBD
}
