#!/bin/bash

# ensure environment variables are loaded
if [ -z "$(which cargo)" ]; then
	>&2 echo "sourcing from bashrc to ensure environment variables are loaded"
	source ~/.bashrc
fi

# enter script directory
cd "$(dirname "$0")" || exit $?

# handle action type
case "$1" in
	# NOTE: for some reason, it gets set to "" rather than "build" when
	# doing a build.
	build|"")
		>&2 echo "Executing build phase for librespot rust"
		../rust/build.sh || exit $?
		;;

	clean)
		>&2 echo "Executing clean phase for librespot rust"
		../rust/clean.sh || exit $?
		;;
	*)
		>&2 echo "Unknown action $1"
		exit 1
		;;
esac
