#!/bin/sh

test -n "$1$2" || exit 1

echo >> $2
echo "# From $1" >> $2
cat $1 < /dev/null >> $2
