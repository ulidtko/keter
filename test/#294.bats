#!/usr/bin/env bats
#--
#-- https://bats-core.readthedocs.io
#--

PORT=8000 #-- where test-keter listens on

setup () {
    #-- assert dependencies of the test
    test -x $(which python3)
    test -x $(which timeout)
    test -x $(which curl)

    #-- imports
    load bats-assert/load
    load bats-support/load
    load bats_fixture/common-setup

    #-- prepare the 2 mini-bundles for test
    MYDIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    ( cd $MYDIR
        mkdir -vp app-dummy/{app,config}
        install -m755 web-hello.py app-dummy/app/
        install -m644 web-hello-cfg1.yml app-dummy/config/keter.yaml
        tar czf dummy.keter -C app-dummy .
        install -m644 web-hello-cfg2.yml app-dummy/config/keter.yaml
        tar czf dummy-broken.keter -C app-dummy .
    )

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
    for test_spin in $(seq 1000); do
        echo "===== Iteration $test_spin ====="

        #-- start the dummy
        cp -v $MYDIR/dummy.keter $KETER_DIR/incoming/dummy.keter
        wait_until "tail $KETER_LOG | grep -q 'Activating app dummy'" 0.1 3
        run curl --max-time 1 -Ss localhost:8000/
        LAST_OUTPUT=$output
        assert_line --partial "This is dummy app"

        #-- update the dummy with a version that's broken
        cp -v $MYDIR/dummy-broken.keter $KETER_DIR/incoming/dummy.keter
        circuit_breaker=$((18 * 5 + 3))
        wait_until "tail $KETER_LOG | grep -q 'ensureAlive failed'" 1.0 $circuit_breaker
        run curl --max-time 1 -Ss localhost:$PORT
        assert_equal "$output" "$LAST_OUTPUT"

        #-- update the dummy again, with working version, verify reload
        cp -v $MYDIR/dummy.keter $KETER_DIR/incoming/dummy.keter
        wait_until "tail $KETER_LOG | grep -q 'Reactivating app dummy'" 0.1 3
        run curl --max-time 1 -Ss localhost:$PORT
        assert_line --partial "This is dummy app"
        assert_not_equal "$output" "$LAST_OUTPUT" #-- expecting different PID, port

        #-- stop the dummy, verifying that bundle termination works
        rm -v $KETER_DIR/incoming/dummy.keter
        wait_until "tail $KETER_LOG | grep -q 'Deactivating app dummy'" 0.1 3
        run curl --max-time 1 -Ss localhost:$PORT
        assert_line --partial "Welcome to Keter"
    done
}

bats::on_failure () {
    echo "----- keter log tail -----"
    tail $KETER_LOG
    echo "----- dummy log tail -----"
    tail $DUMMY_LOG
    echo "----- end keter logs ------"
}

# tail -f /tmp/bats-run-*/file/1/log/{keter,app-dummy}.log
