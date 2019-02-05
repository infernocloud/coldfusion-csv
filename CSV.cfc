
// https://github.com/infernocloud/coldfusion-csv
component {
	// Get a newline seperator character
	variables.newline = createObject("java", "java.lang.System").getProperty("line.separator");

	// We use a temporary qualifier that will be replaced by double quote after escaping double quotes within row items
	// Doing this after adding the row items to the CSV string buffer dramatically increases processing speed
	variables.tempQualifier = "{^}";

	// csvToArray() is forked from https://gist.github.com/bennadel/9760097#file-code-1-cfm and converted to full cfscript.
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

		// Create a compiled Java regular expression pattern object
		// for the expression that will be parsing the CSV.
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

	// arrayToCSV takes an array of arrays where each outer array item is an array representing a row of data that should be printed in a CSV document
	// Using java.lang.StringBuffer over Coldfusion's array concatenation is about 10 times faster
	// Using Java Iterators is about 10% faster than accessing the arrays using Coldfusion's for loops

	// Note about switching from a loop for each row item to using toList():
	// Removing this inner loop significantly speeds up CSV creation
	// Previous version with item loops did 100k rows with 20 columns in 40 seconds
	// Version with hacky toList does the same 100k rows with 20 columns in 3.788 seconds
	public string function arrayToCSV(required array arr, array header = []) {
		var csvText = createObject("java", "java.lang.StringBuffer");

		// Build header if needed
		if (header.len() > 0) {
			// Instead of looping over each header label to add qualifiers, just convert to string with the qualifiers and comma as the separator
			csvText.append(JavaCast("string", variables.tempQualifier & header.toList("#variables.tempQualifier#,#variables.tempQualifier#") & variables.tempQualifier & newline));
		}

		// Each row
		var arrIter = arr.Iterator();

		while (arrIter.hasNext()) {
			// Get the row array
			var row = arrIter.next();

			// Instead of looping over each header label to add qualifiers, just convert to string with the qualifiers and comma as the separator
			csvText.append(JavaCast("string", variables.tempQualifier & row.toList("#variables.tempQualifier#,#variables.tempQualifier#") & variables.tempQualifier & newline));
		}

		// Waiting until the very end to escape quotes and add qualifier quotes speeds this up by more than double
		var escapedCSV = escapeCSV(csvText.toString());

		return escapedCSV;
	}

	// Based on Ben Nadel's updated function but with tons of optimizations https://gist.github.com/bennadel/9753130#file-code-1-cfm
	// header array will take each element and replace the corresponding column name in the header
	// If there is no corresponding header array element or it is empty string, the query column name will be used in the header
	// To make blank header labels, use a single space character
	public string function queryToCSV(required query q, array header = []) {
		var csvText = createObject("java","java.lang.StringBuffer");
		var queryRowCount = q.recordcount;
		var rowData = [];
		var colIndex = 1;
		var rowIndex = 1;

		// Build header
		var queryColumns = q.getColumnNames();
		var queryColumnsLen = arrayLen(queryColumns);

		// Build array of qualified column names
		for (colIndex = 1; colIndex <= queryColumnsLen; colIndex++) {
			var columnLabel = queryColumns[colIndex];

			// If a different label has been passed in for this header, use it instead
			if (header.isDefined(colIndex) && header[colIndex].len() > 0) {
				columnLabel = trim(header[colIndex]);
			}

			rowData[colIndex] = variables.tempQualifier & columnLabel & variables.tempQualifier;
		}

		// Append row data to the string buffer as a comma separated list (and a newline after the header line)
		csvText.append(JavaCast("string", arrayToList(rowData) & newline));

		// Append each row of the query data
		for (rowIndex = 1; rowIndex <= queryRowCount; rowIndex++) {
			rowData = [];

			for (colIndex = 1; colIndex <= queryColumnsLen; colIndex++) {
				// Add the field to the row data
				rowData[colIndex] = variables.tempQualifier & q[queryColumns[colIndex]][rowIndex] & variables.tempQualifier;
			}

			// Append the row data to the string buffer
			// @TODO can we just use arrayToList with a delimiter of "#variables.tempQualifier#,#variables.tempQualifier#" and surround that with variables.tempQualifier instead of looping over each column value?
			// Will this speed up the conversion even more?
			csvText.append(JavaCast("string", arrayToList(rowData) & newline));
		}

		// Waiting until the very end to escape quotes and add qualifier quotes speeds this up by more than double
		var escapedCSV = escapeCSV(csvText.toString());

		return escapedCSV;
	}

	public void function serveCSV(required string filename, required any data, array header = []) {
		var csvText = "";

		// Is data a query object?
		if (isQuery(data)) {
			csvText = queryToCSV(data, header);
		}

		// Is data an array? (An array with each element being an array of row values)
		if (isArray(data)) {
			csvText = arrayToCSV(data, header);
		}

		// Is data already a CSV string?
		if (isSimpleValue(data)) {
			csvText = data;
		}

		// Serve the text as a browser attachment to download
		cfheader(name = "Content-Disposition", value = "attachment; filename=#filename#.csv");
		cfcontent(type = "text/csv", variable = ToBinary(ToBase64(csvText)), reset = true);
	}

	private string function escapeCSV(required string csv) {
		// Escape double quotes
		csv = replace(csv, """", """""", "all");

		// Add actual qualifier double quotes around row items
		return replace(csv, variables.tempQualifier, """", "all");
	}
}
