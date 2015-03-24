#!/bin/bash

# use geoname ID field in a TSV to retrieve records from geonames SQLite db
# build the SQLite db with https://github.com/albert-decatur/geonames2sqlite
# user args: 1) input TSV with just project id, geoname id, and precision code in that order, 2) number of geoname id field in input TSV, 3) geonames sqlite db
# example use: $0 tk.tsv 2 allCountries_2014-09-29.sqlite

# make function to convert arbitrary table to TSV
# prereq: Gnumeric.  don't trust csvkit's csvformat yet
# NB: assumes first three fields of input TSV we join to are project_id,geoname_id,precision_code
# this is a terrible thing to do
function table2tsv { ssconvert --export-type Gnumeric_stf:stf_assistant -O 'separator="	"' fd://0 fd://1; }

intsv=$1
geoid=$2
db=$3
sqltmp=$(mktemp)
# write the start of a single SQL transaction to tmp file
echo -e "BEGIN;\n.separator '\t'" > $sqltmp
# get list of unique goename IDs
geoids=$( 
	mawk -F'\t' "{print \$${geoid}}" $intsv |\
	sed '1d' |\
	sort |\
	uniq 
)
# write SQL select statements to get whole records given geoname IDs
echo "$geoids" |\
parallel --gnu "
cat <<EOF
SELECT
    a.geonameid AS geoname_id,
    a.name AS place_name,
    a.latitude,
    a.longitude,
    f.code AS location_type_code,
    f.name AS location_type_name,
    CASE 
        WHEN f.code = 'ADM1' THEN group_concat( a.countrycode || '|' || adm1.adm1_code ) 
        WHEN f.code = 'ADM2' THEN group_concat( a.countrycode || '|' || adm1.adm1_code || '|' || adm2.adm2_code )
        ELSE group_concat( a.countrycode || '|' || a.admin1code || '|' || a.admin2code || '|' || a.admin3code || '|' || a.admin4code )
    END AS geoname_adm_code,
    CASE
        WHEN f.code = 'ADM1' THEN group_concat( cc.Country || '|' || adm1.adm1_name )
        WHEN f.code = 'ADM2' THEN group_concat( cc.Country || '|' || adm1.adm1_name || '|' || adm2.adm2_name ) 
        ELSE 
	CASE
		WHEN adm1.adm1_name IS NULL AND adm2.adm2_name IS NULL THEN cc.Country
		WHEN adm1.adm1_name IS NOT NULL AND adm2.adm2_name IS NULL THEN group_concat( cc.Country || '|' || adm1.adm1_name )
		WHEN adm1.adm1_name IS NOT NULL AND adm2.adm2_name IS NOT NULL THEN group_concat( cc.Country || '|' || adm1.adm1_name || '|' || adm2.adm2_name )
		ELSE cc.Country
	END
    END AS geonames_adm_name,
    modificationdate || 'T00:00:00+0000' AS geonames_retrieval_time
    FROM
        allCountries AS a
    LEFT JOIN featurecodes_en AS f 
        ON a.featurecode = f.code
    LEFT JOIN admin1codesascii AS adm1 
        ON adm1.adm0_code = a.countrycode AND adm1.adm1_code = a.admin1code
    LEFT JOIN admin2codes AS adm2 
        ON adm2.adm0_code = a.countrycode AND adm2.adm1_code = a.admin1code AND adm2.adm2_code = a.admin2code
    LEFT JOIN countryInfo AS cc 
        ON cc.ISO = a.countrycode
    WHERE
        a.geonameid =  '{}'
    GROUP BY a.geonameid
;
EOF
" >> $sqltmp
# write the end of a single SQL transaction to tmp file
echo "COMMIT;" >> $sqltmp
# make tmp file to write SQLite query results to before joining to toolkit's project_id, geoname_id, precision_code
geotmp=$(mktemp)
# the desired output header for geonames SQLite query.  this is cheating!
geoheader=$( echo -e "geoname_id\tplace_name\tlatitude\tlongitude\tlocation_type_code\tlocation_type_name\tgeoname_adm_code\tgeonames_adm_name\tgeonames_retrieval_time" )
# write our header to geotmp
echo "$geoheader" > $geotmp
# run the SQL on geonames sqlite db
cat $sqltmp | sqlite3 $db |\
# clean up duplicate / trailing pipes in adm codes and names
sed 's:|\+:|:g;s:|\t:\t:g' >> $geotmp
# output header - assumes first three fields of input TSV we join to are project_id,geoname_id,precision_code
output_header=$( echo "$geoheader" | sed 's:^geoname_id\t::g;s:^:project_id\tgeoname_id\tprecision_code\t:g' )
# make output tmp file
outtmp=$(mktemp)
# add output header to outtmp
echo "$output_header" > $outtmp
# join geonames SQLite query results back to toolkit export
csvjoin --outer -t -c${geoid},1 $intsv $geotmp |\
table2tsv |\
# remove duplicate geoname_id field, change header to be locations.tsv style
# NB: requires that input literally uses this field order: project_id, geoname_id, precision_code
# brittle!
cut --complement -f4 |\
# temporarily remove header in order to sort such that geoname_ids that were not found appear at top
sed '1d' |\
sort -k4,4 >> $outtmp
cat $outtmp
#clean up tmp
rm $sqltmp
rm $geotmp
rm $outtmp
