#!/bin/sh
# Прогон всех тестов GON+ на заглушках (без игры).
# Нужен Lua 5.4: команда "lua" (или путь в переменной LUA).
#   sh dev/tests/run_tests.sh            из корня репозитория
#   TEST_VERBOSE=1 sh dev/tests/run_tests.sh   с логом мода
LUA=${LUA:-lua}
HERE=$(cd "$(dirname "$0")" && pwd)
MAIN=${MAIN:-$(cd "$HERE/../.." && pwd)/GONPlus/Scripts/main.lua}
WORK=$(mktemp -d)
cd "$WORK" || exit 1
fail=0
for t in "$HERE"/t_*.lua; do
    "$LUA" "$t" "$MAIN" || fail=1
done
rm -rf "$WORK"
[ $fail -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $fail
