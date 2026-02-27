# Build & Test Verification

After ANY changes to project code (.cs, .csproj, .sln files), always run `make build` and `make test` and verify both pass. If the build or tests fail, review and fix the proposed changes until both `make build` and `make test` succeed. Do not consider a task complete until the build is green and all tests pass.
