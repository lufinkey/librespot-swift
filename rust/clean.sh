#!/bin/bash

cd "$(dirname "$0")" || exit $?
rm -rf lib generated target || exit $?
