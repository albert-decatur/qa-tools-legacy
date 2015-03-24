#!/bin/bash

# print entire record from the search TSV when the given fields match the pattern TSV
# essentially a multi column literal grep - number of columns and column order is arbitrary
# NB: field names must be identical and not contain '?' and other troublesome characters
# user args: 1) TSV to search, 2) TSV with search text (with same field names used by TSV to search)
# print out the records in 1. that match fields in 2.
# example use: $0 complete.tsv my_subset.tsv

search=$1
pattern=$2
# get header of pattern TSV with regex to handle nl
pattern_header=$( head -n 1 $pattern | tr '\t' '\n' | sed 's:$:$:g;s:^:^[ \t]+[0-9]+[ \t]+:g' )
# get header of search TSV numbered by nl, one field per line
search_header=$( head -n 1 $search | tr '\t' '\n' | nl )
# get the field numbers of the pattern TSV fields as they appear in search TSV, using the order found in pattern TSV
search_fieldnums=$(
	echo "$pattern_header" |\
	while read field
	do
		grep -Ef <( echo "$field" ) <( echo "$search_header" )
	done|\
	sed 's:^[ \t]\+\([0-9]\+\)[ \t]\+.*:\1:g'
)

# print entire search TSV header
head -n 1 $search
cat $pattern |\
sed '1d'|\
parallel --gnu '
	pattern_record=$( echo {} )
	pattern_record=$(
		echo "$pattern_record"|\
		tr "\t" "\n"
	)
	# make a string for awk if statement using pattern record
	# looks like this: "$2 ~ /^VALUE$/"
	awkstring_patternvalues=$(
		# escape forward slashes
		paste -d"\t" <( echo '$search_fieldnums' | sed "s:\s:\n:g" | sed "s:^:\$:g" ) <( echo "$pattern_record" | sed "s:/:\\\\/:g;s:^:\/^:g;s:$:$\/:g" )|\
		sed "s:\t: ~ :g"|\
		tr "\n" "\t"|\
		sed "s:\t\+: \&\& :g"|\
		sed "s:\s\+\&\&\s\+$::g"|\
		# escape parens
		sed "s:(:\\\(:g;s:):\\\):g"
	)
	search_record=$( mawk -F"\t" "{OFS=\"\t\";if( $awkstring_patternvalues )print \$0 }" '$search' )
	echo "$search_record"
'
