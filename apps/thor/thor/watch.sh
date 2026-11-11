#!/bin/sh
# Rebuilds and relaunches the thor app in the current folder each time a .odin file changes. The
# window opens where it last was. Run it from the app's folder: ./thor/watch.sh. Ctrl-C stops it.
set -u
out=./.thor-watch
stamp=$(mktemp)
pid=""
trap 'kill $pid 2>/dev/null; rm -f "$stamp" "$out"; exit 0' INT TERM

while :; do
	touch "$stamp"
	echo "watch: building"
	if odin build . -out:"$out"; then
		# The old window stays up while the build runs, and goes once the new one is ready to start.
		[ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
		THOR_KEEP_FRAME=1 "$out" &
		pid=$!
	fi
	# -L follows a thor folder that is a link, so a change to thor rebuilds too.
	while [ -z "$(find -L . -name '*.odin' -newer "$stamp" -print -quit)" ]; do sleep 0.2; done
done
