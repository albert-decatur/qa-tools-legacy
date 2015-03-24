#!/bin/bash

# join two TSVs on fields of your choice
# prereqs: 1) csvkit, 2) ssconvert from gnumeric for table2tsv function (seen csvkit's fail), 3) join type from csvkit (outer,left,right)
# below example joins a.tsv and b.tsv by concatenating fields 1 and 2 from each and using csvjoin on output
# example use: $0 a.tsv b.tsv "1 2" outer

a=$1
b=$2
joincols=$3
jointype=$4
# write joincols for awk
joincols_awk=$( echo "$joincols" | tr ' ' '\n' | sed 's:^:$:g' | tr '\n' ' ' | sed 's: \+::g' )
# pick up num cols in a to clean up join fields from left or right join
function numcols { cat $1 | mawk -F'\t' '{print NF}' | head -n 1;}
a_numcols=$( numcols $a )
function mk_joinfield { mawk -F'\t' "{OFS=\"\t\";print $joincols_awk,\$0}" $1;}
a=$( mk_joinfield $a )
b=$( mk_joinfield $b )
joinedcsv=$( csvjoin --${jointype} -t -c1,1 <( echo "$a" ) <( echo "$b" ) )
function table2tsv { ssconvert --export-type Gnumeric_stf:stf_assistant -O 'separator="	"' fd://0 fd://1; }


if [[ "$jointype" == "outer" ]]; then
	# do not remove any fields
	joinedtsv=$( echo "$joinedcsv" | table2tsv )
elif [[ "$jointype" == "left" ]]; then
	# remove right join fields
	cat_id_col=1
	dup_id_col=$( expr $a_numcols + 2 )
	right_cols_to_rm=$(
	for col in $joincols
	do
		# get position of join cols to remove
		expr $col + 2 + $a_numcols
	done |\
	tr '\n' ','|\
	sed 's:,$::g'
	)
	joinedtsv=$( echo "$joinedcsv" | table2tsv | cut --complement -f${cat_id_col},${dup_id_col},${right_cols_to_rm} )
elif [[ "$jointype" == "right" ]]; then
	dup_id_col=1
	cat_id_col=$( expr $a_numcols + 2 )
	left_cols_to_rm=$(
	for col in $joincols
	do
		# get position of join cols to remove
		expr $col + 1
	done |\
	tr '\n' ','|\
	sed 's:,$::g'
	)
	joinedtsv=$( echo "$joinedcsv" | table2tsv | cut --complement -f${cat_id_col},${dup_id_col},${left_cols_to_rm} )
else
	echo "Join type selected was neither \"outer\", nor \"left\", nor \"right\"."
	exit 1
fi
echo "$joinedtsv"
