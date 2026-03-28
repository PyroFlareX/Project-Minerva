#!/bin/bash
# Fix ownership of cargo cache volumes (named volumes mount as root)
chown -R dev:dev /usr/local/cargo/registry /usr/local/cargo/git 2>/dev/null || true
exec gosu dev "$@"