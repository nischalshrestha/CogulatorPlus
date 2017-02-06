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


	public class BranchingFunctionalityWrapper {

		private static var $: Global = Global.getInstance();
		var ops: TextLoader;
		var stateTable: Dictionary = new Dictionary();


		//
		public function BranchingFunctionalityWrapper() {

			ops = new TextLoader("cogulator/models/Examples/newModelText.goms");
			ops.addEventListener("cogulator/models/Examples/newModelText.goms", parseFile);
			//	//var codeLines = $.codeTxt.text.split('/r');
		}

		function parseFile(evt: Event): void {
			//For all those pesky whitespace characters
			var lines: Array = ops.txt.split('\n');
			for (var removeWhiteSpaceCounter: int = 0; removeWhiteSpaceCounter < lines.length; removeWhiteSpaceCounter++) {
				lines[removeWhiteSpaceCounter] = StringUtils.trim(lines[removeWhiteSpaceCounter]);
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
						//should return int of next line to be processed.
						lineCounter += nextIfLine(lines.slice(lineCounter, lines.length));
						break;
					case "EndIf":
						//ignore EndIfs, but are useful in processing original statement.
						break;
					case "GoTo":
						//line should be in the form "GoTo Goal: goal_name" (name can contain spaces)
						var goalName = frontTrimmedLine.substring(frontTrimmedLine.indexOf(':') + 2,frontTrimmedLine.length);
						var goalTable:Dictionary = indexGoalLines(lines, lineCounter);
						lineCounter = goalTable[goalName];
						wrappedLines.push(lines[lineCounter]);
						break;
					default:
						wrappedLines.push(lines[lineCounter]);

				}
				lineCounter++;
			}

			/*for (var wrapperLinesCounter: int = 0; wrapperLinesCounter < wrappedLines.length; wrapperLinesCounter++) {
				trace(wrappedLines[wrapperLinesCounter]);
			}*/



		}


		//Does not enforce scope
		function indexGoalLines(lines: Array, curGoToLine:int): Dictionary {
			var goalIndexesByName = new Dictionary(); //key = goal_name, val=index
			var goalsInScope = new Dictionary();
			
			for (var i = 0; i < lines.length; i++) {
				var frontTrimmedLine: String = trimIndents(lines[i]);
				var tokens: Array = frontTrimmedLine.split(' ');
				if(i = curGoToLine){
					trace("Found current goTo");
				}
				if(tokens[0] == "If"){
					
				} else if (tokens[0] == "EndIf"){
				
				} else if (tokens[0] == "Goal:"){
					var goalName = frontTrimmedLine.substring(6, frontTrimmedLine.length);
					goalsInScope[goalName] = i;
				}
				/*if (tokens[0] == "Goal:") {
					var goalName = frontTrimmedLine.substring(6, frontTrimmedLine.length);
					goalIndexesByName[goalName] = i;
				}*/
			}
			return goalIndexesByName;
		}


		//Input: subset of lines iwth ifstatement on line 0;
		//Output: int: the number of lines the lineCounter should jump
		//	ifTrue: 0;
		//	ifFalse: the line of the matching EndIf;
		function nextIfLine(ifStatementAndBeyond: Array): int {
			var ifIsTrue: Boolean = evaluateIfStatement(ifStatementAndBeyond[0]);
			if (ifIsTrue) {
				//do not jump any lines, lineCounter in parseloop will iterate to next line
				return 0;
			} else {
				//Jump to the end of the ifStatement
				return findMatchingEndIf(ifStatementAndBeyond);
			}
		}


		//Input: subset of total lines with ifstatement on line 0;
		//Output: int of the matching EndIf
		//Notes: Should handle nested ifs (fingers crossed)
		function findMatchingEndIf(lines: Array): int {
			var numIfs: int = 1;
			var numEndIfs: int = 0;
			for (var i = 1; i < lines.length; i++) {
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




		//Checks the truth value of the input against the statetable
		//Hint: if debugging, check that whitespace characters have been trimmed
		//in both the table and the input
		function evaluateIfStatement(ifLine: String): Boolean {
			//input must be in the form "If key value"
			var key: String = ifLine.split(' ')[1];
			var ifValue: String = ifLine.split(' ')[2];
			var tableValueString = stateTable[key];

			return (tableValueString == ifValue);
		}


		//Changes an existing state, all values are represented as strings.
		//TODO:  Add in error handling
		function createState(key: String, value: String) {
			stateTable[key] = value;
			trace("Created state: " + key + " with value: " + value);
		}

		//Adds a state into the stateTable, all values are represented as strings.
		//TODO:  Add in error handling
		function setState(key: String, value: String) {
			stateTable[key] = value;
			trace("Changed state: " + key + " with value: " + value);
		}



		//removes spaces and periods from front of line so that we can identify the operator
		function trimIndents(line: String): String {
			while (line.length > 0 && line.charAt(0) == ' ' || line.charAt(0) == '.') {
				line = line.substr(1);
			}
			return line;

		}



	}

}