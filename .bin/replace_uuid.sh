#!/bin/sh

# sh replace_uuid.sh "id" "input.file"
while IFS= read -r line; do
  echo $line | sed "s/$1/`uuid`/g";
done < $2