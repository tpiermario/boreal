#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/audit
cc_args=(-std=c11 -Wall -Wextra -Werror -I Sources/CSMC/include)
xcrun clang "${cc_args[@]}" Tests/helper_test.c Sources/CSMC/policy.c -framework IOKit -framework CoreFoundation -o .build/audit/helper-test
.build/audit/helper-test
xcrun clang "${cc_args[@]}" Tests/transport_test.c Sources/CSMC/smc.c Sources/CSMC/policy.c -framework IOKit -o .build/audit/transport-test
.build/audit/transport-test
xcrun clang "${cc_args[@]}" Tests/transport_timing_test.c Sources/CSMC/policy.c -framework IOKit -o .build/audit/transport-timing-test
.build/audit/transport-timing-test
xcrun clang "${cc_args[@]}" -c Sources/CSMC/smc.c -o .build/audit/smc.o
xcrun clang "${cc_args[@]}" -c Sources/CSMC/policy.c -o .build/audit/policy.o
cat > .build/audit/module.modulemap <<'MAP'
module CSMC { header "smc.h" export * }
MAP
cp Sources/CSMC/include/smc.h .build/audit/smc.h
xcrun swiftc -parse-as-library -I .build/audit Sources/Boreal/Models.swift Sources/Boreal/AppModel.swift Sources/Boreal/NativeTray.swift Tests/Audit.swift .build/audit/smc.o .build/audit/policy.o -framework IOKit -o .build/audit/Audit
.build/audit/Audit
