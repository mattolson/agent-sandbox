
default:
  just --list

build:
  # cd images && sh build.sh
  mise exec -- python ./images/build.py