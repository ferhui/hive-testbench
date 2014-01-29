#!/bin/bash

function usage {
	echo "Usage: tpcds-setup.sh scale [temp directory] [partitioned|unpartitioned]"
	exit 1
}

if [ ! -f tpcds-gen/target/tpcds-gen-1.0-SNAPSHOT.jar ]; then
	echo "Build the data generator with build.sh first"
	exit 1
fi
which hive > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Script must be run where Hive is installed"
	exit 1
fi

# Tables in the TPC-DS schema.
LIST="date_dim time_dim item customer customer_demographics household_demographics customer_address store promotion warehouse ship_mode reason income_band call_center web_page catalog_page web_site"
FACTS="web_returns store_sales store_returns web_sales catalog_sales catalog_returns inventory"

# Get the parameters.
SCALE=$1
DIR=$2

# Ensure arguments exist.
if [ X"$SCALE" = "X" ]; then
	usage
fi
if [ X"$DIR" = "X" ]; then
	DIR=/tmp/tpcds-generate
fi

# Sanity checking.
if [ $SCALE -eq 1 ]; then
	echo "Scale factor must be greater than 1"
	exit 1
fi

BUCKETS=13
RETURN_BUCKETS=1
SPLIT=16

set -x
set -e

hadoop dfs -mkdir -p ${DIR}
hadoop dfs -ls ${DIR}/${SCALE} || (cd tpcds-gen; hadoop jar target/*.jar -d ${DIR}/${SCALE}/ -s ${SCALE})
hadoop dfs -ls ${DIR}/${SCALE}

# Generate the text/flat tables. These will be later be converted to ORCFile.
# hive -i settings/load-flat.sql -f ddl/text/alltables.sql -d DB=tpcds_text_${SCALE} -d LOCATION=${DIR}/${SCALE}

# Populate the smaller tables.
#for t in ${LIST}
#do
#	hive -i settings/load-partitioned.sql -f ddl/bin_partitioned/${t}.sql \
#	    -d DB=tpcds_bin_partitioned_orc_${SCALE} \
#	    -d SOURCE=tpcds_text_${SCALE} -d BUCKETS=${BUCKETS} \
#	    -d RETURN_BUCKETS=${RETURN_BUCKETS} -d FILE="${file}" \
#	    -d SERDE=org.apache.hadoop.hive.ql.io.orc.OrcSerde -d SPLIT=${SPLIT}
#done

# Create the partitioned tables.
for t in ${FACTS}
do
	hive -i settings/load-partitioned.sql -f ddl/bin_partitioned/${t}.sql \
	    -d DB=tpcds_bin_partitioned_orc_${SCALE} \
	    -d SOURCE=tpcds_text_${SCALE} -d BUCKETS=${BUCKETS} \
	    -d RETURN_BUCKETS=${RETURN_BUCKETS} -d FILE="${file}" \
	    -d SERDE=org.apache.hadoop.hive.ql.io.orc.OrcSerde -d SPLIT=${SPLIT}
done

# Populate the partitioned tables.
for t in ${FACTS}
do
	hadoop jar tpcds-parts-1.0-SNAPSHOT.jar -t ${t}
	    -i ${DIR}/${t}/
	    -o /apps/hive/warehouse/tpcds_bin_partitioned_orc_${SCALE}.db/${t}
	hive -e "msck repair table ${t}"
done
