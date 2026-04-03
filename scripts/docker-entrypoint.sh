#!/bin/sh
set -e

# Fix volume ownership — Railway mounts volumes as root
chown -R node:node /paperclip

exec gosu node "$@"
