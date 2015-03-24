#!/bin/bash
# given an input TSV and a pair of fields to compare, first find which of those pairs are not unique, and for those find which fields keep them from being non-unique
# this can be used to identify records to change or remove
# allows for an arbitrary number of records for the non-unique pair and an arbitrary number of disagreeing fields
# user args: 1) input TSV with non-unique pairs, 2) position of field1 for not unique pairs (eg projid), 3) position of field2 for not unique pairs (eg geoid), 4) path to search_TSVbyTSV.sh, 5) path to find_notUniqPairs.sh, 6) path to transpose_tsv.sh
# example use: $0 locs.tsv 1 2 qa-tools/other/search_TSVbyTSV.sh qa-tools/cardinality/find_notUniqPairs.sh as-seen-online/transpose_tsv.sh

intsv=$1
field1=$2
field2=$3
path_to_searchTSVbyTSV=$4
path_to_findnotuniqpairs=$5
path_to_transposetsv=$6
# get field names of first and second field inputs
field1_name=$( head -n 1 $intsv | awk -F"\t" "{ print \$${field1}}" )
field2_name=$( head -n 1 $intsv | awk -F"\t" "{ print \$${field2}}" )
# this is needed for searchTSVbyTSV.sh
# print header - ought to use the original headers for field1 and field2 names
echo -e "$field1_name\t$field2_name\tdisagree_fields"
# run findnotuniqpairs
$path_to_findnotuniqpairs $intsv $field1 $field2 |\
# remove the counts fields
mawk -F'\t' '{OFS="\t";print $2,$3}' |\
# for each not uniq pair, find the fields that do not agree
parallel --gnu '
	notuniqpairs=$(mktemp)
	echo {} |\
	# add header
	sed "1s/^/'$field1_name'\t'$field2_name'\n/g" > $notuniqpairs
	notuniqrecords=$(mktemp)
	'$path_to_searchTSVbyTSV' '$intsv' $notuniqpairs > $notuniqrecords
	fields_not_agree=$( 
		'$path_to_transposetsv' <( cat $notuniqrecords | cut --complement -f1,2 ) |\
		awk -F"\t" "{ if( \$2 != \$3 ) print \$1 }" |\
 		tr "\n" "|" |\
 		sed "s:|$:\n:g" 
	)
	echo -e {}"\t$fields_not_agree"
'
