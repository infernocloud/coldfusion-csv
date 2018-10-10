
// https://github.com/infernocloud/coldfusion-csv
component {
	// Get a newline seperator character
	variables.newline = createObject("java", "java.lang.System").getProperty("line.separator");

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

	// arrayToCSV takes an array of arrays where each outer array item is an array representing a row of data that should be printed in a CSV document
	// Using java.lang.StringBuffer over Coldfusion's array concatenation is about 10 times faster
	// Using Java Iterators is about 10% faster than accessing the arrays using Coldfusion's for loops
	public string function arrayToCSV(required array arr, array header = []) {
		var csvText = createObject("java", "java.lang.StringBuffer");

		// Build header if needed
		if (header.len() > 0) {
			var headerIter = header.Iterator();

			while (headerIter.hasNext()) {
				var heading = headerIter.next();

				// Each heading is qualified inside of double quotes
				csvText.append(JavaCast("string", """" & escapeDoubleQuotes(heading) & """"));

				// Comma separated values in the header row
				if (headerIter.hasNext()) {
					csvText.append(",");
				}
			}

			// Newline after header
			csvText.append(newline);
		}

		// Each row
		var arrIter = arr.Iterator();

		while (arrIter.hasNext()) {
			// Get the row array
			var row = arrIter.next();
			var rowIter = row.Iterator();

			while (rowIter.hasNext()) {
				var item = rowIter.next();

				// Each row item is qualified inside of double quotes
				csvText.append(JavaCast("string", """" & escapeDoubleQuotes(item) & """"));

				// Comma separated values in each data row
				if (rowIter.hasNext()) {
					csvText.append(",");
				}
			}

			// Newline after each row
			csvText.append(newline);
		}

		return csvText.toString();
	}

	// @TODO to clean up
	// Based on Ben Nadel's updated function but with tons of optimizations https://gist.github.com/bennadel/9753130#file-code-1-cfm
	public string function queryToCSV(required query q, array header = []) {
		var newline = createobject("java", "java.lang.System").getProperty("line.separator");
		var csvText = createObject("java","java.lang.StringBuffer");

		cftimer(label = "#q.recordcount#: queryToCSVNadelScript", type = "debug") {

		// Build header
		var records = q.recordcount;
		var queryColumns = q.getColumnNames();
		var queryColumnsLen = arrayLen(queryColumns);
		var rowData = [];
		var colIndex = 1;
		var rowIndex = 1;

		// writedump(getMetadata(queryColumns)); abort;

		// Build array of qualified column names
		for (colIndex = 1; colIndex <= queryColumnsLen; colIndex++) {
			// rowData[colIndex] = """#escapeDoubleQuotes(queryColumns[colIndex])#""";

			rowData[colIndex] = "{quot}#queryColumns[colIndex]#{quot}";

			// @TODO removing escapeDoubleQuotes() halves execution time :(
			// rowData[colIndex] = """#replace(queryColumns[colIndex], """", """""", "all")#""";
		}

		// Append row data to the string buffer
		csvText.append(JavaCast("string", arrayToList(rowData) & newline));
		// csvText.append(JavaCast("string", outputCSVRow(rowData) & newline));

		// Append each row of the query data
		for (rowIndex = 1; rowIndex <= records; rowIndex++) {
			rowData = [];

			for (colIndex = 1; colIndex <= queryColumnsLen; colIndex++) {
				// Add the field to the row data
				// rowData[colIndex] = """#escapeDoubleQuotes(q[queryColumns[colIndex]][rowIndex])#""";

				rowData[colIndex] = "{quot}#q[queryColumns[colIndex]][rowIndex]#{quot}";

				// @TODO removing escapeDoubleQuotes() halves execution time :(
				// rowData[colIndex] = """#replace(q[queryColumns[colIndex]][rowIndex], """", """""", "all")#""";
			}

			// Append the row data to the string buffer
			csvText.append(JavaCast("string", arrayToList(rowData) & newline));
			// csvText.append(JavaCast("string", outputCSVRow(rowData) & newline));
		}

		// Waiting until the very end to escape quotes and add qualifier quotes speeds this up by more than double
		var escapedCSV = escapeCSV(csvText.toString());
		}

		return escapedCSV;
	}

	// escapeDoubleQuotes will find any existing double quotes (") and will escape them for
	// @TODO should this check for already escaped quotes and leave them alone?
	private string function escapeDoubleQuotes(required string input) {
		return replace(input, """", """""", "all");
	}

	private string function outputCSVRow(required array row) {
		var rowString = row.toList();

		// Escape double quotes
		rowString = replace(rowString, """", """""", "all");

		// Add actual qualifier double quotes around row items
		return replace(rowString, "{quot}", """", "all");
	}

	private string function escapeCSV(required string csv) {
		// Escape double quotes
		csv = replace(csv, """", """""", "all");

		// Add actual qualifier double quotes around row items
		return replace(csv, "{quot}", """", "all");
	}
}
