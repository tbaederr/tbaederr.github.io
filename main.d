import std.json;
import std.stdio;
import std.file;
import std.array;
import std.string;
import std.format;
import std.conv: to;
import std.algorithm: sort, map, sum;
import std.algorithm.searching: find;



const string GIT_REPO = "https://github.com/tbaederr/trace-files";



pure bool isRelevantEvent(const ref JSONValue V) {
	return V["name"].str == "EvaluateForOverflow" ||
	       V["name"].str == "EvaluateAsRValue" ||
	       V["name"].str == "EvaluateAsBooleanCondition" ||
	       V["name"].str == "EvaluateAsBooleanInt" ||
	       V["name"].str == "EvaluateAsBooleanFixedPoint" ||
	       V["name"].str == "EvaluateAsBooleanFloat" ||
	       V["name"].str == "EvaluateAsLValue" ||
	       V["name"].str == "EvaluateAsConstantExpr" ||
	       V["name"].str == "EvaluateAsInitializer" ||
	       V["name"].str == "EvaluateKnownConstInt" ||
	       V["name"].str == "EvaluateKnownConstIntCheckOverflow" ||
	       V["name"].str == "isIntegerConstantExpr" ||
	       V["name"].str == "EvaluateWithSubstitution" ||
	       V["name"].str == "isPotentialConstantExpr";
}

struct Event {
	string name;
	string detail;
	size_t duration; // Nanoseconds.

	pure bool opEquals(const ref Event E) {
		return E.name == name && E.detail == detail;
	}
}

Event[] readTraceEvents(string filename) {
	auto text = readText(filename);
	JSONValue root = parseJSON(text);

	//writeln(root);

	Event[] events;
	foreach (JSONValue V; root["traceEvents"].array()) {
		if (!V.isRelevantEvent())
			continue;

		//writeln(V);
		events ~= Event(V["name"].str, V["args"]["detail"].str, to!size_t(V["dur"].integer));
	}

	return events;
}

struct ParsedDetail {
	string filePath;
	string filename;
	string fromLine;
	string toLine;
}

ParsedDetail parseDetail(string s) {
	
	// Drop leading <
	s  = s[1..$];
	size_t firstColon = s.indexOf(':');
	if (firstColon == -1) {
		return ParsedDetail("", "", "");
	}

	string filePath = s[0..firstColon];
	string filename = filePath[filePath.lastIndexOf('/')+1..$];
	string fromLine = s[firstColon + 1..s.indexOf(':', firstColon + 1)];

	// TODO: Multiline stuff.
	return ParsedDetail(filePath, filename, fromLine, fromLine);
}


pure string escape(string s) {
	return s.replace("<", "&lt;").replace(">", "&gt;");
}


void main(string[] args) {
	if (args.length < 3) {
		writeln("Must pass input files");
		return;
	}

	size_t limit = 1000;
	if (args.length == 4) {
		if (args[3][0] == '-')
			limit = cast(size_t)-1;
		else
			limit = to!size_t(args[3]);
	}

	Event[] oldEvents = readTraceEvents(args[1]);
	Event[] newEvents = readTraceEvents(args[2]);

	size_t sumOldEvents = oldEvents.map!(e => e.duration).sum();
	size_t sumNewEvents = newEvents.map!(e => e.duration).sum();

	writeln("Old events: ", oldEvents.length);
	writeln("New events: ", newEvents.length);

	// Sort by duration. Longest first.
	oldEvents.sort!("a.duration > b.duration");

	string html = "<html>\n";
	html ~= "<head><link rel=\"stylesheet\" href=\"style.css\"></head>\n";
	html ~= "<body>\n";

	if (newEvents.length != oldEvents.length) {
		html ~= "<p class=\"omg\">There are " ~ to!string(newEvents.length) ~ " new events and "
			 ~ to!string(oldEvents.length) ~ " old events!</p>";
	}

	html ~= "<table>\n";
	html ~= "<tr><th>Event</th><th>Old</th><th>New</th><th>Diff</th></tr>\n";

	// Sum row.
	{
		html ~= "<tr><td>Sum</td><td>" ~ to!string(sumOldEvents) ~ "</td>";
		string cssClass = sumNewEvents < sumOldEvents ? "nice" : (sumOldEvents == sumNewEvents ? "fine" : "meh");
		html ~= "<td class=\"" ~ cssClass ~ "\">" ~ to!string(sumNewEvents) ~ "</td>";
		double diff = cast(double)sumNewEvents - cast(double)sumOldEvents;
		double percent = diff / cast(double)sumNewEvents;
		html ~= "<td>" ~ (percent > 0 ? "+" : "") ~ format("%.2f", percent) ~ "%</td></tr>\n";
	}

	size_t i = 0;
	foreach (const ref Event E; oldEvents) {
		// Find corresponding event in newEvents.
		// This is O(n²), but whatever.
		Event[] N = find(newEvents, E);

		ParsedDetail PD = parseDetail(E.detail);
		string linkUrl = GIT_REPO ~ "/blob/main/" ~ PD.filename ~ "#L" ~ PD.fromLine;
		html ~= "<tr><td class=\"eventname\"><a href=\"" ~ linkUrl ~ "\">" ~ E.name ~ " (" ~ escape(E.detail) ~ ")</a></td>";

		html ~= "<td>" ~ to!string(E.duration) ~ "</td>";
		if (N.length > 0) {
			size_t newDuration = N[0].duration;
			string cssClass = newDuration < E.duration ? "nice" : (newDuration == E.duration ? "fine" : "meh");
			html ~= "<td class=\"" ~ cssClass ~ "\" >" ~ to!string(N[0].duration) ~ "</td>";

			double diff = cast(double)newDuration - cast(double)E.duration;
			double percent = diff / cast(double)E.duration;
			html ~= "<td>" ~ (percent > 0 ? "+" : "") ~ format("%.2f", percent * 100) ~ "%</td>";

		} else {
			html ~= "<td>--</td>";
			html ~= "<td>--</td>";
		}


		html ~= "</tr>\n";

		++i;
		if (i % 1000 == 0) {
			writeln("Event ", i);
		}

		if (i == limit)
			break;
	}

	html ~= "</table></body></html>";
	std.file.write("index.html", html);
}
