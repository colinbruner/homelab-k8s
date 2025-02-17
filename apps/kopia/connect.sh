#!/bin/bash

# lazy connect

(kubectl \
  port-forward \
  -n kopia \
  svc/kopia-service \
  8080:8080 &)

open http://localhost:8080
