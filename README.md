# qa-tools
### "_legacy edition_"

```bash
    __                                        ___ __  _           
   / /__  ____ _____ ________  __   ___  ____/ (_) /_(_)___  ____ 
  / / _ \/ __ `/ __ `/ ___/ / / /  / _ \/ __  / / __/ / __ \/ __ \
 / /  __/ /_/ / /_/ / /__/ /_/ /  /  __/ /_/ / / /_/ / /_/ / / / /
/_/\___/\__, /\__,_/\___/\__, /   \___/\__,_/_/\__/_/\____/_/ /_/ 
       /____/           /____/                                    
```                                                            
                                                            
Welcome to QA-Tools, Legacy Edition (© PLAID, 1995).

This is not a full view of the AidData QA Tools, but only the limited view relevant to bringing old tools into the fast paced modern fold.
NB: example inputs are *not* legitimate datasets.  They have been altered to allow for the errors which we intend to catch with qa-tools.

# meet the utils!

Legacy utilities are organized into these categories:

* cardinality
  * for determining that data relationships are as they should be
    * eg, only one instance of a unique project_id/geoname_id pair per project table
    * eg, only one precision_code per geoname_id
* dates
  * for determining malformed and inappropriate ISO dates
  * checks incorrect leap days!
  * Gregorian calendar only
* geonames
  * for scraping latest GeoNames from either API or a SQLite database made from the text dumps
  * builds all fields required for locations.tsv
* generic

Utilities typically assume TSV input and print TSV output to STDOUT.

# but when do I use them?

Glad you asked!

## cardinality

### find_notUniqPairs.sh

```bash
# example: find project_id / geoname_id pairs that occur more than once in the locations table
# also reports counts of these violations
# output format: "count_of_pair first_field_value second_field_value"
# this should not happen because our data has (almost) entirely been at project level so there is no need to mention a project location more than once
./find_notUniqPairs.sh locations.tsv 1 2
```

### find_not1to1.sh

```bash
# example: find location_type_codes and location_type_names that are not one-to-one
# this would mean that these codes are not being applied consistenly.  perhaps a code was used for two distinct values.
# output format: "first_field_value"
./find_not1to1.sh locations.tsv 7 8
```

### find_wouldBeDuplicates_byField.sh

```bash
# example: determine if any of the source fields are the only reason records are not duplicates - can help in identifying fields that prevent duplicate detection.
# output format: a TSV, one field for each input field, reporting on the percent of records that would become duplicates if that field were removed
./find_wouldBeDuplicates_byField.sh locations.tsv
```

### find_disagreeingFields_for_notUniqPairs.sh

```bash
# this script combines generic/search_TSVbyTSV.sh and cardinality/find_notUniqPairs.sh to find 
# example: determine the fields which prevent project_id and geoname_id from being unique pairs, for example disagreement in the precision code fields (ie, the same project_id/geoname_id pair might have a precision 6 sometimes and a precision 8 sometimes)
# output format: a TSV with fields for the not unique pair and a pipe separated list of fields that keep that pair from not being unique (note the special case where you have true duplicate records is not covered)
# sadly, that "./" must really be in front of transpose.sh - should fix
./find_disagreeingFields_for_notUniqPairs.sh locations.tsv 1 2 ../../generic/search_TSVbyTSV.sh ../../cardinality/find_notUniqPairs.sh ./transpose_tsv.sh
```

## dates

### findInvalidDates_byField.sh

```bash
# this script finds invalid ISO dates (YYYY-MM-DD) in a double quoted list of ISO date fields in a TSV
# in this example, for each of the ISO date fields 4,5, and 6 in the input TSV, find invalid dates
# note that in the example provided these invalid dates are caught:
# * negative date
# * invalid day of month
# * invalid month of year
# * invalid leap day
# however, note that absuurd but technically correct dates, like the year "8", are not caught
./findInvalidDates_byField.sh example_inputs/NPL_AMP_projects.tsv "4 5 6"
```

## geonames

### fromAPI/get_geonamesFields_fromAPI.sh

This script outputs locations.tsv from the GeoNames API.
Inputs are:

1. input TSV with geoname_id field
1. field number for geoname_id field
1. GeoNames username
  1. note that you *can* be limited in the number of requests per unit time for the GeoNames API

Outputs are a TSV in the style of locations.tsv:

field_num|field_name
---|---
1|geonameID
2|placename
3|latitude
4|longitude
5|location_type_code
6|location_type
7|geonames_ADMcode
8|geonames_ADMname
9|geonamesAPI_retrievalTime

Example run:

```bash
# provide the input TSV with geoname_id field, the number of the geoname_id field, and a valid GeoNames username to query the API
./fromAPI/get_geonamesFields_fromAPI.sh example_inputs/to_geocode.tsv 2 adecatur
```

Note that there are a few reasons to *not* use the fromAPI/ scripts.
The GeoNames API:

* may need to have a geoname_id requested multiple times before it decides to hand you back anything other than NULL
  * hence the geonames/patch_geonamesFields_fromAPI.sh script
* may not have the latest GeoNames
  * this matter because out geocoders often add to geonames
* does not have as comprehensive information about each geoname_id as the text dump
  * this is mostly not a problem for locations.tsv.  However, if in the future we decide we need more GeoNames info, the API may not provide it

For these reasons we may want to use the geonames/fromSQLite script to pull from a text dump.
The drawback with that of course is staying up to date.

### fromAPI/patch_geonamesFields_fromAPI.sh

The GeoNames API sometimes has trouble retrieving non-NULL entries for geoname_ids.
If you do not get an entry for every geoname_id there are a few possibilities:

* GeoNames has never used that ID, or no longer uses it
  * it may have been incorrectly recorded on our end
* GeoNames just added that ID and the API does not have it yet
* GeoNames *has* the information about that ID but refuses to divulge it on the first request

This script handles the last case - when GeoNames does have the information about the ID but will not give it  up so easily.

```bash
# example use: add missing geonames to example_inputs/locations.tsv, put the output in /tmp/out.csv
# 2 and 1 are the field numbers for the placename and geoname_id fields in the input TSV
# adecatur is an example GeoNames username
./patch_geonamesFields_fromAPI.sh example_inputs/locations.tsv ./get_geonamesFields_fromAPI.sh 2 1 adecatur /tmp/out.csv
```

### fromSQLite/get_geonamesFields_fromSQLite.sh

This script is an alternative to the fromAPI/ scripts to get the fields needed for locations.tsv.
The strategy is to query a SQLite database with the GeoNames text dumps.
The SQLite database that you need to use with this script can be built with the [geonames2sqlite](https://github.com/albert-decatur/geonames2sqlite) repo.
Once you build that SQLite database, all you have to do is run the script just like you did with fromAPI/get_geonamesFields_fromAPI.sh, except with the path to the database instead of your GeoNames username:

```bash
# use your GeoNames SQLite database to get locations.tsv fields for geoname_id in input TSV
./get_geonamesFields_fromSQLite.sh ../example_inputs/to_geocode.tsv 2 /path/to/geonameSQLiteDB/geonames_YYYY-MM-DD.sqlite
```

NB: 

* you should rebuild your SQLite database of GeoNames on occaison to keep up to date.
* [geonames2sqlite](https://github.com/albert-decatur/geonames2sqlite) does not yet handle the following properly:
  * when GeoNames entries have the wrong number of fields
    * this is typically due to GeoNames inserting a line break inappropriately
  * when GeoNames entries themselves are quoted
    * this is common
* for get_geonamesFields_fromSQLite.sh, the geonamesAPI_retrievalTime field refers not to the retrieval time but the modification time in the GeoNames text dump

## generic

### find_invalidEntries_givenTable.sh

This script will find invalid combinations of values from two fields given an input TSV and an allowable combos TSV.

```bash
# in this example, fine location type / precision code pairs in Nepal project locations that fall outside the allowable list called loctypes_allowable.tsv
./find_invalidEntries_givenTable.sh example_inputs/NPL_geocoded_projectLocations.tsv 8 3 example_inputs/loctypes_allowable.tsv
```

### find_null_byField.sh

```bash
# in this example, for each field in the input TSV, count the number of records that match the regex, and report on the percent of each field this is
# NB: this regex could be anything - searching for nulls is simply an obvious application
./find_null_byField.sh example_inputs/NPL_geocoded_projectLocations.tsv "^(\s|0)*$"
```

### multi_field_join.sh

Join two TSVs by more than one field at once, for example project_id and geoname_id.
This simply concatenates these fields and removes the duplicates after the join.

```bash
# in this example, join on the first two fields of each TSV, concatenating their output and removing fields that were duplicated due to the join
# this example uses the outer join type but right and left are possible, as well as inner which is called by not specifying a type (as per csvjoin)
./multi_field_join.sh example_inputs/NPL_AMP_projects.tsv example_inputs/NPL_geocoded_projectLocations.tsv "1 2" outer
```

### make_concat_field.sh

Concatenate fields from a TSV.

```bash
# in this example, concatenate the first two fields to make an ID field
# put that field at the front of the new TSV
# arguments are the input TSV, the fields to concatenate, and the name of the new output field
./make_concat_field.sh example_inputs/NPL_AMP_projects.tsv 1 2 ID_field
```

### 


```bash
```

### 


```bash
```

### 


```bash
```

# prerequisites

* mawk
  * like awk but much faster.  awk is a "data-driven" programming language for plain text tables.
* GNU parallel
  * for processing across all cores, potentially multiple hosts
* Gnumeric
  * for ssconvert
    * might be replaced with in2csv, but need outputs to be tabs as is
* csvkit
* moreutils
  * for mktemp, and potentially sponge
    * note that moreutils has a util named parallel.  this comes into conflict with GNU parallel which must be compiled from source
