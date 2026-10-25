#!/bin/sh
# Answer only for the local Forgejo. Any other host gets no credential.
proto=""
host=""
port=""
while IFS= read -r line; do
  [ -z "$line" ] && break
  case "$line" in
    protocol=*) proto=${line#protocol=} ;;
    host=*) host=${line#host=} ;;
    port=*) port=${line#port=} ;;
  esac
done
ok=0
if [ "$proto" = "http" ] && [ "$host" = "localhost:3300" ]; then
  ok=1
fi
if [ "$proto" = "http" ] && [ "$host" = "localhost" ] && [ "$port" = "3300" ]; then
  ok=1
fi
if [ "$ok" -ne 1 ]; then
  exit 0
fi
if [ -z "$OSF_GIT_USER" ] || [ -z "$OSF_FORGEJO_TOKEN" ]; then
  exit 0
fi
printf 'username=%s\n' "$OSF_GIT_USER"
printf 'password=%s\n' "$OSF_FORGEJO_TOKEN"
