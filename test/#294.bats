#--
#-- https://bats-core.readthedocs.io
#--

setup () {
    MYDIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

    #-- assert dependencies of the test
    test -f $MYDIR/dummy.keter
    test -f $MYDIR/dummy-broken.keter
    test -x $(which nc)

    load bats-assert/load
    load bats-support/load
    load bats_fixture/common-setup
    _locate_keter_executable
}

teardown () {
    : TBD
}

@test "Reproduce issue #294" { # https://github.com/snoyberg/keter/issues/294
    fail TBD
}
