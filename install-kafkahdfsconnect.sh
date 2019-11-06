#!/usr/bin/env bash

# Script downloads Kafka HDFS Connect, untars and copies to the required location 

# Import the helper method module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh

# In case Kafka HDFS Connector is installed, exit.
if [ -e /usr/local/share/kafka-connect ]; then
    echo "Kafka HDFS Connector folder already exists, exiting ..."
    exit 0
fi

# Download Kafka Connect binary to temporary location.
echo "Download Kafka HDFS Connect binaries to temporary location..."
download_file https://hdinsightscripts.blob.core.windows.net/scripts/confluentinc-kafka-connect-hdfs-5.2.1.tgz /tmp/confluentinc-kafka-connect-hdfs-5.2.1.tgz

# makedir target location for Kafka Connect
echo "Create /usr/local/share/kafka-connect/ folder..."
mkdir /usr/local/share/kafka-connect

# Untar the binary and move it to proper location.
echo "Untar Kafka Connect binary files from tmp -> /user/local/share/kafka-connect/..."
untar_file /tmp/confluentinc-kafka-connect-hdfs-5.2.1.tgz /usr/local/share/kafka-connect/

# Remove the temporary binary file downloaded.
echo "Remove the temporary .tgz file downloaded"
rm -f /tmp/confluentinc-kafka-connect-hdfs-5.2.1.tgz

echo "Kafka Connect installation completed!"