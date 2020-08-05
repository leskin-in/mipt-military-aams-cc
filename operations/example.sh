#!/usr/bin/env bash

psql postgres -e -f 1_user.sql
PGPASSWORD=petrov psql postgres -h localhost -U petrov -e -f 2_self.sql
PGPASSWORD=radar psql postgres -h localhost -U radar -f 3_fr24data.sql
