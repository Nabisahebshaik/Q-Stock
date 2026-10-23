#!/bin/bash
# Workaround for the CDH 5.13 QuickStart VM: Cloudera Manager writes 127.0.0.1
# into the NameNode's dfs.hosts include list, while /etc/hosts (regenerated at
# boot) maps quickstart.cloudera to the NAT address 10.0.2.15. The DataNode then
# fails to register ("host is not in the include-list"), HDFS has 0 live
# DataNodes and the NameNode stays in safe mode.
#
# This adds the current address to the runtime include file and refreshes the
# node list. CM regenerates the file when the NameNode restarts, so re-run after
# every VM boot:  ssh ... 'bash -s' < hadoop/vm_fix_datanode_include.sh
set -e
IP=$(getent hosts quickstart.cloudera | awk '{print $1}')
NN_DIR=$(sudo bash -c 'ls -td /var/run/cloudera-scm-agent/process/*-hdfs-NAMENODE | head -1')
ALLOW="$NN_DIR/dfs_hosts_allow.txt"
if ! sudo grep -qx "$IP" "$ALLOW"; then
  # CM writes the file without a trailing newline; add one before appending,
  # otherwise the entries merge into an unparseable host name.
  sudo sed -i -e '$a\' "$ALLOW"
  echo "$IP" | sudo tee -a "$ALLOW" > /dev/null
  echo "added $IP to $ALLOW"
fi
# The NameNode re-reads its own dfs.hosts file; the default client config is enough.
sudo -u hdfs hdfs dfsadmin -refreshNodes
for i in $(seq 1 36); do
  live=$(sudo -u hdfs hdfs dfsadmin -report 2>/dev/null | awk -F'[()]' '/Live datanodes/{print $2}')
  safe=$(sudo -u hdfs hdfs dfsadmin -safemode get 2>/dev/null)
  echo "live datanodes: ${live:-0}; $safe"
  if [ "${live:-0}" -ge 1 ] && echo "$safe" | grep -q OFF; then exit 0; fi
  sleep 5
done
echo "HDFS did not become healthy in 3 minutes" >&2
exit 1
