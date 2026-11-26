#!/bin/bash
set -Eeuo pipefail
pg=/storage/postgres
mongo=/storage/mongo
install -d -m 700 -o postgres -g postgres "$pg"
install -d -m 700 -o mongod -g mongod "$mongo"
install -d -m 700 -o alignflow -g alignflow "$DATA_DIR"
install -d -m 775 -o postgres -g postgres /var/run/postgresql
if [[ ! -s "$pg/PG_VERSION" ]]; then
    gosu postgres initdb -D "$pg" --auth-local=peer --auth-host=scram-sha-256
fi
if [[ ! -f /storage/mongo-password ]]; then
    (umask 077; python -c 'import secrets; print(secrets.token_hex(32))' > /storage/mongo-password.tmp)
    mv /storage/mongo-password.tmp /storage/mongo-password
fi
gosu postgres postgres -D "$pg" -c listen_addresses='' &
pg_pid=$!
mongo_args=(--dbpath "$mongo" --bind_ip 127.0.0.1 --nounixsocket)
if [[ ! -f /storage/mongo-initialized ]]; then
    # Only the bootstrap process runs on this container-private port.
    gosu mongod mongod "${mongo_args[@]}" --port 27018 --noauth &
else
    gosu mongod mongod "${mongo_args[@]}" --auth &
fi
mongo_pid=$!
shutdown() {
    trap - EXIT TERM INT
    if [[ -n ${api_pid:-} ]]; then kill -TERM "$api_pid" || true; wait "$api_pid" || true; fi
    kill -TERM "$mongo_pid" || true
    kill -INT "$pg_pid" || true
    wait "$mongo_pid" || true
    wait "$pg_pid" || true
}
trap shutdown EXIT
trap 'exit 0' TERM INT
until gosu postgres pg_isready -q; do kill -0 "$pg_pid"; sleep 1; done
if [[ ! -f /storage/schema-v1 ]]; then
    if [[ -z $(gosu postgres psql -Atc "SELECT 1 FROM pg_roles WHERE rolname='alignflow'") ]]; then
        gosu postgres createuser alignflow
    fi
    if [[ -z $(gosu postgres psql -Atc "SELECT 1 FROM pg_database WHERE datname='alignflow'") ]]; then
        gosu postgres createdb --owner=alignflow alignflow
    fi
    gosu alignflow psql -X -1 -v ON_ERROR_STOP=1 -d alignflow -f setup.sql
    touch /storage/schema-v1
fi
export DATABASE_URL=postgresql:///alignflow
export MONGODB_URL="mongodb://alignflow:$(cat /storage/mongo-password)@127.0.0.1:27017/alignflow?authSource=admin"
if [[ ! -f /storage/mongo-initialized ]]; then
    python init_mongo.py
    kill -TERM "$mongo_pid"
    wait "$mongo_pid"
    touch /storage/mongo-initialized
    gosu mongod mongod "${mongo_args[@]}" --auth &
    mongo_pid=$!
fi
python -c 'import os; from pymongo import MongoClient; MongoClient(os.environ["MONGODB_URL"]).alignflow.command("ping")'
gosu alignflow uvicorn webapp:app --host 0.0.0.0 --port 8000 &
api_pid=$!
wait -n "$pg_pid" "$mongo_pid" "$api_pid"
exit 1
