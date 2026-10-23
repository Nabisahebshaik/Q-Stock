#!/bin/bash
# Bring the CDH 5.13 QuickStart VM to a state Q-Stock needs: HDFS with a live
# DataNode, YARN, ZooKeeper, Hive Metastore and HiveServer2.
# Run after every VM boot, from the project root on the host:
#   ssh <opts> cloudera@127.0.0.1 'bash -s' < hadoop/vm_start_services.sh
set -e
CM="http://localhost:7180/api/v18"
SVC="$CM/clusters/Cloudera%20QuickStart/services"
api() { curl -s -u admin:admin "$@"; }
json() { python -c "import json,sys; d=json.load(sys.stdin); $1"; }

wait_cmd() {
  for i in $(seq 1 120); do
    st=$(api "$CM/commands/$1" | json 'print("%s|%s" % (d["active"], d.get("success")))')
    [ "${st%%|*}" = "False" ] && { echo "  command $1 success=${st##*|}"; return 0; }
    sleep 5
  done
  return 1
}

echo "== waiting for Cloudera Manager API"
for i in $(seq 1 60); do api "$CM/../version" >/dev/null 2>&1 && break; sleep 5; done

# The 8 GB VM hung (guest unresponsive, ACPI ignored) with CM monitoring roles +
# HDFS + YARN + ZooKeeper + Hive all running. Q-Stock does not need CM's
# monitoring dashboards, so stop the Cloudera Management Service to free memory.
if [ "${KEEP_CM_MGMT:-0}" != "1" ]; then
  mstate=$(api "$CM/cm/service" | json 'print(d["serviceState"])')
  if [ "$mstate" = "STARTED" ] || [ "$mstate" = "STARTING" ]; then
    echo "== stopping Cloudera Management Service (set KEEP_CM_MGMT=1 to keep it)"
    wait_cmd "$(api -X POST "$CM/cm/service/commands/stop" | json 'print(d["id"])')"
  fi
fi

echo "== HDFS / YARN"
for s in hdfs yarn zookeeper hive; do
  state=$(api "$SVC/$s" | json 'print(d["serviceState"])')
  echo "$s: $state"
done

# HDFS: DataNode include-list fix (see vm_fix_datanode_include.sh for why).
IP=$(getent hosts quickstart.cloudera | awk '{print $1}')
NN_DIR=$(sudo bash -c 'ls -td /var/run/cloudera-scm-agent/process/*-hdfs-NAMENODE | head -1')
ALLOW="$NN_DIR/dfs_hosts_allow.txt"
if ! sudo grep -qx "$IP" "$ALLOW"; then
  sudo sed -i -e '$a\' "$ALLOW"
  echo "$IP" | sudo tee -a "$ALLOW" > /dev/null
  sudo -u hdfs hdfs dfsadmin -refreshNodes 2>/dev/null
fi
for i in $(seq 1 36); do
  sudo -u hdfs hdfs dfsadmin -safemode get 2>/dev/null | grep -q OFF && break; sleep 5
done
sudo -u hdfs hdfs dfsadmin -safemode get 2>/dev/null

for s in zookeeper hive; do
  state=$(api "$SVC/$s" | json 'print(d["serviceState"])')
  if [ "$state" != "STARTED" ]; then
    echo "== starting $s"
    wait_cmd "$(api -X POST "$SVC/$s/commands/start" | json 'print(d["id"])')"
  fi
done

echo "== waiting for metastore (9083)"
for i in $(seq 1 60); do sudo netstat -tln | grep -q ":9083 " && break; sleep 5; done
# HiveServer2 gives up if it starts before the metastore; restart it if needed.
sleep 20
if ! sudo netstat -tln | grep -q ":10000 "; then
  echo "== restarting HiveServer2"
  wait_cmd "$(api -X POST -H 'Content-Type: application/json' -d '{"items":["hive-HIVESERVER2"]}' \
    "$SVC/hive/roleCommands/restart" | json 'print(d["items"][0]["id"])')"
  for i in $(seq 1 36); do sudo netstat -tln | grep -q ":10000 " && break; sleep 5; done
fi
sudo netstat -tln | grep -qE ":10000 " && echo "HiveServer2 listening on 10000" || { echo "HiveServer2 not up" >&2; exit 1; }
