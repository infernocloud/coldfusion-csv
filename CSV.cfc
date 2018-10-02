
// https://github.com/infernocloud/coldfusion-csv
// csvToArray() is forked from https://gist.github.com/bennadel/9760097#file-code-1-cfm and converted to full cfscript.
component {
	// I take a CSV file or CSV data value and convert it to an array of arrays based on the given field delimiter. Line delimiter is assumed to be new line / carriage return related.
	// file is the optional file containing the CSV data.
	// csv is the CSV text data (if the file argument was not used).
	// delimiter is the field delimiter (line delimiter is assumed to be new line / carriage return).
	// trim is whether or not to trim the END of the file for line breaks and carriage returns.
	public array function csvToArray(string file = "", string csv = "", string delimiter = ",", boolean trim = true, boolean includeFirstRow = true) {
		var regEx = "";

		// Check to see if we are using a CSV File. If so, then all we
		// want to do is move the file data into the CSV variable. That
		// way, the rest of the algorithm can be uniform.
		if (len(arguments.file)) {
			// Read the file into Data.
			arguments.csv = fileRead(arguments.file);
		}

		// ASSERT: At this point, no matter how the data was passed in,
		// we now have it in the CSV variable.

		// Check to see if we need to trim the data. Be default, we are
		// going to pull off any new line and carraige returns that are
		// at the end of the file (we do NOT want to strip spaces or
		// tabs as those are field delimiters).
		if (arguments.trim) {
			// Remove trailing line breaks and carriage returns.
			arguments.csv = reReplace(
				arguments.csv,
				"[\r\n]+$",
				"",
				"all"
			);
		}

		// Make sure the delimiter is just one character.
		if (len(arguments.delimiter) != 1) {
			// Set the default delimiter value.
			arguments.delimiter = ",";
		}

		// Now, let's define the pattern for parsing the CSV data. We
		// are going to use verbose regular expression since this is a
		// rather complicated pattern.
		// NOTE: We are using the verbose flag such that we can use
		// white space in our regex for readability.
		cfsavecontent(variable = "regEx") {
			writeoutput('(?x)');

			// Make sure we pick up where we left off.
			writeoutput('\G');

			// We are going to start off with a field value since
			// the first thing in our file should be a field (or a
			// completely empty file).
			writeoutput('(?:');
				// Quoted value - GROUP 1
				writeoutput('"([^"]*+ (?>""[^"]*+)* )"');

				writeoutput('|');

				// Standard field value - GROUP 2
				writeoutput('([^"\#arguments.delimiter#\r\n]*+)');
			writeoutput(')');

			// Delimiter - GROUP 3
			writeoutput('(
				\#arguments.delimiter# |
				\r\n? |
				\n |
				$
			)');
		}

		//	Create a compiled Java regular expression pattern object
		//	for the experssion that will be parsing the CSV.
		var pattern = createObject(
			"java",
			"java.util.regex.Pattern"
		).compile(
			javaCast("string", regEx)
		);

		// Now, get the pattern matcher for our target text (the CSV
		// data). This will allows us to iterate over all the tokens
		// in the CSV data for individual evaluation.
		var matcher = pattern.matcher(
			javaCast("string", arguments.csv)
		);

		// Create an array to hold the CSV data. We are going to create
		// an array of arrays in which each nested array represents a
		// row in the CSV data file. We are going to start off the CSV
		// data with a single row.
		// NOTE: It is impossible to differentiate an empty dataset from
		// a dataset that has one empty row. As such, we will always
		// have at least one row in our result.
		var csvData = [[]];

		// Here's where the magic is taking place; we are going to use
		// the Java pattern matcher to iterate over each of the CSV data
		// fields using the regular expression we defined above.
		// Each match will have at least the field value and possibly an
		// optional trailing delimiter.
		while (matcher.find()) {
			// Next, try to get the qualified field value. If the field
			// was not qualified, this value will be null.
			var fieldValue = matcher.group(
				javaCast("int", 1)
			);

			// Check to see if the value exists in the local scope. If
			// it doesn't exist, then we want the non-qualified field.
			// If it does exist, then we want to replace any escaped,
			// embedded quotes.
			if (structKeyExists(local, "fieldValue")) {
				// The qualified field was found. Replace escaped
				// quotes (two double quotes in a row) with an unescaped
				// double quote.
				fieldValue = replace(
					fieldValue,
					"""""",
					"""",
					"all"
				);
			} else {
				// No qualified field value was found; as such, let's
				// use the non-qualified field value.
				fieldValue = matcher.group(
					javaCast("int", 2)
				);
			}

			// Now that we have our parsed field value, let's add it to
			// the most recently created CSV row collection.
			arrayAppend(
				csvData[arrayLen(csvData)],
				fieldValue
			);

			// Get the delimiter. We know that the delimiter will always
			// be matched, but in the case that it matched the end of
			// the CSV string, it will not have a length.
			var matchedDelimiter = matcher.group(
				javaCast("int", 3)
			);

			// Check to see if we found a delimiter that is not the
			// field delimiter (end-of-file delimiter will not have
			// a length). If this is the case, then our delimiter is the
			// line delimiter. Add a new data array to the CSV
			// data collection.
			if (len(matchedDelimiter) && matchedDelimiter != arguments.delimiter) {
				// Start new row data array.
				arrayAppend(
					csvData,
					[]
				);
			} else if (!len(matchedDelimiter)) {
				// If our delimiter has no length, it means that we
				// reached the end of the CSV data. Let's explicitly
				// break out of the loop otherwise we'll get an extra
				// empty space.
				break;
			}
		}

		if (!includeFirstRow) {
			arrayDeleteAt(csvData, 1);
		}

		// At this point, our array should contain the parsed contents
		// of the CSV value as an array of arrays. Return the array.
		return csvData;
	}
}
