#!/bin/bash

# take a TSV output from get_geonamesFields.sh and run through it again
# keep everything that worked and retry everything that didn't
# user args: 1) input TSV from get_geonamesFields.sh, 2) path to get_geonamesFields.sh, 3) number of placename field in input TSV, 4) number of geonameid field in input TSV, 5) geonames username, 6) output file name
# example use: $0 geo.csv ../scripts-aiddata-qa/get_geonamesFields.sh 2 1 adecatur /tmp/out.csv

incsv=$1
get_geonamesFields=$2
placename_field=$3
geonameid_field=$4
user=$5
out=$6

tmp=$(mktemp)
tmp_out=$(mktemp)
echo "geonames_id" > $tmp
cat $incsv |\
awk -F'\t' "{if(\$${placename_field} ~ /^$/)print \$${geonameid_field}}" >> $tmp
missing_geo_id_regex=$( cat $tmp | sed 's:^:\\b:g;s:$:\\b:g;s:^:^:g' | tr '\n' '|' | sed 's:|$::g' )
grep -vE "$missing_geo_id_regex" $incsv > $tmp_out
sh $2 $tmp 1 $user | sed '1d' >> $tmp_out
mv $tmp_out $out
