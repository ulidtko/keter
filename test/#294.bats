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
    test -x $(which yq)
    test -x $(which bc)

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

    #-- compute our timeout for the ensureAlive "circuit-breaker": the one
    #-- which eventually abandons start attempts of dummy-broken.
    bound_us=`yq '.stanzas[0].ensure-alive-time-bound' $MYDIR/web-hello-cfg2.yml`
    bound_s=`bc -lq <<< "$bound_us / 1000000"`
    #-- for reliability, the test amplifies the timeout
    circuit_breaker=`bc -lq <<< "$bound_s * 3 + 3"`
    export circuit_breaker

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
        wait_until "test -r $KETER_LOG"
        wait_until "grep -q 'Started listening' $KETER_LOG"
    )
}

teardown () {
    read pid < $BATS_FILE_TMPDIR/keter.pid
    if test -e $BATS_FILE_TMPDIR/keter.keep; then
        echo "Keter PID $pid -- LEFT RUNNING"
    else
        kill $pid
    fi
}

@test "Reproduce issue #294" { # https://github.com/snoyberg/keter/issues/294
    LAST_OUTPUT=''
    #-- It's a suspected race-condition in keter, so we spin the scenario multiple times.
    for test_spin in $(seq 99000); do
        echo "===== Iteration $test_spin ====="
        echo -e "\x1b[1A\x1b[K     iteration $test_spin..." >&3

        #-- start the dummy
        cp -v $MYDIR/dummy.keter $KETER_DIR/incoming/dummy.keter
        wait_until "tail $KETER_LOG | grep -q 'Activating app dummy'" 0.1 3
        run curl --max-time 1 -Ss localhost:$PORT/
        LAST_OUTPUT=$output
        assert_line --partial "This is dummy app"

        #-- update the dummy with a version that's broken
        cp -v $MYDIR/dummy-broken.keter $KETER_DIR/incoming/dummy.keter
        wait_until "tail $KETER_LOG | grep -q 'ensureAlive failed'" 0.1 $circuit_breaker
        run curl --max-time 1 -Ss localhost:$PORT
        assert_equal "$output" "$LAST_OUTPUT"

        #-- update the dummy again, with working version, verify reload
        cp -v $MYDIR/dummy.keter $KETER_DIR/incoming/dummy.keter
        wait_until "tail $KETER_LOG | grep -q 'Reactivating app dummy'" 0.1 5
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

#-- this gets called before teardown(), on failures only
bats::on_failure () {
    echo "----- keter log tail -----"
    tail "$KETER_LOG"
    echo "----- dummy log tail -----"
    tail "$DUMMY_LOG"
    echo "----- end keter logs ------"

    # small cooldown, for the logs to flush fully
    sleep 0.3

    rescue_dir="$MYDIR/last-test-fail"
    rm -rf "$rescue_dir/*"
    mkdir -p "$rescue_dir"
    cp -r "$BATS_RUN_TMPDIR"/* "$rescue_dir"/
    echo "Test-run files rescued to $rescue_dir"
    # can also just pass --no-tempdir-cleanup

    # flag teardown() to leave it running. (in this state, where test failure occured)
    touch "$BATS_FILE_TMPDIR"/keter.keep
}

# tail -f /tmp/bats-run-*/test/1.out
# tail -f /tmp/bats-run-*/file/1/log/{keter,app-dummy}.log
