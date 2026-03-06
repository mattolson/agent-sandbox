#!/usr/bin/env bats

setup() {
	load test_helper

	mkdir -p "$BATS_TEST_TMPDIR/lib"
	export AGB_LIBDIR="$BATS_TEST_TMPDIR/lib"

	cat > "$AGB_LIBDIR/run-compose" <<'SCRIPT'
#!/usr/bin/env bash
echo "run-compose $*"
SCRIPT
	chmod +x "$AGB_LIBDIR/run-compose"
}

@test "compose module forwards arbitrary docker compose commands" {
	run "$AGB_LIBEXECDIR/compose/_" ps
	assert_success
	assert_output "run-compose ps"
}

@test "compose default command forwards args to docker compose" {
	run "$AGB_LIBEXECDIR/compose/compose" ps
	assert_success
	assert_output "run-compose ps"
}

@test "up command forwards args to docker compose up" {
	run "$AGB_LIBEXECDIR/up/up" -d
	assert_success
	assert_output "run-compose up -d"
}

@test "up catch-all forwards positional args to docker compose up" {
	run "$AGB_LIBEXECDIR/up/_" myservice
	assert_success
	assert_output "run-compose up myservice"
}

@test "down command forwards args to docker compose down" {
	run "$AGB_LIBEXECDIR/down/down" --volumes
	assert_success
	assert_output "run-compose down --volumes"
}

@test "down catch-all forwards positional args to docker compose down" {
	run "$AGB_LIBEXECDIR/down/_" myservice
	assert_success
	assert_output "run-compose down myservice"
}

@test "logs command forwards args to docker compose logs" {
	run "$AGB_LIBEXECDIR/logs/logs" --tail 10
	assert_success
	assert_output "run-compose logs --tail 10"
}

@test "logs catch-all forwards positional args to docker compose logs" {
	run "$AGB_LIBEXECDIR/logs/_" myservice
	assert_success
	assert_output "run-compose logs myservice"
}
