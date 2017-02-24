package classes {
	import flash.utils.Dictionary;
	import classes.SyntaxColor;
	import classes.TimeObject;
	import classes.Step;
	import classes.StringUtils;
	import com.inruntime.utils.*;
	import flash.events.*;
	import flash.filesystem.*;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.utils.Dictionary;


	public class CogulatorPlusProcessor {

		private static var $: Global = Global.getInstance();
		var ops: TextLoader;
		var stateTable: Dictionary = new Dictionary();
		var lines: Array = new Array();


		
		public function CogulatorPlusProcessor() {

			//ops = new TextLoader("cogulator/models/Examples/ifTest.goms");
			//ops.addEventListener("cogulator/models/Examples/ifTest.goms", parseFile);
			//	//var codeLines = $.codeTxt.text.split('/r');
		}

		//Purpose: Get rid of all CreateState,SetState,If, and EndIf, GoTos
		//Input: None, input taken from $Global
		//Output: Array wrappedLines:  CPM-GOMS model in the format of original cogulator
		//
		//Note: whitespace characters and lineEndings don't always work.  Revisit \n vs \r
		public function process():String{
			//For all those pesky whitespace characters
			lines = $.codeTxt.text.split('\r');
			for (var WhiteSpaceCounter: int = 0; WhiteSpaceCounter < lines.length; WhiteSpaceCounter++) {
				lines[WhiteSpaceCounter] = StringUtils.trim(lines[WhiteSpaceCounter]);
			}

			//The model that will be fed to the GOMS processor
			var wrappedLines: Array = new Array();

			//Get rid of all CreateState,SetState,If, and EndIf, GoTos
			var lineCounter: int = 0;
			while (lineCounter < lines.length) {
				var frontTrimmedLine: String = trimIndents(lines[lineCounter]);
				var tokens: Array = frontTrimmedLine.split(' ');
				switch (tokens[0]) {
					case "CreateState":
						createState(tokens[1], tokens[2]);
						break;
					case "SetState":
						setState(tokens[1], tokens[2]);
						break;
					case "If":
						//should return int of next line to be processed based on the resolution
						//of the if statement.
						lineCounter = nextIfLine(lineCounter);
						break;
					case "EndIf":
						//ignore EndIfs, but are useful in processing original statement.
						break;
					case "GoTo":
						//line should be in the form "GoTo Goal: goal_name" (name can contain spaces)
						var goalName = frontTrimmedLine.substring(frontTrimmedLine.indexOf(':') + 2,frontTrimmedLine.length);
						var goalTable:Dictionary = indexGoalLines();
						lineCounter = goalTable[goalName];
						wrappedLines.push(lines[lineCounter]);
						break;
					default:
						wrappedLines.push(lines[lineCounter]);

				}
				lineCounter++;
			}

			//Print out final result to be fed to GOMSProcessor
/*			trace("wrapper output: ");
			for (var wrapperLinesCounter: int = 0; wrapperLinesCounter < wrappedLines.length; wrapperLinesCounter++) {
				trace(wrappedLines[wrapperLinesCounter]);
			}*/
			return wrappedLines.join("\r");
		}


		//Purpose: finds the lineNumbers of all goals in the program
		//Input: None
		//Output: Dictionary of goals and lines in the form: 
		//		key: goal_name
		//		value: lineNumber
		//Notes: Does not enforce scope
		//		 Goal line assumed to be in the form "...Goal: goal_name"
		function indexGoalLines(): Dictionary {
			var goalIndexesByName = new Dictionary(); //key = goal_name, val=index
			var goalsInScope = new Dictionary();
			
			for (var i = 0; i < lines.length; i++) {
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0] == "Goal:") {
					//Goal line assumed to be in the form "Goal: goal_name"
					var goalName = frontTrimmedLine.substring(6, frontTrimmedLine.length);
					goalIndexesByName[goalName] = i;
				}
			}
			return goalIndexesByName;
		}


		//Purpose: Finds next value of lineCounter. 
		//Input: Int lineCounter: lineNumber of Current If-statement
		//Output: int: the lineNumber of the next statement to be processed
		//	ifTrue: lineCounter - continue processing where you are.
		//	ifFalse: the line of the matching EndIf;
		function nextIfLine(lineCounter: int): int {
			var ifIsTrue: Boolean = evaluateIfStatement(lines[lineCounter]);
			if (ifIsTrue) {
				//do not jump any lines, lineCounter in parseloop will iterate to next line
				return lineCounter;
			} else {
				//Jump to the end of the ifStatement
				return findMatchingEndIf(lineCounter);
			}
		}


		//Purpose: Returns the lineNumber of the matching EndIf
		//Input: Int lineCounter, the lineNumber of the current if statement
		//Output: int of the matching EndIf
		//		  if no ENDIF is found, returns end of program
		//Notes: Should handle nested ifs (fingers crossed)  
		function findMatchingEndIf(lineCounter:int): int {
			var numIfs: int = 1;
			var numEndIfs: int = 0;
			for (var i = lineCounter + 1; i < lines.length; i++) {
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if (tokens[0] == "If") { //Handles nested ifs
					numIfs++; //for each if found, it must find an additional endif
				} else if (tokens[0] == "EndIf") {
					numEndIfs++;
					if (numEndIfs == numIfs) {
						return i;
					}
				}
			}
			return lines.length;
		}




		//Purpose: Checks the truth value of the input against the statetable
		//Input: String ifLine: already frontTrimmed line (If this_state isTrue)
		//Output: Boolean: if an entry in StateTable matches exactly the key and value
		//
		//Hint: if debugging, check that whitespace characters have been trimmed
		//in both the table and the input
		function evaluateIfStatement(ifLine: String): Boolean {
			//input must be in the form "If key value"
			var key: String = ifLine.split(' ')[1];
			var ifValue: String = ifLine.split(' ')[2];
			var tableValueString = stateTable[key];

			return (tableValueString == ifValue);
		}


		//Purpose: Creates new state in the stateTable, all values are represented as strings.
		//Input: String key, String value (target1, visited)
		//Output: none
		//	SideEffect:  An new entry in global stateTable is added
		//TODO:  Add in error handling
		function createState(key: String, value: String) {
			stateTable[key] = value;
		}

		//Purpose: Changes an existing state in the stateTable, all values are represented as strings.
		//Input: String key, String value (target1, visited)
		//Output: none
		//	SideEffect:  An existing entry in global stateTable is changed
		//TODO:  Add in error handling
		function setState(key: String, value: String) {
			stateTable[key] = value;
		}



		//Purpose: removes spaces and periods from front of line so that we can identify the operator
		//Input: String: raw line 
		//	Example: "...CreateState goal_name value"
		//Output: String: trimmed line 
		//	Example: "CreateState goal_name value"
		function trimIndents(line: String): String {
			while (line.length > 0 && line.charAt(0) == ' ' || line.charAt(0) == '.') {
				line = line.substr(1);
			}
			return line;
		}
	}
}