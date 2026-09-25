#!/usr/bin/env bats
# lib/verify.sh: runs through without a user manager (as bootstrap.sh runs it) and counts failures

setup() {
  load helpers
  setup_sandbox
  machine A
}

@test "verify runs to the end without a user session" {
  run dl A verify
  [[ $output == *"== Sync"* ]]
  [[ $output == *" FAIL, "* ]]
  [[ $output == *"no user manager"* ]]
}
