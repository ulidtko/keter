#!/usr/bin/env bats
#--
#-- https://bats-core.readthedocs.io
#--

PORT=8000 #-- where test-keter listens on

setup () {
    MYDIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

    #-- assert dependencies of the test
    test -f $MYDIR/dummy.keter
    test -f $MYDIR/dummy-broken.keter
    test -x $(which nc)
    test -x $(which timeout)
    test -x $(which curl)

    #-- imports
    load bats-assert/load
    load bats-support/load
    load bats_fixture/common-setup

    locate_keter_executable

    #-- start keter process, backgrounded
    export KETER_DIR=$BATS_FILE_TMPDIR
    export KETER_LOG=$KETER_DIR/log/keter.log
    export DUMMY_LOG=$KETER_DIR/log/app-dummy.log
    ( cd "$KETER_DIR"
        mkdir -p log incoming
        keter_config="
        root: $PWD
        rotate-logs: true
        listeners:
          - host: 127.0.0.1
            port: $PORT
        "
        echo "$keter_config" > keter-config.yml
        #-- remember to close FD 3
        #-- https://bats-core.readthedocs.io/en/stable/writing-tests.html
        $KETER keter-config.yml 3>&- &
        echo $! > keter.pid
        wait_until "grep -q 'Started listening' $KETER_LOG"
    )
}

teardown () {
    read pid < $BATS_FILE_TMPDIR/keter.pid
    kill $pid
}

@test "Reproduce issue #294" { # https://github.com/snoyberg/keter/issues/294
    LAST_OUTPUT=''
    #-- It's a suspected race-condition in keter, so we spin the scenario multiple times.
    for test_spin in $(seq 1); do
        echo "===== Iteration $test_spin ====="

        #-- start the dummy
        cp -v $MYDIR/dummy.keter $KETER_DIR/incoming/dummy.keter
        wait_until "grep -q 'Activating app dummy' $KETER_LOG" 0.1
        run curl --max-time 1 -Ss localhost:8000/
        LAST_OUTPUT=$output
        assert_line --partial "this is dummy app"

        #-- update the dummy with a version that's broken
        cp -v $MYDIR/dummy-broken.keter $KETER_DIR/incoming/dummy.keter
        circuit_breaker=$((18 * 5 + 3))
        wait_until "tail $KETER_LOG | grep -q 'ensureAlive failed'" 1.0 $circuitbreaker
        run curl --max-time 1 -Ss localhost:$PORT
        assert_equal "$output" "$LAST_OUTPUT"

        #-- update the dummy again, with working version, verify reload
        cp -v $MYDIR/dummy.keter $KETER_DIR/incoming/dummy.keter
        sleep 5
        fail "TODO"
    done
    fail TBD
}

bats::on_failure () {
    echo "----- keter log tail -----"
    tail $KETER_LOG
    echo "----- dummy log tail -----"
    tail $DUMMY_LOG
}

# tail -f /tmp/bats-run-*/file/1/log/{keter,app-dummy}.log
