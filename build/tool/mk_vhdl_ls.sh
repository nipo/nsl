#!/bin/sh

echo '[libraries]'
for i in $(cd lib ; ls -1) ; do
	test -d lib/$i || continue
	find lib/$i -name \*.vhd | grep -q . > /dev/null || continue
	echo "$i.files = ['lib/$i/**/*.vhd']"
done

