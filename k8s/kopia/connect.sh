#!/bin/bash

# lazy connect

# Assume in correct namespace
(kubectl \
  port-forward \
  svc/backup \
  8080:8080 &)

open http://localhost:8080
