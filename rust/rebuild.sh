#!/bin/bash

cd "$(dirname "$0")" || exit $?
./clean.sh || exit $?
./build.sh || exit $?
