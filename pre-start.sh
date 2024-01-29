#!/bin/sh
# delay for database startup using wait-for-it for up to 5 minutes
wait-for-it.sh -h database -p 3306 -t 300
# call the original wordpress entrypoint script with any args
exec start.sh "$@"
