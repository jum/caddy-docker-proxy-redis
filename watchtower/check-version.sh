#!/bin/sh
echo on docker.io:
regctl image digest --list containrrr/watchtower
echo running currently:
docker image inspect containrrr/watchtower  --format '{{json .RepoDigests}}' | jq .
