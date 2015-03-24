#!/bin/bash

# substitute values in a big TSV using values in a subset TSV
# at least one of the fields in the subset TSV must be a replacement field, like "new_precision_code"
# NB: field names **not** used as sub fields must be identical and not contain '?' and other troublesome characters
# user args: 1) TSV to search, 2) TSV with search text (with same field names used by TSV to search), 3) double quoted space separated list of this form subset_field_num:bigTSV_field_name, where the field subset_field_num replaces values in the field bigTSV_field_name
# print out the records in 1. that match fields in 2.
# example use: $0 complete.tsv my_subset.tsv "1:precision_code 2:geoname_id"
# in that example, values in the field complete.tsv precision_code are replaced with the values in the 1st field in my_subset.tsv and values in complete.tsv geonameid are replaced with values in the second field in my_subset.tsv

search=$1
pattern=$2
subfields=$3

function get_fieldinfo {
	# get header of search TSV numbered by nl, one field per line
	search_header=$( head -n 1 $search | tr '\t' '\n' | nl -ba )
	tmp_search_header=$(mktemp)
	echo "$search_header" > $tmp_search_header
	# get header of pattern TSV with regex to handle nl
	pattern_header_regex=$( head -n 1 $pattern | tr '\t' '\n' | sed 's:$:$:g;s:^:^[ \t]+[0-9]+[ \t]+:g' )
	# get header of pattern TSV
	pattern_header=$( head -n 1 $pattern | tr '\t' '\n' | nl -ba )
	tmp_pattern_header=$(mktemp)
	echo "$pattern_header" > $tmp_pattern_header
	# get the field numbers of the pattern TSV fields as they appear in search TSV, using the order found in pattern TSV
	search_fieldnums=$(
		echo "$pattern_header_regex" |\
		while read field
		do
			grep -Ef <( echo "$field" ) <( echo "$search_header" )
		done|\
		sed 's:^[ \t]\+\([0-9]\+\)[ \t]\+.*:\1:g'
	)
}

function get_subfields {
	# tmp file to hold field lists
	tmp_newReplaceOrig_fields_list=$(mktemp)
	newReplaceOrig_fields_list=$(
		echo "$subfields" |\
		tr ' ' '\n' |\
		while read subfield
		do
			replace_field_num=$(
				echo $subfield|\
				grep -oE "^[^:]*"
			)
			field_to_replace=$(
				echo $subfield|\
				grep -oE "[^:]*$"
			)
			field_to_replace_num=$( 
				grep -wEf <( echo "$field_to_replace" ) "$tmp_pattern_header" |\
				sed 's:^[ \t]\+\([0-9]\+\)[ \t]\+.*:\1:g'
			)
			field_to_replace_insearchTSV=$( 
				grep -wEf <( echo "$field_to_replace" ) "$tmp_search_header" |\
				sed 's:^[ \t]\+\([0-9]\+\)[ \t]\+.*:\1:g'
			)
			echo -e "$replace_field_num\t$field_to_replace_num\t$field_to_replace_insearchTSV"
		done 
	)
	echo "$newReplaceOrig_fields_list" > $tmp_newReplaceOrig_fields_list
} 

function get_replaceCols {
	replaceCols=$(
		cat $tmp_newReplaceOrig_fields_list|\
		mawk -F'\t' '{ print $1 }' |\
		tr '\n' ','|\
		sed 's:,$::g'
	)
}


function get_inputrecords {
	tmprecords=$(mktemp)
	tmpsearchcopy=$(mktemp)
	cat $pattern |\
	# get rid of header
	sed '1d'|\
	parallel --gnu '
		w_replacements=$( echo {} )
		subs=$(
			while read toreplace
			do
				patternnew=$(
					echo "$toreplace"|\
					mawk -F"\t" "{ print \$1 }"
				)
				patternold=$(
					echo "$toreplace"|\
					mawk -F"\t" "{ print \$2 }"
				)
				searchold=$(
					echo "$toreplace"|\
					mawk -F"\t" "{ print \$3 }"
				)
				# write the gsub statements to replace patternold with patternnew in field searchold
				mawk -F"\t" "{ print \"gsub(/^\"\$${patternold}\"$/,\\\"\"\$${patternnew}\"\\\",\$$searchold)\" }" <( echo "$w_replacements" )
			done < <( cat '$tmp_newReplaceOrig_fields_list' ) |\
			tr "\n" " "
		)
		# get rid of replace cols for purposes of finding subset records
		pattern_record=$( echo {} | cut --complement -f'${replaceCols}' )
		pattern_record=$(
			echo "$pattern_record"|\
			tr "\t" "\n"
		)
		# make a string for awk if statement using pattern record
		# looks like this: "$2 ~ /^VALUE$/"
		ifs=$(
			# escape forward slashes
			paste -d"\t" <( echo '$search_fieldnums' | sed "s:\s:\n:g" | sed "s:^:\$:g" ) <( echo "$pattern_record" | sed "s:/:\\\\/:g;s:^:\/^:g;s:$:$\/:g" )|\
			sed "s:\t: ~ :g"|\
			tr "\n" "\t"|\
			sed "s:\t\+: \&\& :g"|\
			sed "s:\s\+\&\&\s\+$::g"|\
			# escape parens
			sed "s:(:\\\(:g;s:):\\\):g" |\
			# escape pluses
			sed "s:+:\\\+:g" |\
			# escape questions marks
			sed "s:?:\\\?:g"
		)
		# this is the heart of the script - do if statements, then gsub on those
		# in order to also get records that did not need to be subbed, knock out each block of ifs results from original search TSV before catting subbed results onto that
		to_sub=$( mawk -F"\t" "{OFS=\"\t\";if( $ifs )print \$0 }" '$search' )
		echo "$to_sub" >> '$tmpsearchcopy'
		# now make subbed results
		search_record=$( 
			echo "$to_sub" |\
			mawk -F"\t" "{OFS=\"\t\";$subs;print \$0 }"
		)
		echo "$search_record" >> '$tmprecords'
	'
	# knock out the original records that got subbed from the whole file
	# write the subbed records to the end of the search TSV minus the original copy of records that got subbed
	grep -vFf $tmpsearchcopy $search | cat - $tmprecords
}

get_fieldinfo
get_subfields
get_replaceCols
get_inputrecords
