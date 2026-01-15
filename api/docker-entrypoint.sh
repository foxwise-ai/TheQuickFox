#!/bin/sh

# migrate first
/app/bin/migrate

# if sucessful, start the server

if [ $? -eq 0 ]; then
    echo "Migration successful"
else
    echo "Migration failed"
    exit 1
fi

exec /app/bin/server "@"
